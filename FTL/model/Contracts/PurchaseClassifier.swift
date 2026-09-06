//
//  PurchaseClassifier.swift
//  FTL — model/Contracts · Phase 2 · ★ MODEL JOB 1 of 2
//
//  The only place the model acts autonomously, and it is allowed to because its
//  output lands in the provisional cache where a false positive is recoverable.
//
//  Two questions, one call: is this a purchase at all (receipt vs marketing), and
//  if so how is it tagged (category, merchant, spend/non-spend, mixed-receipt split).
//
//  Hard requirements on any implementation:
//    · Gated by LanguageGate before the call — Invariant 9.
//    · Guided generation, schema-locked. Free-form output is not accepted.
//    · Never returns a question. Uncertainty is a flag (Invariant 6); the
//      feasibility run confirmed 0 questions asked, and it must stay 0.
//    · Never computes. It selects; code computes (Invariant 2).
//    · Never writes anywhere. It returns a verdict; the pipeline stores it.
//    · Hard call budget. One runaway loop hit 30 tool calls — cap and abort.
//
//  Implementation: services/Agent/FoundationModelClassifier
//

import Foundation

nonisolated protocol PurchaseClassifier: Sendable {
    func classify(
        _ transaction: NormalizedTransaction,
        in context: ClassificationContext
    ) async throws -> ClassificationVerdict
}

nonisolated struct ClassificationVerdict: Sendable, Hashable {
    let isPurchase: Bool
    /// Nil when `isPurchase` is false.
    let resolution: ProvisionalEntry.Resolution?

    /// Recorded for measurement, NOT for routing.
    ///
    /// Feasibility: 0.76 confident when right, 0.73 when wrong — 0.03 separation.
    /// This number does not carry the information a threshold would need. Do not
    /// gate a write, an auto-approve, or a flag on it. Route on rules and flags.
    let confidence: Double

    let flags: [ReviewFlag]
    /// Short factual justification for the review UI. Never a question.
    let rationale: String
}

/// What the classifier is given. Assembled deterministically — the model does not
/// fetch. Unconfirmed dictionary hints are allowed here (unlike RuleContext),
/// because a hint informing a verdict that a human will approve is safe.
nonisolated struct ClassificationContext: Sendable {
    let merchantHints: [Merchant]
    let availableCategories: [SpendCategory]
    let recentSimilar: [LedgerTransaction]
    let nonSpendMarkers: [String: NonSpendType]
}

nonisolated enum ClassifierError: Error, Sendable {
    /// LanguageGate said no. Expected, common, and not a failure of the run.
    case gated(GateDecision.Reason)
    case modelRefused(String)
    case schemaViolation(String)
    case callBudgetExceeded(limit: Int)
}
