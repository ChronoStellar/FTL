//
//  ResultReasoner.swift
//  FTL — model/Contracts · Phase 2 · ★ MODEL JOB 2 of 2
//
//  The query box. The model compiles a plain-language question into a structured
//  LedgerQuery, hands it to CalcTool, and narrates what comes back.
//
//  It never touches the numbers. Invariant 2 is the entire shape of this contract:
//  the model picks filters, code computes, the model reads the result aloud.
//
//  Invariant 8 binds hardest here, because this is the surface where a model is
//  most tempted to editorialize:
//    allowed   — "Delivery 0.6M of 0.5M." · "Dining up 3× vs last month."
//    forbidden — "You're overspending." · "Consider cutting back."
//  The feasibility run recorded 0 pieces of advice given. That is the bar.
//
//  On a question it cannot compile, it says so. It does not guess a filter.
//
//  Implementation: services/Agent/FoundationModelReasoner
//

import Foundation

nonisolated protocol ResultReasoner: Sendable {
    /// Compile only — exposed separately so the query can be shown to the user and
    /// unit-tested without a narration step.
    func compile(_ question: String, context: QueryContext) async throws -> LedgerQuery

    /// Narrate an aggregate the calc tool produced. Receives numbers already
    /// computed; it may not derive new ones.
    func narrate(_ aggregate: LedgerAggregate, answering question: String) async throws -> String
}

nonisolated struct QueryContext: Sendable {
    let availableCategories: [SpendCategory]
    let knownMerchants: [Merchant]
    /// Bounds the model can express relative dates against ("last month").
    let ledgerInterval: DateInterval
    let now: Date
}

nonisolated enum ReasonerError: Error, Sendable {
    case gated(GateDecision.Reason)
    /// The honest failure. Better than a plausible wrong filter, which produces a
    /// confident wrong number the user has no way to notice.
    case couldNotCompile(question: String)
    case callBudgetExceeded(limit: Int)
}
