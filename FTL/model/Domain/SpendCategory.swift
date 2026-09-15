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

    /// Trimmed and lowercased at construction, always.
    ///
    /// The same bucket arrives spelled differently depending on the path it
    /// came in on: the budgets tab is hand-editable ("Food"), the legacy month
    /// import lowercases whatever the old sheet said ("food"), and the add-
    /// category form slugs from typed text. Two spellings meant two buckets —
    /// spend attributed to one, a ceiling sitting on the other, and a category
    /// that looks present everywhere but never matches anything. Normalizing in
    /// the initializer catches every path at once (sheet reads, legacy import,
    /// JSON decode, anything typed) rather than asking each call site to
    /// remember.
    ///
    /// Display names are NOT normalized — `SpendCategory.name` is what a person
    /// reads and stays exactly as they wrote it.
    init(rawValue: String) {
        self.rawValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

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
    /// Money ARRIVING that is not a refund — a salary, a repayment, a top-up
    /// from someone else. Its own case rather than folded into `.transfer`,
    /// which was where blu's "Incoming Transaction to Your blu" used to land.
    ///
    /// A transfer is money you moved between your own accounts; an inflow is
    /// money that came from somewhere else. Both are excluded from every
    /// ceiling (Invariant 5), so this changes no arithmetic today — but it is
    /// the difference between "I moved this" and "I received this", and a
    /// learned pattern cannot describe a sender's inbound receipts at all if
    /// the only word available for them is one that means something else.
    case incoming
}
