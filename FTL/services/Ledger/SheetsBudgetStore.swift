//
//  SheetsBudgetStore.swift
//  FTL — services/Ledger
//
//  The target tree, stored on the `budgets` tab alongside the category names so
//  the two can't drift.
//
//  A row's `month` is "2026-09", or blank meaning "applies to every month". Blank
//  is the common case; a month-specific row overrides it. That keeps the sheet
//  readable — five rows, not five per month — while still allowing a one-off.
//

import Foundation

actor SheetsBudgetStore: BudgetStore {
    private let ledger: SheetsLedgerStore

    init(ledger: SheetsLedgerStore) {
        self.ledger = ledger
    }

    func tree(for interval: DateInterval) async throws -> [BudgetNode] {
        let rows = try await ledger.budgetRows()
        let month = SheetsSchema.monthKey(for: interval)

        // Month-specific rows win over the blank-month defaults.
        var ceilings: [CategoryID: Money] = [:]
        var names: [CategoryID: String] = [:]
        var parents: [CategoryID: CategoryID?] = [:]

        for row in rows.sorted(by: { ($0.count > 4 ? $0[4] : "").isEmpty && !($1.count > 4 ? $1[4] : "").isEmpty }) {
            guard row.count > 3, !row[0].isEmpty else { continue }
            let rowMonth = row.count > 4 ? row[4] : ""
            guard rowMonth.isEmpty || rowMonth == month else { continue }

            let id = CategoryID(rawValue: row[0])
            names[id] = row[1]
            parents[id] = row[2].isEmpty ? nil : CategoryID(rawValue: row[2])
            ceilings[id] = Money(minorUnits: Int(row[3]) ?? 0)
        }

        let roots = parents.filter { $0.value == nil }.map(\.key)
        return roots.map { node(id: $0, names: names, parents: parents, ceilings: ceilings) }
    }

    func setCeiling(_ amount: Money, for categoryID: CategoryID, in interval: DateInterval) async throws {
        var rows = try await ledger.budgetRows()
        if let index = rows.firstIndex(where: { $0.first == categoryID.rawValue }) {
            var row = rows[index]
            while row.count < 5 { row.append("") }
            row[3] = String(amount.minorUnits)
            rows[index] = row
        } else {
            rows.append(
                SheetsSchema.row(
                    categoryID: categoryID,
                    name: categoryID.rawValue.capitalized,
                    parentID: CategoryID(rawValue: "total"),
                    ceiling: amount,
                    month: ""
                )
            )
        }
        try await ledger.writeBudgetRows(rows)
    }

    func addCategory(_ category: SpendCategory, under parentID: CategoryID?) async throws {
        var rows = try await ledger.budgetRows()
        guard !rows.contains(where: { $0.first == category.id.rawValue }) else { return }
        rows.append(
            SheetsSchema.row(
                categoryID: category.id, name: category.name,
                parentID: parentID, ceiling: .zero, month: ""
            )
        )
        try await ledger.writeBudgetRows(rows)
    }

    private func node(
        id: CategoryID,
        names: [CategoryID: String],
        parents: [CategoryID: CategoryID?],
        ceilings: [CategoryID: Money]
    ) -> BudgetNode {
        let children = parents
            .filter { $0.value == id }
            .map(\.key)
            .sorted { (names[$0] ?? "") < (names[$1] ?? "") }
            .map { node(id: $0, names: names, parents: parents, ceilings: ceilings) }

        return BudgetNode(
            id: id,
            name: names[id] ?? id.rawValue,
            ceiling: ceilings[id] ?? .zero,
            children: children
        )
    }
}
