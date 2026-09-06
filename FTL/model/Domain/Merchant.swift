//
//  Merchant.swift
//  FTL — model/Domain
//
//  The merchant dictionary: a fuzzy-matched lookup table populated by use, not a
//  model call. Every resolved merchant makes the next one cheaper, which is what
//  shrinks the model's share over time.
//

import Foundation

nonisolated struct MerchantID: Sendable, Hashable, Codable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct Merchant: Sendable, Hashable, Identifiable, Codable {
    let id: MerchantID
    var canonicalName: String
    /// Default bucket for this merchant. A dictionary hit categorizes without the
    /// model — this field is the whole reason the deterministic path is wide.
    var defaultCategoryID: CategoryID?
    /// Raw descriptors seen for this merchant, across rails. Grows by use.
    var knownRawForms: [String]
    /// True once a human has confirmed it. Unconfirmed entries are hints, and a
    /// hint must never settle a row on its own.
    var isConfirmed: Bool
}
