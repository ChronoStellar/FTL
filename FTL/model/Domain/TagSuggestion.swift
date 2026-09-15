//
//  TagSuggestion.swift
//  FTL — model/Domain
//
//  What the tagger said, kept beside what you decided.
//
//  This is the second tool's whole difference from the first one. A pattern can
//  be checked without you: "the amount follows the word Total" is either true of
//  the next fifty emails or it isn't, and `PatternVerifier` finds out. A tag
//  cannot. Whether `HOKKY SUPERMARKET` is groceries or shopping is not a fact in
//  the email — it is a decision about your own budget, and no verifier settles
//  it.
//
//  So the only honest source of truth is what you approved last time, and this
//  type is what makes that comparison possible: the suggestion survives on the
//  row even after a retag overwrites `Resolution.categoryID`. Without it the
//  queue records what you chose and forgets what was offered, and "how often was
//  the tagger right" becomes unanswerable — which is the number the third rung
//  of the trust ladder has to be earned against.
//

import Foundation

nonisolated struct TagSuggestion: Sendable, Hashable, Codable {
    /// Always a real bucket, never "not a spend".
    ///
    /// The tagger's question is *which bucket*. Whether a row is spending at all
    /// was already answered — by the parser reading the email, and by the person
    /// at the gate — and a suggestion of "not a spend" would be a claim that
    /// costs nothing to be right about: an untagged row already displays that
    /// way, so approving one unchanged would record an agreement nobody made
    /// and the hit rate would start measuring its own output.
    ///
    /// A merchant you consistently settle as non-spend therefore produces NO
    /// suggestion rather than a free one. See `DefaultPurchaseTagger`.
    let categoryID: CategoryID

    let basis: Basis

    /// Where the suggestion came from, in enough detail to argue with.
    ///
    /// Not a confidence score, deliberately. The feasibility run measured 0.76
    /// confident when right against 0.73 when wrong — 0.03 of separation, which
    /// is no information at all — so nothing here is a number the model made up
    /// about itself. `.memory` carries a count of YOUR decisions instead, which
    /// is checkable.
    nonisolated enum Basis: Sendable, Hashable, Codable {
        /// A merchant you have settled before: `agreed` of `of` past decisions
        /// went to this bucket. The deterministic path, and the wide one.
        case memory(agreed: Int, of: Int)
        /// A merchant with no history. The model was asked precisely because
        /// there was nothing to look up.
        case model

        var isModel: Bool { if case .model = self { return true } else { return false } }
    }
}
