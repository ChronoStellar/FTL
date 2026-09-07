//
//  IncomeSplitViewModel.swift
//  FTL — viewModel · Phase 1
//
//  Set every bucket ceiling at once from a monthly income and a percentage
//  split, instead of one by one. Still Invariant 8: every ceiling that lands
//  in the Sheet is the ratio the user actually landed on after adjusting —
//  never a number the app invented. The only thing the app supplies is an
//  EVEN starting split, which is the one default that isn't itself a
//  budgeting opinion (a housing-heavy or food-heavy preset would be).
//

import Foundation
import Observation

@Observable @MainActor
final class IncomeSplitViewModel {
    private let budgets: BudgetStore
    private let ledger: LedgerStore
    private let interval: DateInterval

    private(set) var phase: LoadPhase = .idle
    var incomeDigits: String = ""
    private(set) var rows: [SplitRow] = []

    /// Percentage points per tap on a row's stepper. The starting split is
    /// snapped to this grid too, so stepping never strands you on a total that
    /// can't reach a round number.
    static let step = 5

    struct SplitRow: Identifiable, Hashable {
        let categoryID: CategoryID
        let name: String
        var percent: Int
        var id: CategoryID { categoryID }
    }

    init(budgets: BudgetStore, ledger: LedgerStore, interval: DateInterval) {
        self.budgets = budgets
        self.ledger = ledger
        self.interval = interval
    }

    // MARK: - Derived

    var income: Money { Money.idr(Int(incomeDigits) ?? 0) }
    var hasIncome: Bool { income.minorUnits > 0 }

    var totalPercent: Int { rows.reduce(0) { $0 + $1.percent } }
    var remainingPercent: Int { 100 - totalPercent }
    var isOverAllocated: Bool { totalPercent > 100 }

    /// Anything up to 100% saves. A leftover isn't an error — it lands in the
    /// implicit `unallocated` bucket the budget tree already models, which is
    /// exactly where un-apportioned money is supposed to show up. Only going
    /// OVER the income is blocked, because that partitions money that isn't
    /// there.
    var canSave: Bool { hasIncome && totalPercent > 0 && !isOverAllocated }

    func amount(for row: SplitRow) -> Money {
        Money(minorUnits: Self.share(of: income.minorUnits, percent: row.percent), currency: income.currency)
    }

    var unallocatedAmount: Money {
        Money(minorUnits: Self.share(of: income.minorUnits, percent: max(0, remainingPercent)), currency: income.currency)
    }

    // MARK: - Actions

