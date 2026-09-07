//
//  LegacyMigration.swift
//  FTL — services/Ledger
//
//  One-time migration from the Phase-0 month-named tabs (Debug harness format)
//  to the Phase-1 `transactions` tab (SheetsSchema format).
//
//  The debug harness wrote [Date, Category, Description, Amount] into tabs named
//  "September 2026", etc.  The dashboard reads from the `transactions` tab with
//  16 columns.  This bridges the two.
//
//  Bypasses the approval gate deliberately: these are the user's own manually
//  entered rows, not model output, and presenting every import as a provisional
//  entry for individual approval would make the migration impractical.
//

import Foundation

actor LegacyMigration {
    private let auth: GoogleAuthManager
    private let ledger: LedgerStore

    init(auth: GoogleAuthManager, ledger: LedgerStore) {
        self.auth = auth
        self.ledger = ledger
    }

    struct MigrationResult: Sendable {
        let tabsScanned: Int
        let rowsMigrated: Int
        let rowsSkipped: Int
    }

    /// Scans every month-named tab ("September 2026", etc.), converts its rows
    /// to `LedgerTransaction`, and appends to the canonical `transactions` tab.
    ///
    /// Safe to call twice: `SheetsLedgerStore.append` is idempotent on `id`.
    /// However, each call generates new UUIDs, so a second run would create
    /// duplicates.  Guard with a flag on the call site.
    func migrate() async throws -> MigrationResult {
        let sheets = SheetsService(auth: auth)
        let allTabs = try await sheets.tabTitles()

        let reserved: Set<String> = [
            SheetsSchema.Tab.transactions,
            SheetsSchema.Tab.budgets,
            "Sheet1",
        ]

        let monthTabs = allTabs.filter { tab in
            !reserved.contains(tab) && Self.monthFormatter.date(from: tab) != nil
        }

        var transactions: [LedgerTransaction] = []
        var skipped = 0

        for tab in monthTabs {
            let rows = try await sheets.read(range: SheetsService.a1(tab: tab, "A:D"))
            for row in rows.dropFirst() {                       // drop the header
                guard row.count >= 4,
                      let date = Self.dayFormatter.date(from: row[0].trimmingCharacters(in: .whitespaces)),
                      let amountDouble = Double(row[3].trimmingCharacters(in: .whitespaces))
                else {
                    skipped += 1
                    continue
                }

                // IDR has exponent 0, so minor units = whole rupiah.
                let minorUnits = Int(amountDouble.rounded())
                let category = row[1].trimmingCharacters(in: .whitespaces)
                let description = row[2].trimmingCharacters(in: .whitespaces)
                let now = Date.now

                let tx = LedgerTransaction(
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
                )
                transactions.append(tx)
            }
        }

        if !transactions.isEmpty {
            try await ledger.append(transactions)
        }

        return MigrationResult(
            tabsScanned: monthTabs.count,
            rowsMigrated: transactions.count,
            rowsSkipped: skipped
        )
    }

    // MARK: - Formatters (fixed locale, matching the debug harness)

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "LLLL yyyy"      // "September 2026"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
