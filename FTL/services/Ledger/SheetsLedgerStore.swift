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
        try await bootstrap()

        let rows = try await sheets.read(
            range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, SheetsSchema.transactionRange)
        )
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

    /// Idempotent on `id`. A retry after an ambiguous failure reads back first and
    /// appends only what is missing — never appends twice, and never assumes the
    /// first attempt failed.
    func append(_ transactions: [LedgerTransaction]) async throws {
        guard !transactions.isEmpty else { return }
        let existing = Set(try await all().map(\.id))
        let fresh = transactions.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }

        try await sheets.append(
            range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, SheetsSchema.transactionRange),
            values: fresh.map(SheetsSchema.row(from:)),
            inputOption: "RAW"
        )
        cache = nil
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

    /// Creates the tabs and headers on first use. Safe to call repeatedly; it
    /// never touches a tab that already exists.
    private func bootstrap() async throws {
        guard !didBootstrap else { return }
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
        didBootstrap = true
    }

    /// A new sheet gets bucket names but no ceilings. Names are needed before
    /// anything can be tagged; the numbers are the user's to set, and inventing
    /// them would be the app deciding what they should spend.
    private static var starterBudgets: [[String]] {
        let total = CategoryID(rawValue: "total")
        let leaves = [("food", "Food"), ("transport", "Transport"),
                      ("shopping", "Shopping"), ("subscriptions", "Subscriptions")]
        return [SheetsSchema.row(categoryID: total, name: "Total", parentID: nil, ceiling: .zero, month: "")]
            + leaves.map { id, name in
                SheetsSchema.row(
                    categoryID: CategoryID(rawValue: id), name: name,
                    parentID: total, ceiling: .zero, month: ""
                )
            }
    }
}
