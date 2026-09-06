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

    var needsAttention: Bool { !flags.isEmpty }

    /// What the pipeline concluded about this transaction.
    nonisolated struct Resolution: Sendable, Hashable, Codable {
        var kind: TransactionKind
        var nonSpendType: NonSpendType?
        var categoryID: CategoryID?
        var merchantID: MerchantID?
        /// Populated only for mixed receipts. Empty means "whole into one bucket",
        /// which is the simple-first default.
        var splits: [Split]
        /// Other entries this one folds in, making a merge reversible.
        var mergedFrom: [ProvisionalEntry.ID]
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
        case promoted   // written to the canonical ledger
    }
}

nonisolated struct Split: Sendable, Hashable, Codable {
    let categoryID: CategoryID
    let amount: Money
}
