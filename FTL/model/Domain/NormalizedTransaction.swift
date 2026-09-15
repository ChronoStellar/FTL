//
//  NormalizedTransaction.swift
//  FTL — model/Domain
//
//  A parsed, fingerprinted candidate. Deterministically produced, not yet judged:
//  nothing here says whether it is a purchase, which bucket it belongs to, or
//  whether it duplicates something already known.
//

import Foundation

nonisolated struct NormalizedTransaction: Sendable, Hashable, Identifiable, Codable {
    let id: UUID
    /// The capture that produced this row. Opaque until the rails land.
    let documentID: UUID
    let source: CaptureSource

    var date: Date
    var amount: Money

    /// Invariant 3: written once by the normalizer, never mutated afterwards.
    /// Every downstream correction goes to `merchant` instead, so a normalization
    /// mistake is always recoverable and the raw string stays a valid join key.
    let merchantRaw: String

    /// Normalized name once a merchant is resolved. Blank until then — a blank
    /// merchant is a normal state, not an error.
    var merchant: MerchantID?

    var lineItems: [LineItem]
    var fingerprint: Fingerprint
}

nonisolated struct LineItem: Sendable, Hashable, Codable {
    let label: String
    let amount: Money
    let quantity: Int?
    /// Set only when a mixed receipt is split across buckets (model job 1, P2).
    var categoryID: CategoryID?
}
