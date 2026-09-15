//
//  LedgerCalcTool.swift
//  FTL — services/Ledger
//
//  All ledger arithmetic. Behind the CalcTool protocol so nothing else — and in
//  particular no model call — can produce a figure the user reads.
//

import Foundation

/// Invariant 2 made concrete: every number the user sees is computed here, in
/// plain Swift, over rows the ledger handed back. Works against any LedgerStore —
/// Sheets in the live app, fixtures in the sample one. The arithmetic never moves
/// to the model.
actor LedgerCalcTool: CalcTool {
    private let budgets: BudgetStore
    private let ledger: LedgerStore
    private let calendar = Calendar.current

    init(budgets: BudgetStore, ledger: LedgerStore) {
        self.budgets = budgets
        self.ledger = ledger
    }

    func monthSummaries(limit: Int) async throws -> [MonthSummary] {
        let rows = try await ledger.all()
        let now = Date.now
        let months: [DateInterval] = (0..<limit).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: date)
        }
        let tree = try await budgets.tree(for: calendar.dateInterval(of: .month, for: now) ?? .init(start: now, duration: 0))
        let ceiling = tree.first?.ceiling ?? .zero

        return months.map { interval in
            let spend = rows.filter { interval.containsLedgerDate($0.date) && $0.countsTowardBudget }
            let isCurrent = interval.containsLedgerDate(now)
            let spentMoney = Money.sum(spend.map(\.amount))
            let daysRemaining = isCurrent
                ? max(0, calendar.dateComponents([.day], from: now, to: interval.end).day ?? 0)
                : 0
            
            let perDayRemaining: Money?
            if isCurrent, daysRemaining > 0 {
                if let customDailyUnits = DailyBudgetManager.amount {
                    if DailyBudgetManager.rollsOver {
                        let daysTotal = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
                        let daysPassed = max(1, daysTotal - daysRemaining)
                        let totalAllowance = customDailyUnits * daysPassed
                        let left = totalAllowance - spentMoney.minorUnits
                        perDayRemaining = Money(minorUnits: left, currency: ceiling.currency)
                    } else {
                        let spentToday = Money.sum(spend.filter { calendar.isDate($0.date, inSameDayAs: now) }.map(\.amount))
                        let left = customDailyUnits - spentToday.minorUnits
                        perDayRemaining = Money(minorUnits: left, currency: ceiling.currency)
                    }
                } else {
                    let left = max(0, (ceiling - spentMoney).minorUnits)
                    perDayRemaining = Money(minorUnits: left / daysRemaining, currency: ceiling.currency)
                }
            } else {
                perDayRemaining = nil
            }

            return MonthSummary(
                interval: interval,
                spent: spentMoney,
                ceiling: ceiling,
                isCurrent: isCurrent,
                daysRemaining: daysRemaining,
                perDayRemaining: perDayRemaining
            )
        }
    }

    func transactions(
        in interval: DateInterval,
        categoryID: CategoryID?,
        limit: Int
    ) async throws -> [LedgerTransaction] {
        try await ledger.all()
            .filter { interval.containsLedgerDate($0.date) }
            .filter { categoryID == nil || $0.categoryID == categoryID }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    func evaluate(_ query: LedgerQuery) async throws -> LedgerAggregate {
        let matching = try await ledger.all().filter { tx in
            guard query.interval.containsLedgerDate(tx.date) else { return false }
            if !query.includeNonSpend && !tx.countsTowardBudget { return false }
            if let ids = query.categoryIDs, let category = tx.categoryID, !ids.contains(category) { return false }
            return true
        }
        return LedgerAggregate(
            total: Money.sum(matching.map(\.amount)),
            count: matching.count,
            groups: [:],
            interval: query.interval
        )
    }

    func budgetPositions(for interval: DateInterval) async throws -> [BudgetPosition] {
        let tree = try await budgets.tree(for: interval)
        // Invariant 5: only spend counts toward a ceiling.
        let spend = try await ledger.all().filter { interval.containsLedgerDate($0.date) && $0.countsTowardBudget }
        return tree.map { position(for: $0, spend: spend) }
    }

    private func position(for node: BudgetNode, spend: [LedgerTransaction]) -> BudgetPosition {
        let children = node.children.map { position(for: $0, spend: spend) }

        let namedIDs = Set(node.children.map(\.id))
        let isRoot = !node.children.isEmpty
        let ownSpend = spend.filter { tx in
            guard let category = tx.categoryID else {
                // Uncategorized spend belongs to the root's total and to nothing
                // below it — that is exactly what "unallocated" means.
                return isRoot
            }
            return category == node.id || namedIDs.contains(category)
        }

        // The implicit child: anything landing on the parent rather than a named
        // bucket. Kept visible instead of folded away — mystery spend that hides
        // is the failure mode the target tree exists to prevent.
        var allChildren = children
        if !node.children.isEmpty {
            let unnamedSpend = spend.filter { $0.categoryID == nil || $0.categoryID == node.id }
            let unallocatedNode = BudgetNode(
                id: .unallocated,
                name: "Unallocated",
                ceiling: node.unallocatedCeiling,
                children: []
            )
            allChildren.append(
                BudgetPosition(
                    node: unallocatedNode,
                    actual: Money.sum(unnamedSpend.map(\.amount)),
                    children: []
                )
            )
        }

        return BudgetPosition(
            node: node,
            actual: Money.sum(ownSpend.map(\.amount)),
            children: allChildren
        )
    }
}

import Foundation

enum DailyBudgetManager {
    static let amountKey = "ftl_daily_budget_amount"
    static let rollsOverKey = "ftl_daily_budget_rolls_over"
    
    static var amount: Int? {
        get {
            guard UserDefaults.standard.object(forKey: amountKey) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: amountKey)
        }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set(newValue, forKey: amountKey)
            } else {
                UserDefaults.standard.removeObject(forKey: amountKey)
            }
        }
    }
    
    static var rollsOver: Bool {
        get { UserDefaults.standard.bool(forKey: rollsOverKey) }
        set { UserDefaults.standard.set(newValue, forKey: rollsOverKey) }
    }
}
