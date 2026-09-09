//
//  FoundationModelTagger.swift
//  FTL — services/Agent · Stage 4.5 · ★ the model call in the second tool
//
//  One question, for one merchant you have never settled: which of these buckets.
//
//  Why this is a smaller and safer call than it looks:
//
//  · It is asked ONLY for a merchant with no history. Everything you have
//    already decided is answered by a lookup, so this shrinks as the ledger
//    fills — see `DefaultPurchaseTagger`.
//  · It picks from a CLOSED list that came out of your own sheet. A name that
//    isn't on the list is a refusal, not free text: the row simply arrives
//    untagged, which is what every row looked like before this existed.
//  · It never reads the email. The parser already read it; this sees a merchant,
//    an amount and a date — the same three things a person glancing at the queue
//    sees.
//  · Invariant 2: it selects, it does not compute. The amount is passed in
//    already formatted and comes back unused.
//
//  Gated as `.classification`, the strict setting, and that is the deliberate
//  opposite of `FoundationModelSynthesizer`'s choice. Synthesis is permissive
//  because its answer is scored against real emails before it can matter, so
//  refusing it up front prevents finding out rather than preventing a mistake.
//  A tag has no such check — the only thing downstream of it is a person — so
//  the strict gate is the right one. A gated row arrives untagged and unflagged:
//  "no suggestion" is the status quo, and flagging every Indonesian receipt for
//  a feature that is pure upside would be flag inflation on a queue that depends
//  on its flags meaning something.
//

import Foundation
import FoundationModels

/// What the model is allowed to say. One name from a list, and its reasoning —
/// no amount, no merchant, no confidence score. There is deliberately nothing
/// here for it to be wrong about except the one choice.
@Generable
struct ProposedTag: Sendable {
    @Guide(description: "One short sentence: what kind of business this merchant is, judging by its name, and which listed bucket that makes it.")
    var thinking: String

    @Guide(description: "The name of exactly ONE bucket, copied character for character from the list you were given. Do not invent a bucket, do not translate one, and do not return a bucket that is not on the list.")
    var bucket: String
}

nonisolated struct FoundationModelTagger: TagProposer {
    private let languageGate: LanguageGate
    /// Low: this is a choice from a list, not a creative task.
    private let options = GenerationOptions(temperature: 0.2)

    init(languageGate: LanguageGate = DefaultLanguageGate()) {
        self.languageGate = languageGate
    }

    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func propose(
        for context: TagContext,
        among categories: [SpendCategory]
    ) async -> CategoryID? {
        guard Self.isAvailable, !categories.isEmpty else { return nil }

        let prompt = Self.prompt(for: context, among: categories)
        // Invariant 9. The whole prompt, because the framework language-detects
        // the whole prompt — see the note on `FoundationModelSynthesizer.prompt`
        // for how that was measured, and why the framing here is English prose
        // wrapped around a merchant name that very often is not.
        guard case .allow = languageGate.canProcess(prompt, for: .classification) else { return nil }

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: prompt,
                generating: ProposedTag.self,
                options: options
            )
            return Self.resolve(response.content.bucket, among: categories)
        } catch {
            // A refused or failed call is a row with no suggestion on it. There
            // is nothing to retry against and nothing to fall back to that
            // wouldn't be a guess.
            return nil
        }
    }

    /// Exact name match, case- and whitespace-insensitive, against the buckets
    /// that were actually offered.
    ///
    /// No fuzzy matching, deliberately. "Food" against "Food & Dining" is an
    /// easy call and "Transport" against "Ride & Transport" and "Travel" is not,
    /// and a near-miss resolved by string distance is a bucket the user did not
    /// pick chosen by a rule nobody can read. `TagStore` already draws this
    /// line — a category outside the canonical list is a detectable event, not
    /// free text to be accepted — and the cost of a refusal here is one untagged
    /// row.
    static func resolve(_ name: String, among categories: [SpendCategory]) -> CategoryID? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        return categories.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted }?.id
    }

    // MARK: - Prompt

    private static let instructions = """
    You are helping someone file a purchase they have already made into one of \
    the spending buckets they set up for themselves. You are given the name of \
    the merchant as it appeared on the receipt, and the list of buckets.

    RULES:
    1. Choose exactly one bucket, and copy its name character for character from \
    the list. A bucket that is not on the list is not an answer.
    2. Judge from the merchant's name and nothing else. Do not assume anything \
    about the person from the amount, and never comment on whether the purchase \
    was a good idea.
    3. Many merchant names are Indonesian, and many are shortened or have a city \
    or a branch appended. Read what you can and choose the closest bucket.
    4. If the name tells you nothing at all, choose the bucket that is most \
    general rather than inventing a specific one.
    """

    /// English prose around a merchant name, for the same measured reason the
    /// synthesizer's prompt is prose: the framework language-identifies the
    /// WHOLE PROMPT, and terse scaffolding around Indonesian text detects as
    /// Indonesian and is refused before the model sees it. Here the receipt text
    /// is one short name rather than 400 characters of it, so the framing wins
    /// easily — but the reason it wins is the framing, and compressing it back
    /// into labels would start refusing Indonesian merchants.
    private static func prompt(for context: TagContext, among categories: [SpendCategory]) -> String {
        let list = categories.map { "- \($0.name)" }.joined(separator: "\n")
        return """
        A purchase was made at a merchant whose name appears on the receipt as: \
        \(context.merchantRaw)

        These are the only buckets available. Choose the one this purchase \
        belongs in, and copy its name exactly:

        \(list)
        """
    }
}
