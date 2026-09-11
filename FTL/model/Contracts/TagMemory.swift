//
//  TagMemory.swift
//  FTL — model/Contracts · Stage 4.5
//
//  What you decided, kept — the tagger's only source of truth, and the evidence
//  the third rung of the trust ladder has to be earned against.
//
//  Invariant 10 says accuracy that opens `Auto` is measured "against the user's
//  own approvals, not against a model's confidence in itself". This is where
//  those approvals are counted. A tool claiming 90% certainty has said nothing;
//  a tagger that matched you on nine of its last ten `HOKKY SUPERMARKET` rows
//  has said something checkable, and this is what makes it checkable.
//
//  Two consequences of that wording, both structural rather than stylistic:
//
//  · The scope is **per merchant, per layout** (`TagKey`) — because that is the
//    scope the evidence has. Trusting `HOKKY SUPERMARKET` implies nothing about
//    a shop seen once, and trusting "grab" as one thing implies nothing about
//    which of Grab's several services a charge actually was — a platform's
//    ride, food and grocery arms all share one merchant name and mean three
//    different buckets. `TagScoreboard` reports one global hit rate anyway,
//    for reading, and nothing routes on it.
//  · A **retag is the most valuable event in the system**, not correction noise.
//    It is the only place the app finds out it was wrong, so it is recorded with
//    exactly as much care as an agreement.
//
//  Implementation: services/Persistence/SwiftDataTagMemory
//

import Foundation

/// WHAT accrues a decision: a merchant, AND which layout of it read the row.
///
/// A merchant name is not always one kind of purchase. Grab's ride, food and
/// grocery services all say "Grab" on a bank statement, and a `MerchantID`
/// alone folds all three into one key — which is exactly why that key could
/// never settle: 22 decisions split three ways looks identical to a merchant
/// nobody can predict, and `worthAsking` correctly gave up on it rather than
/// keep guessing. Keying on the LAYOUT too — which template or pattern
/// actually read the email, `RuleID.rawValue` — separates `grab.com/food`
/// from `grab.com/ride` before they ever get folded together, so each can
/// settle on its own.
///
/// `layout` is nil for a manual entry (nothing read it) or a merchant no
/// active parser or pattern claimed. Nil rows still accrue together as one
/// key — there is no signal to split them by, which is the honest answer
/// rather than a guess: a bank's generic notification for a Grab charge
/// carries no more information about what was bought than the merchant name
/// itself, and no key scheme can recover what was never captured.
nonisolated struct TagKey: Sendable, Hashable, Codable {
    let merchant: MerchantID
    let layout: String?

    /// A flat, queryable encoding for the persistence layer — SwiftData
    /// predicates filter and group on one column, not a compound value. Not
    /// shown anywhere a person reads; `merchantRaw` is what they see.
    ///
    /// The delimiter is a control character rather than something like "/",
    /// which both a merchant name and a `RuleID` could plausibly contain —
    /// see `ExtractionPattern.id`, which itself uses "/" as a separator.
    var compositeKey: String { merchant.rawValue + "\u{1F}" + (layout ?? "") }
}

/// One settled row: what was offered, what you chose.
nonisolated struct TagDecision: Sendable, Hashable, Codable, Identifiable {
    /// The provisional entry this settled, so a decision is never double-counted
    /// if a promotion is retried.
    let id: ProvisionalEntry.ID
    let key: TagKey
    /// Kept alongside the key so a scoreboard can show a name a person
    /// recognises rather than the flattened form (Invariant 3, in spirit).
    let merchantRaw: String
    /// Nil when nothing suggested anything — a row from before the tagger, or
    /// one it had nothing to say about. Distinct from a suggestion of nil,
    /// which means "not a spend" and IS an answer.
    let suggested: TagSuggestion?
    /// Nil means the row was settled as non-spend.
    let chosen: CategoryID?
    let chosenKind: TransactionKind
    let decidedAt: Date

    /// Nil when there was nothing to be right or wrong about. Counting an
    /// un-suggested row as a miss would make the hit rate a measure of how much
    /// of the queue the tagger reached rather than how often it was right.
    var wasCorrect: Bool? {
        guard let suggested else { return nil }
        return suggested.categoryID == chosen
    }
}

