//
//  ApprovalService.swift
//  FTL — model/Contracts · Phase 1
//
//  The human gate, and Invariant 1: this is the ONLY path from the provisional
//  cache into the canonical ledger. No rail, no rule, and above all no model
//  writes to LedgerStore. If a second write path ever appears, the guarantee that
//  makes autonomous model tagging safe is gone.
//
//  Implementation: services/Pipeline/DefaultApprovalService
//

import Foundation

nonisolated protocol ApprovalService: Sendable {
    /// Promote approved entries. Returns what was written so the caller can show
    /// it. Partial success is normal and reported per entry — one bad row must not
    /// strand the rest of the batch.
    func approve(_ ids: [ProvisionalEntry.ID]) async throws -> ApprovalResult

    /// Rejected entries stay in the cache marked `.rejected`, never deleted: the
    /// record of what the model got wrong is how promotion gets decided later.
    func reject(_ ids: [ProvisionalEntry.ID]) async throws

    /// Correct a resolution before approving — recategorize, change kind, split.
    /// Sets provenance to `.manual`, because a corrected row is no longer the
    /// model's verdict and must not be counted as one when measuring accuracy.
    func amend(_ id: ProvisionalEntry.ID, to resolution: ProvisionalEntry.Resolution) async throws

    /// Correct the FIGURE before approving — the parser read the wrong number
    /// out of the email and you are fixing it.
    ///
    /// Separate from `amend` because it changes the transaction rather than the
    /// resolution, and because the two mean different things about different
    /// tools: a retag is evidence about the tagger, a corrected amount is
    /// evidence about the parser that read the email. Both set provenance to
    /// `.manual`; only this one recomputes the fingerprint, which is derived
    /// from the amount and would otherwise leave the row blocking against
    /// candidates for a figure it no longer carries.
    func correctAmount(_ id: ProvisionalEntry.ID, to amount: Money) async throws

    /// Correct the merchant NAME before approving — the parser grabbed the
    /// wrong string, or a legible one nobody would recognise.
    ///
    /// This never touches `merchantRaw` and could not if it wanted to
    /// (Invariant 3, enforced by `let`). It sets the display name the ledger
    /// row will carry; the string the email actually said is preserved beside
    /// it forever, which is what makes the correction auditable rather than a
    /// rewrite of history.
    ///
    /// Passing nil, or the name the parser already produced, clears the
    /// correction rather than recording an empty one.
    func correctMerchant(_ id: ProvisionalEntry.ID, to name: String?) async throws
}

nonisolated struct ApprovalResult: Sendable {
    let written: [LedgerTransaction]
    let failed: [(id: ProvisionalEntry.ID, error: String)]
}

/// How much the user trusts the pipeline to act. v0.6 ships pinned to `.assist`;
/// `.auto` exists in the type so the UI can name the ladder, and must not be
/// selectable until accuracy is re-measured (feasibility: 67% unattended correct).
nonisolated enum TrustLevel: String, Sendable, Hashable, Codable, CaseIterable {
    case off      // rails still capture and dedup; nothing is resolved
    case assist   // default — everything waits for the human gate
    case auto     // NOT AVAILABLE in v0.6

    static var available: [TrustLevel] { [.off, .assist] }
}
