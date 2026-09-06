//
//  CalcTool.swift
//  FTL — model/Contracts · Phase 1
//
//  Invariant 2, made structural: every number the user sees comes from here.
//  The model never sums a column — in Phase 2 the ResultReasoner picks filters and
//  calls this, then narrates the result it gets back.
//
//  The feasibility run recorded 1 invented number. Keeping arithmetic behind a
//  protocol the model cannot bypass is what makes that class of error impossible
//  rather than merely unlikely.
//
//  Implementation: services/Ledger/SheetsCalcTool
//

import Foundation

nonisolated protocol CalcTool: Sendable {
    /// Run a filter and aggregate it. Deterministic: same query, same ledger, same
    /// answer, every time.
    func evaluate(_ query: LedgerQuery) async throws -> LedgerAggregate

    /// The dashboard's whole job — actual against ceiling, per node, as flat facts.
    func budgetPositions(for interval: DateInterval) async throws -> [BudgetPosition]

    /// Totals per month, newest last. Feeds the month picker and the home hero.
    func monthSummaries(limit: Int) async throws -> [MonthSummary]

    /// Ledger rows for a period, newest first. `categoryID` nil means every bucket.
    func transactions(
        in interval: DateInterval,
        categoryID: CategoryID?,
        limit: Int
    ) async throws -> [LedgerTransaction]
}

/// A structured filter, never free text. Phase 2's model job compiles a question
/// into one of these, and fails with `.couldNotCompile` rather than guessing.
nonisolated struct LedgerQuery: Sendable, Hashable, Codable {
    var interval: DateInterval
    var categoryIDs: [CategoryID]?
    var merchantIDs: [MerchantID]?
    var minAmount: Money?
    var maxAmount: Money?
    /// Defaults to spend-only. Invariant 5: non-spend never lands in a total
    /// unless something explicitly asks for it.
    var includeNonSpend: Bool = false
    var groupBy: GroupBy?

    nonisolated enum GroupBy: String, Sendable, Hashable, Codable {
        case category
        case merchant
        case month
        case source
    }
}

nonisolated struct LedgerAggregate: Sendable, Hashable {
    let total: Money
    let count: Int
    /// Populated when `groupBy` is set; key is the group's display label.
    let groups: [String: Money]
    let interval: DateInterval
}
