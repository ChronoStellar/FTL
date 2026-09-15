//
//  FailureExplainer.swift
//  FTL — services/Agent · Diagnostics
//
//  When the end-to-end run breaks, the model reads the evidence and says where
//  it would look.
//
//  ## Why this is allowed to exist at all
//
//  Nothing else in this app lets a model produce prose a person then acts on.
//  The design principle is explicit — the model acts autonomously only where
//  false positives are RECOVERABLE — and a wrong explanation is recoverable in
//  the cheapest possible way: you open the file it named, find nothing, and
//  ignore it. No row moves, no ledger is touched, no number changes. It runs on
//  a DEBUG screen, only when something already failed.
//
//  ## The one rule that makes it useful rather than dangerous
//
//  **It is given the evidence and forbidden to go past it.** `EndToEndRunner`
//  already computes why things failed — concrete misses from `PatternFeedback`,
//  coverage complaints, triage counts per gate, the active patterns' provenance.
//  This narrates THAT. It is never asked "why did the pipeline fail", which is
//  an invitation to invent a plausible story about code it cannot see.
//
//  That distinction is the whole reason this is not the thing the roadmap warns
//  about. Every instrument in this repo that gave a confident wrong answer did
//  so by being asked a question the data in front of it could not settle:
//  `coverage` asked "did it extract something", `isLikelyTransaction` asked a
//  vocabulary question of a sender whose vocabulary it had never seen. A model
//  asked to summarise a list of concrete failures is being asked something the
//  list actually contains.
//
//  It is still a guess, and the output says so on every run.
//

import Foundation
import FoundationModels

/// What the model may say. Two fields, both short, because a paragraph invites
/// narration and a named file invites checking.
@Generable
struct FailureReading: Sendable {
    @Guide(description: "One sentence naming the single most likely cause, using ONLY the evidence given. If the evidence does not point at a cause, say exactly that instead of guessing.")
    var likelyCause: String

    @Guide(description: "The one file or function a person should open first, copied from the evidence or the pipeline map. Nothing else.")
    var whereToLook: String
}

nonisolated struct FailureExplainer: Sendable {
    private let languageGate: LanguageGate
    /// Low. This is a summarising task over a list, not a creative one.
    private let options = GenerationOptions(temperature: 0.2)

    init(languageGate: LanguageGate = DefaultLanguageGate()) {
        self.languageGate = languageGate
    }

    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// Nil when there is nothing to explain, no model, or the gate refused.
    /// A missing reading is the normal case and never an error — the
    /// deterministic evidence is already in the report above it.
    func read(_ failures: [EndToEndRunner.Failure]) async -> String? {
        guard !failures.isEmpty, Self.isAvailable else { return nil }

        let prompt = Self.prompt(for: failures)
        // Invariant 9. `.classification` — the strict setting — because this
        // answer is read by a person and nothing checks it.
        guard case .allow = languageGate.canProcess(prompt, for: .classification) else { return nil }

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: prompt, generating: FailureReading.self, options: options
            )
            return """
            \(response.content.likelyCause)
            Start at: \(response.content.whereToLook)
            """
        } catch {
            return nil
        }
    }

    private static let instructions = """
    You are reading the output of a test that has already failed, and saying \
    where a developer should look first.

    You are given the failed assertions and the evidence the test itself \
    recorded. You cannot see the source code.

    RULES:
    1. Use ONLY the evidence given. Never state a number, a filename or a \
    behaviour that does not appear in it.
    2. If the evidence does not point at a cause, say "the evidence does not \
    say" and name the stage that failed. That is a useful answer; a plausible \
    invented one is not.
    3. One sentence. No preamble, no restating the failure back.
    4. When several assertions failed, explain the EARLIEST stage only — later \
    stages run on what earlier ones produced, so a first failure usually \
    explains the rest.
    """

    /// The map is deliberately terse and factual: enough for the model to name a
    /// stage, not enough for it to reason about code it cannot see.
    private static func prompt(for failures: [EndToEndRunner.Failure]) -> String {
        let stages = """
        The pipeline runs in this order, and each stage consumes what the last \
        one produced:

        ① GmailRail.sync fetches mail and asks each active parser to claim it.
        ② PatternDiscovery picks senders by currency, then layout clustering, \
        then distinct figure-counts, then volume. No model is involved.
        ③ DefaultPatternLearner proposes a pattern, PatternVerifier scores it, \
        and the retry is fed the concrete misses. Coverage is used when no \
        oracle exists.
        ④ The rail syncs again; rows land in the approval queue flagged while \
        the pattern is unverified.
        ⑤ DefaultPurchaseTagger suggests a bucket.
        ⑥ Approving rows accrues evidence in PatternMemory until the pattern is \
        vouched for and its rows stop being flagged.
        """

        let listed = failures.map { failure in
            let evidence = failure.evidence.isEmpty
                ? "  (the test recorded no evidence for this one)"
                : failure.evidence.map { "  - \($0)" }.joined(separator: "\n")
            return """
            Stage \(failure.stage) — the check "\(failure.assertion)" produced \
            \(failure.got) where \(failure.expected) was expected.
            Evidence the test recorded:
            \(evidence)
            """
        }.joined(separator: "\n\n")

        return """
        \(stages)

        These checks failed, earliest first.

        \(listed)
        """
    }
}
