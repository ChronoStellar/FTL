//
//  Category.swift
//  FTL — model/Domain
//
//  Leaf spending buckets. Flat first (v0.5 §10 "simple-first"); the tree lives in
//  BudgetNode, so a category is just a name and an identity.
//

import Foundation

nonisolated struct CategoryID: Sendable, Hashable, Codable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    /// The implicit child every parent ceiling carries, so mystery spend stays
    /// visible instead of silently vanishing from the tree.
    static let unallocated = CategoryID(rawValue: "unallocated")
}

/// Named `SpendCategory` rather than `Category` — the bare name collides with an
/// SDK typealias and silently resolves to it in some contexts.
nonisolated struct SpendCategory: Sendable, Hashable, Identifiable, Codable {
    let id: CategoryID
    var name: String
    /// Nil for top-level buckets.
    var parentID: CategoryID?
}

/// Spend or not. Invariant 5: non-spend rows are labelled and kept, never deleted,
/// and never counted toward a ceiling. Without this every budget is fiction.
nonisolated enum TransactionKind: String, Sendable, Hashable, Codable {
    case spend
    case nonSpend
}

nonisolated enum NonSpendType: String, Sendable, Hashable, Codable, CaseIterable {
    case transfer
    case topup
    case creditCardPayment
    case cashback
    case refund
}
