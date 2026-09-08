//
//  DefaultPatternLearner.swift
//  FTL — services/Pipeline · Stage 4
//
//  Drives propose → verify → retry → promote. Deterministic: the only model call
//  in here is the one it delegates to the synthesizer.
//
//  It is deliberately NOT the model's job to decide when to stop. The call
//  budget, the holdout, the promotion bar and the choice of best-so-far all live
//  on this side of the seam — a loop that asks the model whether it is done is a
//  loop with no bound, and the feasibility run already produced one runaway that
//  hit 30 calls.
//

import Foundation

nonisolated struct DefaultPatternLearner: PatternLearner {
    private let synthesizer: any PatternSynthesizer
    private let verifier = PatternVerifier()
    private let oracle: any PatternOracle

    init(synthesizer: any PatternSynthesizer, oracle: any PatternOracle) {
        self.synthesizer = synthesizer
        self.oracle = oracle
    }

    func learn(
        senderDomain: String,
        from corpus: [CapturedEmail],
        policy: PatternSynthesisPolicy
    ) async -> SynthesisOutcome {
        let fromSender = corpus
            .filter { $0.senderDomain.hasSuffix(senderDomain) }
            .sorted { $0.date > $1.date }

        // Enough to verify against, not merely enough to read. A pattern perfect
        // on three emails has told you nothing.
        guard fromSender.count >= policy.minimumEvidence else {
            return .insufficientEvidence(available: fromSender.count)
        }

        // The examples the model sees are HELD OUT of scoring. Verifying against
        // the same emails it was shown measures memorisation, not generalisation
        // — and generalising to the sender's next receipt is the entire point.
        let examples = Array(fromSender.prefix(policy.maxExamples))
        let holdout = Array(fromSender.dropFirst(policy.maxExamples))

        guard holdout.count >= policy.minimumEvidence else {
            return .insufficientEvidence(available: holdout.count)
        }

        var feedback: PatternFeedback?
        var best: (pattern: ExtractionPattern, feedback: PatternFeedback)?

        for attempt in 1...policy.maxAttempts {
            let proposal: ExtractionPattern
            do {
                proposal = try await synthesizer.propose(from: examples, feedback: feedback)
            } catch SynthesisError.gated(let reason) {
                return .gated(reason)
            } catch {
                // A failed call is not a failed pattern — try again within the
                // budget, and report the best real attempt if none succeed.
                continue
            }

            let scored = verifier.verify(proposal, against: holdout, oracle: oracle)

            if best == nil || scored.accuracy > best!.feedback.accuracy {
                best = (proposal, scored)
            }

            if verifier.clearsBar(scored, policy: policy) {
                return .promoted(Self.stamped(proposal, with: scored, attempt: attempt), scored)
            }

            feedback = scored
        }

        return .rejected(
            best: best.map { Self.stamped($0.pattern, with: $0.feedback, attempt: policy.maxAttempts) },
            feedback: best?.feedback,
            attempts: policy.maxAttempts
        )
    }

    /// Writes the measured numbers onto the artifact. A pattern that says it was
    /// verified against 111 emails at 0.99 is making a checkable claim, and the
    /// UI can say "verified on 111" rather than implying all patterns are equal.
    private static func stamped(
        _ pattern: ExtractionPattern,
        with feedback: PatternFeedback,
        attempt: Int
    ) -> ExtractionPattern {
        ExtractionPattern(
            senderDomain: pattern.senderDomain,
            subjectContains: pattern.subjectContains,
            amount: pattern.amount,
            merchant: pattern.merchant,
            nonSpendMarkers: pattern.nonSpendMarkers,
            version: attempt,
            proposedAt: pattern.proposedAt,
            verifiedAgainst: feedback.attempted,
            accuracy: feedback.accuracy,
            author: pattern.author
        )
    }
}