/// Everything decided about one merchant LAYOUT — see `TagKey`.
nonisolated struct MerchantTagHistory: Sendable, Hashable {
    let key: TagKey
    /// The name last seen for it, for display.
    let merchantRaw: String
    /// Bucket → how many times you chose it.
    let choices: [CategoryID: Int]
    /// Times you settled it as non-spend. Kept out of `choices` because "no
    /// bucket" is an answer and not a missing key.
    let nonSpendCount: Int
    /// Decisions where something was suggested, and of those, how many matched.
    let suggested: Int
    let agreed: Int

    var total: Int { choices.values.reduce(0, +) + nonSpendCount }

    /// The bucket you pick for this merchant when you are consistent about it,
    /// or nil when you are not.
    ///
    /// Two bars, and both matter:
    ///
    /// · `minimumDecisions` — one past decision is an anecdote. Two is the
    ///   floor at which "you have settled this before" is even a sentence.
    /// · `dominance` — a merchant you split evenly between two buckets is a
    ///   merchant you have NOT settled, and suggesting the marginal winner
    ///   would be the app inventing a preference you don't have (Invariant 8).
    ///
    /// Non-spend competes on the same terms: if you have marked this merchant
    /// a transfer three times out of four, the honest suggestion is "not a
    /// spend", not the one bucket it went to once.
    /// One past decision is an anecdote. Two is the floor at which "you have
    /// settled this before" is even a sentence.
    static let minimumDecisions = 2
    /// A merchant you split evenly between two buckets is a merchant you have
    /// NOT settled.
    static let dominance = 0.6

    /// Whether there is enough history here to have an opinion at all —
    /// separate from whether that opinion is settled.
    ///
    /// The distinction is what stops the most-used merchant costing the most
    /// model calls. Measured on the real corpus: `MerchantID(normalizing:)`
    /// folds 22 spellings of `Grab* A-…` into one key, which is what makes 72%
    /// of tagging a lookup — and also puts rides and food under one merchant.
    /// Tag those differently and `settled()` correctly returns nil, and the
    /// caller used to read that as "nothing known, ask the model", so a
    /// merchant with 22 decisions on it got a model call every single sync,
    /// forever.
    ///
    /// A merchant you have tagged 22 times inconsistently is not one a model
    /// that has never seen your budget can help with. Asking is worse than
    /// useless: it spends the call budget on the case where your own history is
    /// the most informative thing in the system and simply does not point one
    /// way.
    var hasOpinion: Bool { total >= Self.minimumDecisions }

    func settled(
        minimumDecisions: Int = MerchantTagHistory.minimumDecisions,
        dominance: Double = MerchantTagHistory.dominance
    ) -> (categoryID: CategoryID?, agreed: Int, of: Int)? {
        let all = total
        guard all >= minimumDecisions else { return nil }

        var leader: (categoryID: CategoryID?, count: Int) = (nil, nonSpendCount)
        for (category, count) in choices where count > leader.count {
            leader = (category, count)
        }
        guard leader.count > 0, Double(leader.count) / Double(all) >= dominance else { return nil }
        return (leader.categoryID, leader.count, all)
    }
}

/// The shadow-mode measurement. Roadmap #14 is explicit that auto-commit is not
/// built until there is a month of this, and that the threshold is picked from
/// what it says rather than chosen first and justified later.
nonisolated struct TagScoreboard: Sendable {
    let decisions: Int
    /// Decisions where a suggestion existed to be judged.
    let suggested: Int
    let agreed: Int
    let byMerchant: [MerchantTagHistory]

    /// Read, never routed on. Auto is scoped per merchant precisely because one
    /// number over every merchant hides the only distinction that matters.
    var hitRate: Double { suggested == 0 ? 0 : Double(agreed) / Double(suggested) }
}

nonisolated protocol TagMemory: Sendable {
    /// Idempotent on `TagDecision.id` — a retried promotion must not count as a
    /// second agreement.
    func record(_ decisions: [TagDecision]) async throws

    func history(for keys: [TagKey]) async throws -> [TagKey: MerchantTagHistory]

    func scoreboard() async throws -> TagScoreboard
}