    /// Rows come from every place a category can legitimately exist, unioned —
    /// NOT just the budget tree. The tree only shows leaves whose `parent_id`
    /// resolves to an actual root row, so a sheet with a broken or missing
    /// parent link silently offers one or two buckets to split across, and the
    /// split is then forced onto whichever happened to resolve. `categories()`
    /// is looser (it only needs a non-empty parent column), and the ledger
    /// itself carries categories that were never given a budget row at all —
    /// legacy-imported rows especially. All three belong here: this screen is
    /// where a person decides what their money is divided into, so it has to
    /// show everything that already exists.
    func load() async {
        if case .idle = phase { phase = .loading }
        do {
            // The tree read throws: it's the primary source, and if the sheet
            // itself is unreachable the user needs to see THAT, not "no
            // categories yet". The two below are supplementary — they only add
            // rows the tree missed, so a failure there shouldn't sink the
            // screen.
            let root = try await budgets.tree(for: interval).first
            let existingIncome = root?.ceiling.minorUnits ?? 0

            var names: [CategoryID: String] = [:]
            var ceilings: [CategoryID: Int] = [:]
            var order: [CategoryID] = []

            // The total is what gets divided; it can never be one of the
            // shares. A sheet whose root row carries a non-empty parent column
            // comes back from `categories()` looking like an ordinary spend
            // bucket, and letting it in here is not cosmetic: it takes a
            // percentage like any other row, and `save()` then writes that
            // share over the income itself.
            let rootIDs: Set<CategoryID> = [CategoryID(rawValue: "total"), root?.id].compactMap { $0 }.reduce(into: []) { $0.insert($1) }

            func note(_ id: CategoryID, name: String?, ceiling: Int?) {
                guard !rootIDs.contains(id) else { return }
                if !order.contains(id) { order.append(id) }
                if let name, names[id] == nil || names[id]?.isEmpty == true { names[id] = name }
                if let ceiling, ceilings[id] == nil { ceilings[id] = ceiling }
            }

            for leaf in root?.children ?? [] {
                note(leaf.id, name: leaf.name, ceiling: leaf.ceiling.minorUnits)
            }
            for category in (try? await ledger.categories()) ?? [] {
                note(category.id, name: category.name, ceiling: nil)
            }
            for transaction in (try? await ledger.all()) ?? [] where transaction.kind == .spend {
                guard let id = transaction.categoryID else { continue }
                note(id, name: nil, ceiling: nil)
            }

            guard !order.isEmpty else {
                phase = .failed("No categories yet — add one under Budget Ceilings first.")
                return
            }

            incomeDigits = existingIncome > 0 ? String(existingIncome) : ""

            // Revisiting an already-split sheet: derive each row's percent back
            // from its current ceiling rather than resetting to even shares —
            // the Sheet is canonical, so what's already there is the starting
            // point, not a fresh guess. Categories with no ceiling yet start at
            // zero rather than stealing from the ones that have one.
            let named = order.map { ($0, names[$0] ?? $0.rawValue.capitalized) }
            let derived = order.map { id in
                SplitRow(
                    categoryID: id,
                    name: names[id] ?? id.rawValue.capitalized,
                    percent: existingIncome > 0
                        ? Int((Double(ceilings[id] ?? 0) / Double(existingIncome) * 100).rounded())
                        : 0
                )
            }

            // Derived percentages are only worth showing if they're a coherent
            // split of the income. Ceilings that already overrun the total —
            // which is what a clobbered Total row leaves behind — produce
            // something like six rows at 100% summing to 600%, and that's a
            // worse starting point than an even split, not a truer one.
            let derivedTotal = derived.reduce(0) { $0 + $1.percent }
            rows = (existingIncome > 0 && derivedTotal <= 100)
                ? derived
                : Self.evenSplit(over: named)

            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    func adjust(_ row: SplitRow, by delta: Int) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index].percent = max(0, min(100, rows[index].percent + delta))
    }

    /// Writes the Total ceiling (the income) and every row's ceiling (its share
    /// of it) straight to the Sheet — the same `setCeiling` call the manual
    /// ceiling editor uses, just run once per row instead of by hand. A row for
    /// a category that has no budget row yet gets one created, so saving here
    /// also repairs a sheet whose categories only ever existed on transactions.
    func save() async -> Bool {
        guard canSave else { return false }
        phase = .loading
        do {
            try await budgets.setCeiling(income, for: CategoryID(rawValue: "total"), in: interval)
            for row in rows {
                try await budgets.setCeiling(amount(for: row), for: row.categoryID, in: interval)
            }
            phase = .loaded
            return true
        } catch {
            phase = .failed(String(describing: error))
            return false
        }
    }

    // MARK: - Helpers

    private static func share(of minorUnits: Int, percent: Int) -> Int {
        Int((Double(minorUnits) * Double(percent) / 100).rounded())
    }

    /// As even as the `step` grid allows — 100 split into `100 / step` units,
    /// handed out one at a time. Keeping every starting value a multiple of
    /// `step` means a tap moves the total between round numbers instead of
    /// stranding it a point or two short of 100 forever.
    private static func evenSplit(over categories: [(CategoryID, String)]) -> [SplitRow] {
        guard !categories.isEmpty else { return [] }
        let units = 100 / step
        let base = units / categories.count
        var remainder = units - base * categories.count
        return categories.map { id, name in
            let extra = remainder > 0 ? 1 : 0
            if remainder > 0 { remainder -= 1 }
            return SplitRow(categoryID: id, name: name, percent: (base + extra) * step)
        }
    }
}
