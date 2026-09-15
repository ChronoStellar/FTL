//
//  ProvisionalEntry.swift
//  FTL — model/Domain
//
//  A row in the on-device cache. Invariant 7: nothing here is a fact. This is the
//  layer where false positives are recoverable, which is the only reason the model
//  is allowed to write autonomously at all.
//
//  Both paths land here — a rule-settled row and a model-tagged row are the same
//  type, distinguished by `provenance`. That distinction must survive to the UI.
//

import Foundation

nonisolated struct ProvisionalEntry: Sendable, Hashable, Identifiable, Codable {
    let id: UUID
    var transaction: NormalizedTransaction
    var resolution: Resolution
    var provenance: Provenance
    var flags: [ReviewFlag]
    var status: Status
    let createdAt: Date

    /// Which parser produced this row. Written once at capture, never mutated.
    ///
    /// `provenance` cannot answer this, and the difference is load-bearing:
    /// `amend` sets provenance to `.manual` the moment a person retags, so the
    /// row forgets which parser read the email exactly when it becomes evidence
    /// about that parser. Splitting the two questions — *who extracted this*
    /// against *who decided the resolution* — is what lets the approval queue
    /// be an oracle for the pattern that produced the row (`PatternMemory`).
    ///
    /// Optional so every row already in the on-disk cache decodes unchanged.
    var readBy: RuleID?

    /// What that parser concluded about direction, kept for the same reason
    /// `Resolution.suggestedTag` is kept: so an agreement can be told apart
    /// from a correction. Without it, approving a row a person had already
    /// flipped from spend to non-spend is indistinguishable from approving one
    /// the parser got right.
    var readAs: TransactionKind?

    /// What the parser read as the AMOUNT, kept for exactly the reason `readAs`
    /// above is kept: so approving a row somebody had already corrected is
    /// distinguishable from approving one the parser got right.
    ///
    /// Nil means nobody has touched the figure — the common case, and why this
    /// is populated on the first correction rather than at capture. It is not a
    /// "was corrected" flag: correcting a row back to what it said originally
    /// leaves this set and equal to the current amount, which reads as
    /// untouched, because it is.
    ///
    /// Optional so every row already in the on-disk cache decodes unchanged.
    var readAmount: Money?

    var needsAttention: Bool { !flags.isEmpty }

    /// What the pipeline concluded about this transaction.
    nonisolated struct Resolution: Sendable, Hashable, Codable {
        var kind: TransactionKind
        var nonSpendType: NonSpendType?
        var categoryID: CategoryID?
        var merchantID: MerchantID?

        /// The display name a person typed, when the parser pulled the wrong
        /// string out of the email. Nil — the overwhelmingly common case —
        /// means use what was parsed.
        ///
        /// It lives on the RESOLUTION and not on the transaction, because
        /// Invariant 3 leaves nowhere else for it to go: `merchantRaw` is `let`
        /// and never mutated, and `merchantID` beside it is a normalization key
        /// computed from the raw, not a name anybody reads. A correction is a
        /// conclusion about the row, which is what this type is for.
        ///
        /// So the raw string survives a correction exactly as it survives
        /// everything else, and the reconciliation join key still points at
        /// what the email actually said.
        var merchantName: String?
        /// Populated only for mixed receipts. Empty means "whole into one bucket",
        /// which is the simple-first default.
        var splits: [Split]
        /// Other entries this one folds in, making a merge reversible.
        var mergedFrom: [ProvisionalEntry.ID]

        /// What the tagger proposed, kept even after a retag has overwritten
        /// `categoryID`. Nil means nothing proposed anything — the status quo
        /// for every row before the second tool existed, and still the answer
        /// for a row the tagger had nothing to say about.
        ///
        /// Deliberately NOT folded into `provenance`. That field says how the
        /// row was EXTRACTED — which parser read the email — and a row read by
        /// a deterministic rule and tagged by the model has two different
        /// answers to two different questions. Collapsing them would make a
        /// suggested tag look like a model-extracted amount, which is the one
        /// distinction Invariant 1 rests on.
        ///
        /// Optional, so every row already in the on-disk cache decodes
        /// unchanged.
        var suggestedTag: TagSuggestion?
    }

    /// How this row got its resolution. A rule and the model are never confused
    /// for one another, in storage or on screen.
    nonisolated enum Provenance: Sendable, Hashable, Codable {
        case rule(RuleID)
        case model(confidence: Double)
        case manual

        var isModel: Bool { if case .model = self { return true } else { return false } }
    }

    nonisolated enum Status: String, Sendable, Hashable, Codable {
        case pending    // waiting on the human gate
        case approved   // user said yes; not yet written
        case rejected   // user said no; kept for audit, never promoted
        /// The pipeline dropped it without asking — today only for a possible
        /// duplicate. Kept and never promoted, exactly like `.rejected`, but a
        /// SEPARATE case on purpose: `.rejected` means a person looked and said
        /// no, and folding a machine decision into that would corrupt the one
        /// record this app has of what a human actually thought. It is also why
        /// an auto-drop records no `PatternObservation` — the queue's value as
        /// an oracle is that it is human evidence.
        case autoDropped
        case promoted   // written to the canonical ledger
    }
}

nonisolated struct Split: Sendable, Hashable, Codable {
    let categoryID: CategoryID
    let amount: Money
}
