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
        
        // Ensure the Emergency category always exists.
        if names[.emergency] == nil {
            names[.emergency] = "Emergency"
            parents[.emergency] = CategoryID(rawValue: "total")
            ceilings[.emergency] = .zero
        }

        // A row only counts as a true root when it declares no parent at all.
        // A row that DOES declare a parent, but that parent isn't a row of its
        // own — deleted, renamed, or a typo made by hand in the Sheet — is an
        // orphan: not a root (it has a parent), and not anyone's child either
        // (that parent doesn't exist), so it would otherwise vanish from the
        // tree entirely while still being a perfectly valid category everywhere
        // else (transactions can still reference it; `categories()` doesn't
        // require the parent to resolve). Same principle as `.unallocated`:
        // a category losing its place in the tree is a bug to surface, not
        // silently drop.
        // A row naming itself as its own parent is a cycle, not a hierarchy. It
        // is neither a root (its parent column isn't empty) nor anyone's child
        // (it can't be its own), so on its own it collapses the entire tree to
        // nothing — which is exactly what an observed sheet did with
        // `id=total parent=total`. It was meant to be the root; treat it as one.
        for (id, parent) in parents where parent == id {
            parents[id] = nil
        }

        let knownIDs = Set(parents.keys)
        var roots = parents.filter { $0.value == nil }.map(\.key)
        let orphanIDs = parents.compactMap { id, parent -> CategoryID? in
            guard let parent, !knownIDs.contains(parent) else { return nil }
            return id
        }

        if !orphanIDs.isEmpty {
            if let existingRoot = roots.first {
                for id in orphanIDs { parents[id] = existingRoot }
            } else {
                // No declared root survived at all, but leaves still point at
                // one — synthesize the id every other write path in this file
                // already uses ("total") rather than let the whole tree go
                // empty.
                let syntheticRoot = CategoryID(rawValue: "total")
                names[syntheticRoot] = names[syntheticRoot] ?? "Total"
                ceilings[syntheticRoot] = ceilings[syntheticRoot] ?? .zero
                parents[syntheticRoot] = nil
                for id in orphanIDs { parents[id] = syntheticRoot }
                roots = [syntheticRoot]
            }
        }

        return roots.map { node(id: $0, names: names, parents: parents, ceilings: ceilings) }
    }

    func setCeiling(_ amount: Money, for categoryID: CategoryID, in interval: DateInterval) async throws {
        var rows = try await ledger.budgetRows()
        // Compare through CategoryID, never against the raw cell: the id in the
        // sheet may be "Food" where ours is "food", and a miss here doesn't
        // fail loudly — it appends a second row for a bucket that already
        // exists.
        if let index = rows.firstIndex(where: { CategoryID(rawValue: $0.first ?? "") == categoryID }) {
            var row = rows[index]
            while row.count < 5 { row.append("") }
            row[3] = String(amount.minorUnits)
            rows[index] = row
        } else {
            // The root is not its own child. Writing `parent = total` on the
            // `total` row itself makes a cycle: it stops being a root (its
            // parent column isn't empty) and it can't be anyone's child either,
            // so the whole tree resolves to nothing and every bucket vanishes
            // from the dashboard. Hard-coding the parent here is what produced
            // exactly that.
            let root = CategoryID(rawValue: "total")
            rows.append(
                SheetsSchema.row(
                    categoryID: categoryID,
                    name: categoryID.rawValue.capitalized,
                    parentID: categoryID == root ? nil : root,
                    ceiling: amount,
                    month: ""
                )
            )
        }
        try await ledger.writeBudgetRows(rows)
    }

    func addCategory(_ category: SpendCategory, under parentID: CategoryID?) async throws {
        var rows = try await ledger.budgetRows()
        guard !rows.contains(where: { CategoryID(rawValue: $0.first ?? "") == category.id }) else { return }
        rows.append(
            SheetsSchema.row(
                categoryID: category.id, name: category.name,
                parentID: parentID, ceiling: .zero, month: ""
            )
        )
        try await ledger.writeBudgetRows(rows)
    }

    /// `visited` is a cycle brake, not bookkeeping. The sheet is hand-editable,
    /// so a → b → a is reachable, and without this the recursion never returns
    /// — a hang or a stack overflow rather than a wrong number. A node already
    /// on the current path is dropped instead of followed.
    private func node(
        id: CategoryID,
        names: [CategoryID: String],
        parents: [CategoryID: CategoryID?],
        ceilings: [CategoryID: Money],
        visited: Set<CategoryID> = []
    ) -> BudgetNode {
        let seen = visited.union([id])
        let children = parents
            .filter { $0.value == id && !seen.contains($0.key) }
            .map(\.key)
            .sorted { (names[$0] ?? "") < (names[$1] ?? "") }
            .map { node(id: $0, names: names, parents: parents, ceilings: ceilings, visited: seen) }

        return BudgetNode(
            id: id,
            name: names[id] ?? id.rawValue,
            ceiling: ceilings[id] ?? .zero,
            children: children
        )
    }
}
