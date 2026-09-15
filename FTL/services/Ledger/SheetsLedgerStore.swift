//
//  SheetsLedgerStore.swift
//  FTL — services/Ledger
//
//  The canonical store. Google Sheets is the source of truth; this is the only
//  code that writes to it, and it is reached only through ApprovalService
//  (Invariant 1).
//
//  Rows are cached in memory for the session because every screen reads the whole
//  ledger and the Sheets API is both slow and rate-limited. The cache is
//  invalidated on write, never trusted across a write, and never used to answer a
//  question the sheet could answer differently.
//

import Foundation

actor SheetsLedgerStore: LedgerStore {
    private let auth: GoogleAuthManager
    private var customSpreadsheetID: String?
    private var cache: [LedgerTransaction]?
    private var didBootstrap = false

    private var sheets: SheetsService {
        SheetsService(auth: auth, spreadsheetID: customSpreadsheetID ?? SheetsService.activeSpreadsheetID)
    }

    init(auth: GoogleAuthManager, spreadsheetID: String? = nil) {
        self.auth = auth
        self.customSpreadsheetID = spreadsheetID
    }

    /// Invalidates cache and fetches fresh ledger rows from the active spreadsheet.
    func reload() async throws -> [LedgerTransaction] {
        cache = nil
        didBootstrap = false
        return try await all()
    }

    // MARK: - Reads

    func all() async throws -> [LedgerTransaction] {
        if let cache { return cache }

        // bootstrap() already has to read the full transactions range once, to
        // decide whether the tab is empty (legacy import) — reuse that instead
        // of reading the same range again right after. Only the first call each
        // cold launch pays for bootstrap() at all; every call after that reads
        // once, same as before this existed.
        let rows: [[String]]
        if let bootstrapped = try await bootstrap() {
            rows = bootstrapped
        } else {
            rows = try await sheets.read(
                range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, SheetsSchema.transactionRange)
            )
        }
        // Drop the header, then skip anything unparseable rather than guessing —
        // the sheet is user-editable, so half-typed rows are an expected state.
        let parsed = rows.dropFirst().compactMap(SheetsSchema.transaction(from:))
        cache = parsed
        return parsed
    }

    func transactions(in interval: DateInterval) async throws -> [LedgerTransaction] {
        try await all().filter { interval.containsLedgerDate($0.date) }
    }

    func transaction(id: LedgerTransaction.ID) async throws -> LedgerTransaction? {
        try await all().first { $0.id == id }
    }

    func categories() async throws -> [SpendCategory] {
        try await budgetRows().compactMap { row in
            guard row.count > 1, !row[0].isEmpty else { return nil }
            let parent = row.count > 2 && !row[2].isEmpty ? CategoryID(rawValue: row[2]) : nil
            // Only leaves are spending buckets; the root is the total.
            guard parent != nil else { return nil }
            return SpendCategory(id: CategoryID(rawValue: row[0]), name: row[1], parentID: parent)
        }
    }

    // MARK: - Writes

    /// Idempotent on `id` and deduplicated against existing ledger rows by amount,
    /// normalized merchant, calendar date, and timestamp (LedgerDeduplicator).
    /// Never appends twice, and never creates duplicate sheet rows.
    func append(_ transactions: [LedgerTransaction]) async throws {
        guard !transactions.isEmpty else { return }
        let existing = try await all()
        var fresh: [LedgerTransaction] = []
        for tx in transactions {
            // Deduplicate against already written ledger transactions
            guard !existing.contains(where: { LedgerDeduplicator.isDuplicate($0, tx) }) else { continue }
            // Deduplicate against other transactions in the same append batch
            guard !fresh.contains(where: { LedgerDeduplicator.isDuplicate($0, tx) }) else { continue }
            fresh.append(tx)
        }
        guard !fresh.isEmpty else { return }

        try await sheets.append(
            // Anchored at A1, not the A:P span — see SheetsService.append.
            range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, "A1"),
            values: fresh.map(SheetsSchema.row(from:)),
            inputOption: "RAW"
        )
        cache?.append(contentsOf: fresh)
    }

    /// Rewrites one row in place, located by its id in column A.
    ///
    /// Deliberately NOT the clear-then-rewrite that `delete` below does. That is
    /// a whole-tab replace, and spending it on a one-cell amount correction
    /// means every edit briefly empties the ledger and then depends on the
    /// second call landing — a failure between the two takes the sheet with it.
    /// Finding the row costs one read and lets the write touch sixteen cells.
    ///
    /// The row number cannot come from `all()`: that drops the header and skips
    /// rows it can't parse, so its indices stop matching the sheet's the moment
    /// somebody half-types a row by hand — which the sheet being user-editable
    /// makes an expected state, not an edge case.
    func update(_ transaction: LedgerTransaction) async throws {
        try await bootstrap()
        let rows = try await sheets.read(
            range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, SheetsSchema.transactionRange)
        )

        // A slice keeps its base's indices, so this IS the 0-based row index
        // even though the header was dropped; +1 makes it a 1-based A1 row.
        guard let index = rows.dropFirst().firstIndex(where: { row in
            guard let first = row.first else { return false }
            return UUID(uuidString: first.trimmingCharacters(in: .whitespaces)) == transaction.id
        }) else {
            throw LedgerError.rowNotFound(id: transaction.id)
        }
        let number = index + 1

        try await sheets.write(
            range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, "A\(number):P\(number)"),
            values: [SheetsSchema.row(from: transaction)],
            inputOption: "RAW"
        )
        // Patch the cache rather than dropping it: the row that changed is the
        // one in hand, and every screen behind this sheet is about to re-read.
        cache = cache?.map { $0.id == transaction.id ? transaction : $0 }
    }

    /// Deletes a transaction by its UUID from the transactions tab.
    func delete(_ id: LedgerTransaction.ID) async throws {
        try await bootstrap()
        let current = try await all()
        guard current.contains(where: { $0.id == id }) else { return }
        let remaining = current.filter { $0.id != id }

        // Clear existing transactions range
        try await sheets.clear(
            range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, SheetsSchema.transactionRange)
        )

        // Write back headers + remaining rows
        let values = [SheetsSchema.transactionColumns] + remaining.map(SheetsSchema.row(from:))
        try await sheets.write(
            range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, "A1"),
            values: values,
            inputOption: "RAW"
        )
        cache = remaining
    }

    // MARK: - Budgets tab
    //
    // Shared with SheetsBudgetStore: categories are derived from the same rows
    // that carry the ceilings, so there is no second list to keep in step.

    func budgetRows() async throws -> [[String]] {
        try await bootstrap()
        let rows = try await sheets.read(
            range: SheetsService.a1(tab: SheetsSchema.Tab.budgets, SheetsSchema.budgetRange)
        )
        return Array(rows.dropFirst())
    }

    func writeBudgetRows(_ rows: [[String]]) async throws {
        try await bootstrap()
        // Rewrite the whole tab: it is a handful of rows, and a full replace can't
        // leave a stale ceiling behind the way a partial update can.
        let range = SheetsService.a1(tab: SheetsSchema.Tab.budgets, SheetsSchema.budgetRange)
        try await sheets.write(range: range, values: [SheetsSchema.budgetColumns] + rows, inputOption: "RAW")
    }

    // MARK: - Bootstrap

    /// Creates the tabs and headers on first use, then auto-imports any data
    /// sitting in the Phase-0 month-named tabs (e.g. "September 2026") so the
    /// dashboard works without a manual migration step.
    ///
    /// Returns the transactions tab's rows when this call did the bootstrap
    /// work — it already had to read them to check for emptiness, so `all()`
    /// reuses that instead of reading the same range again right after. Returns
    /// nil on every call after the first one this session (nothing new to
    /// report); callers other than `all()` ignore the return value.
    @discardableResult
    private func bootstrap() async throws -> [[String]]? {
        guard !didBootstrap else { return nil }
        let titles = try await sheets.tabTitles()

        if !titles.contains(SheetsSchema.Tab.transactions) {
            try await sheets.createTab(title: SheetsSchema.Tab.transactions)
            try await sheets.write(
                range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, "A1:P1"),
                values: [SheetsSchema.transactionColumns],
                inputOption: "RAW"
            )
        }

        if !titles.contains(SheetsSchema.Tab.budgets) {
            try await sheets.createTab(title: SheetsSchema.Tab.budgets)
            try await sheets.write(
                range: SheetsService.a1(tab: SheetsSchema.Tab.budgets, "A1:E1"),
                values: [SheetsSchema.budgetColumns] + Self.starterBudgets,
                inputOption: "RAW"
            )
        }

        // If the transactions tab is empty, pull data from any legacy month-named
        // tabs the debug harness created. Runs once — after this the transactions
        // tab has rows and the guard won't fire again.
        var txRows = try await sheets.read(
            range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, SheetsSchema.transactionRange)
        )
        if txRows.dropFirst().isEmpty {
            try await importLegacyMonthTabs(from: titles)
            // The import appended rows directly via sheets.append (see its doc
            // comment on why) — re-read only in this branch, so the common case
            // of an already-populated tab still costs exactly one read.
            txRows = try await sheets.read(
                range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, SheetsSchema.transactionRange)
            )
        }

        didBootstrap = true
        return txRows
    }

    // MARK: - Legacy import

    /// Reads every month-named tab ("September 2026", etc.) and appends its rows
    /// to the `transactions` tab in the 16-column schema.
    ///
    /// Called from `bootstrap()` only when the transactions tab is empty, so it
    /// never creates duplicates during normal use. Uses `sheets.append` directly
    /// rather than `self.append` to avoid a re-entrant `bootstrap()` call.
    private func importLegacyMonthTabs(from allTabs: [String]) async throws {
        let reserved: Set<String> = [
            SheetsSchema.Tab.transactions,
            SheetsSchema.Tab.budgets,
            "Sheet1",
        ]

        let monthTabs = allTabs.filter { tab in
            !reserved.contains(tab) && Self.legacyMonthFormatter.date(from: tab) != nil
        }
        guard !monthTabs.isEmpty else { return }

        var transactions: [LedgerTransaction] = []
        let now = Date.now

        for tab in monthTabs {
            let rows = try await sheets.read(range: SheetsService.a1(tab: tab, "A:D"))
            for row in rows.dropFirst() {
                guard row.count >= 4,
                      let date = Self.legacyDayFormatter.date(from: row[0].trimmingCharacters(in: .whitespaces)),
                      let amountDouble = Double(row[3].trimmingCharacters(in: .whitespaces))
                else { continue }

                // IDR exponent is 0 — minor units are whole rupiah.
                let minorUnits = Int(amountDouble.rounded())
                let category = row[1].trimmingCharacters(in: .whitespaces)
                let description = row[2].trimmingCharacters(in: .whitespaces)

                transactions.append(LedgerTransaction(
                    id: UUID(),
                    date: date,
                    amount: Money(minorUnits: minorUnits, currency: .idr),
                    merchantRaw: description.isEmpty ? "Legacy import" : description,
                    merchant: description.isEmpty ? nil : description,
                    categoryID: category.isEmpty ? nil : CategoryID(rawValue: category),
                    kind: .spend,
                    nonSpendType: nil,
                    source: .manual,
                    sourcesMerged: [],
                    splits: [],
                    lineItems: [],
                    provenance: .manual,
                    flags: [],
                    capturedAt: date,
                    approvedAt: now,
                    notes: "Migrated from \(tab)"
                ))
            }
        }

        guard !transactions.isEmpty else { return }
        try await sheets.append(
            // Anchored at A1, not the A:P span — see SheetsService.append.
            range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, "A1"),
            values: transactions.map(SheetsSchema.row(from:)),
            inputOption: "RAW"
        )
    }

    // MARK: - Static helpers

    /// A new sheet gets bucket names but no ceilings. Names are needed before
    /// anything can be tagged; the numbers are the user's to set, and inventing
    /// them would be the app deciding what they should spend (Invariant 8).
    ///
    /// These seven are the actual categories in use — the ones already driving
    /// the Google Form this ledger was fed from — not a taxonomy the app
    /// invented. Sheets is canonical: TagStore reconciles its own spend
    /// categories FROM the live ledger (`AppEnvironment.reconcileTagStore()`),
    /// so keeping this list in sync with TagStore's is no longer something this
    /// file needs to worry about — it flows the other way now.
    private static var starterBudgets: [[String]] {
        let total = CategoryID(rawValue: "total")
        let leaves = [
            ("food", "Food"),
            ("transport", "Transport"),
            ("housing", "Housing"),
            ("utilities", "Utilities"),
            ("entertainment", "Entertainment"),
            ("shopping", "Shopping"),
            ("other", "Other"),
        ]
        return [SheetsSchema.row(categoryID: total, name: "Total", parentID: nil, ceiling: .zero, month: "")]
            + leaves.map { id, name in
                SheetsSchema.row(
                    categoryID: CategoryID(rawValue: id), name: name,
                    parentID: total, ceiling: .zero, month: ""
                )
            }
    }

    private static let legacyMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "LLLL yyyy"      // "September 2026"
        return f
    }()

    private static let legacyDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

