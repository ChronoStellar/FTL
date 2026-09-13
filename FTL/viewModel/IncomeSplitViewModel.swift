//
//  IncomeSplitViewModel.swift
//  FTL — viewModel · Phase 1
//
//  Set every bucket ceiling at once from a monthly income and a percentage
//  split, instead of one by one. Still Invariant 8: every ceiling that lands
//  in the Sheet is the ratio the user actually landed on after adjusting —
//  never a number the app invented.
//
//  WHERE THE STARTING SPLIT COMES FROM, in order:
//
//   1. The ceilings already in the Sheet, if they form a coherent split. The
//      Sheet is canonical; what is already there is the starting point, not a
//      fresh guess.
//   2. Otherwise, YOUR OWN SPEND over the last `historyMonths` months, one
//      share per bucket in proportion to what actually went through it.
//   3. Otherwise — a mailbox with no history yet — an even split.
//
//  Rung 2 replaced an even-split-always default, and the distinction it turns
//  on is the whole of Invariant 8. A shipped "food-heavy" preset would be the
//  app asserting how a person OUGHT to divide their money. Reading the ledger
//  back is the opposite: it reports what they already did and offers it as the
//  starting point. Food comes out biggest when food IS biggest, and on a
//  mailbox where it isn't, it doesn't. Nothing here is a recommendation, and
//  every number is still moved by the user before it is saved.
//
//  The split always totals exactly 100%, and every point a bucket gains or
//  gives up moves to or from UNALLOCATED — never to or from another bucket. See
//  `setPercent`.
//
//  The first version spread the difference across the other buckets in
//  proportion to their size, which kept the total honest and had a worse
//  property: touching one row silently rewrote every other row on the screen.
//  A person raising Food by ten points did not ask for Transport, Shopping and
//  Subscriptions to move, and watching four numbers change under one thumb
//  makes the control feel like it is guessing. Drawing from the buffer instead
//  means a drag changes exactly the two figures it should, and the cost is a
//  real one stated plainly: a bucket can only grow into what is left.
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

    /// Minor units spent per bucket over the lookback window. Kept after
    /// `load` so "Match my spending" can re-derive the split without another
    /// read of the whole ledger.
    private(set) var spendWeights: [CategoryID: Int] = [:]

    /// How far back "what you actually spend" reaches. A split derived from
    /// three years ago is not descriptive of now.
    static let historyMonths = 6

    var hasSpendHistory: Bool { spendWeights.values.contains { $0 > 0 } }

    struct SplitRow: Identifiable, Hashable {
        let categoryID: CategoryID
        let name: String
        var percent: Int
        var id: CategoryID { categoryID }

        /// The implicit child, made explicit here. See `load`.
        var isUnallocated: Bool { categoryID == .unallocated }
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

    /// Over-allocation is no longer reachable — `setPercent` keeps the total
    /// pinned at 100 — so all that is left to require is an income and at
    /// least one named bucket carrying some of it.
    var canSave: Bool { hasIncome && namedPercent > 0 }

    /// What a drag has left to spend. Zero means every named bucket is at its
    /// ceiling until one of them is lowered.
    var unallocatedPercent: Int { rows.first { $0.isUnallocated }?.percent ?? 0 }

    /// Everything except the unallocated row. That row is a deliberate buffer,
    /// not a ceiling, and saving a split of nothing but buffer would write
    /// zero to every bucket.
    var namedPercent: Int { rows.filter { !$0.isUnallocated }.reduce(0) { $0 + $1.percent } }

    func amount(for row: SplitRow) -> Money {
        Money(minorUnits: Self.share(of: income.minorUnits, percent: row.percent), currency: income.currency)
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
            // Two jobs in one pass. Every spend category becomes a row no
            // matter how old, so nothing a person has ever spent on quietly
            // goes missing from the screen where they divide their money up —
            // but only spend inside the lookback window earns WEIGHT, because
            // the split is meant to describe how they spend now.
            let historyStart = Calendar.current.date(
                byAdding: .month, value: -Self.historyMonths, to: interval.end
            ) ?? .distantPast

            var weights: [CategoryID: Int] = [:]
            for transaction in (try? await ledger.all()) ?? [] where transaction.kind == .spend {
                guard let id = transaction.categoryID else { continue }
                note(id, name: nil, ceiling: nil)
                guard transaction.date >= historyStart else { continue }
                weights[id, default: 0] += transaction.amount.minorUnits
            }
            spendWeights = weights

            guard !order.isEmpty else {
                phase = .failed("No categories yet — add one under Budget Ceilings first.")
                return
            }

            incomeDigits = existingIncome > 0 ? String(existingIncome) : ""

            // Unallocated is pulled out of the ordinary rows and appended last,
            // always present. It used to be implied — whatever the named rows
            // left short of 100% — but with the total pinned there is no
            // "short of" any more, so the buffer has to be a row you can drag
            // or it stops existing. It still writes no ceiling: the budget tree
            // computes it as parent minus children, so `save` skips it.
            let namedOrder = order.filter { $0 != .unallocated }
            func name(_ id: CategoryID) -> String { names[id] ?? id.rawValue.capitalized }

            // 1. What the Sheet already says, if it's coherent. Ceilings that
            //    overrun the total — what a clobbered Total row leaves behind —
            //    produce six rows at 100% summing to 600%, which is a worse
            //    starting point than either fallback, not a truer one.
            let derived = namedOrder.map { id in
                existingIncome > 0
                    ? Int((Double(ceilings[id] ?? 0) / Double(existingIncome) * 100).rounded())
                    : 0
            }
            let derivedTotal = derived.reduce(0, +)

            let percents: [Int]
            let unallocatedPercent: Int

            if existingIncome > 0, derivedTotal > 0, derivedTotal <= 100 {
                percents = derived
                unallocatedPercent = 100 - derivedTotal
            } else if hasSpendHistory {
                // 2. Their own spend. Uncategorized spend weights the buffer
                //    rather than being dropped — it is money that went out
                //    without landing in a bucket, which is what unallocated
                //    means.
                let ids = namedOrder + [CategoryID.unallocated]
                let shares = Self.apportion(100, weights: ids.map { Double(weights[$0] ?? 0) })
                percents = Array(shares.dropLast())
                unallocatedPercent = shares[shares.count - 1]
            } else {
                // 3. Nothing to go on. Even is the only split that isn't an
                //    opinion.
                percents = Self.apportion(100, weights: namedOrder.map { _ in 1 })
                unallocatedPercent = 0
            }

            rows = zip(namedOrder, percents).map {
                SplitRow(categoryID: $0, name: name($0), percent: $1)
            } + [
                SplitRow(categoryID: .unallocated, name: "Unallocated", percent: unallocatedPercent)
            ]

            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Move one named row. Every point it gains comes out of Unallocated, and
    /// every point it gives up goes back there. No other bucket moves.
    ///
    /// That makes the buffer the only thing a drag can spend, so a bucket's
    /// ceiling is `its own share + whatever is left` and nothing beyond — a drag
    /// past that just stops. The stop is the honest answer: the money is
    /// already committed somewhere, and the way to free it is to lower the
    /// bucket holding it, not to have the app pick a victim.
    ///
    /// Unallocated itself is not passed here — `isUnallocated` rows have no
    /// thumb. It is `100 − Σ named` by definition, and a pool you can also drag
    /// directly is a pool with two contradictory definitions.
    func setPercent(_ row: SplitRow, to newValue: Int) {
        guard !row.isUnallocated,
              let index = rows.firstIndex(where: { $0.id == row.id }),
              let buffer = rows.firstIndex(where: { $0.isUnallocated })
        else { return }

        let current = rows[index].percent
        // The ceiling on this row is what it already holds plus what is spare.
        let clamped = max(0, min(current + rows[buffer].percent, newValue))
        guard clamped != current else { return }

        rows[index].percent = clamped
        rows[buffer].percent -= (clamped - current)
    }

    /// Throw the current split away and re-derive it from the ledger. The same
    /// rung 2 `load` uses, reachable on demand so a split that has been dragged
    /// around can be put back to what the spending actually looks like.
    /// Sets every row at once rather than one at a time, so it is not bound by
    /// the single-row rule above — this is a whole new split, not a drag.
    func matchSpending() {
        guard hasSpendHistory else { return }
        let shares = Self.apportion(100, weights: rows.map { Double(spendWeights[$0.categoryID] ?? 0) })
        for (index, share) in shares.enumerated() { rows[index].percent = share }
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
            // Unallocated is never written. The budget tree derives it as the
            // parent ceiling minus the named children, so giving it a row of
            // its own would count the buffer twice — once as its own ceiling
            // and once as the gap it already is.
            for row in rows where !row.isUnallocated {
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

    /// Split `total` across `weights` in whole percentage points that sum to
    /// EXACTLY `total`.
    ///
    /// Largest remainder, because rounding each share on its own does not add
    /// up: five buckets at 20.4% each round to 20 and lose 2 points, and a
    /// split that silently fails to total 100 is the bug this whole screen is
    /// now built to make impossible. Floor everything, then hand the leftover
    /// points to whichever shares were cut hardest.
    static func apportion(_ total: Int, weights: [Double]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        guard total > 0 else { return Array(repeating: 0, count: weights.count) }

        // All-zero weights carry no ratio to respect, so fall back to even.
        let usable = weights.contains(where: { $0 > 0 }) ? weights : weights.map { _ in 1 }
        let sum = usable.reduce(0, +)

        let raw = usable.map { Double(total) * $0 / sum }
        var out = raw.map { Int($0.rounded(.down)) }
        var left = total - out.reduce(0, +)

        for index in raw.indices.sorted(by: { raw[$0] - Double(out[$0]) > raw[$1] - Double(out[$1]) }) {
            guard left > 0 else { break }
            out[index] += 1
            left -= 1
        }
        return out
    }
}
