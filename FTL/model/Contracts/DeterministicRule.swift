//
//  DeterministicRule.swift
//  FTL — model/Contracts · Phase 1
//
//  The spine. Dedup, known-merchant lookup, non-spend rules, recurring detection —
//  the wide path that settles the majority with no model call.
//
//  Rules are pure functions of (transaction, context). No I/O, no clock, no
//  randomness: the context carries everything they need, which is what makes them
//  table-testable against the 66 real cases in feasibility-report.md.
//
//  Implementations: services/Pipeline/Rules/*
//

import Foundation

nonisolated struct RuleID: Sendable, Hashable, Codable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

nonisolated protocol DeterministicRule: Sendable {
    var id: RuleID { get }

    /// Runs in the pipeline's declared order; the first non-`.pass` outcome wins.
    /// A rule that cannot decide returns `.pass` — it never guesses, and it never
    /// hands work to the model itself. Routing is the pipeline's job.
    func evaluate(_ transaction: NormalizedTransaction, in context: RuleContext) -> RuleOutcome
}

nonisolated enum RuleOutcome: Sendable {
    /// Not my case — try the next rule.
    case pass
    /// Settled deterministically. Goes straight to the cache, skipping the model.
    case settle(ProvisionalEntry.Resolution)
    /// Definitively not a transaction. Recorded with its reason, never silent.
    case drop(DropReason)
    /// A human should look. The batch continues (Invariant 6).
    case flag(ReviewFlag, ProvisionalEntry.Resolution?)
}

/// Everything a rule may read. Deterministic lookups only — assembled by the
/// pipeline before the rules run, so no rule can reach out mid-evaluation.
nonisolated struct RuleContext: Sendable {
    /// Confirmed dictionary entries. Unconfirmed hints are deliberately excluded:
    /// a hint may inform the model, but it must not settle a row.
    let merchants: [String: Merchant]
    /// Cache and ledger rows sharing a fingerprint bucket — the dedup candidates.
    let fingerprintCandidates: [ProvisionalEntry]
    let recentLedger: [LedgerTransaction]
    /// Descriptor substrings that mark a non-spend movement, per institution.
    let nonSpendMarkers: [String: NonSpendType]
    /// Injected rather than read from `Date()` so rules stay pure.
    let now: Date
}
