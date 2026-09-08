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

    /// One pass per LAYOUT. See `SenderTriage` for why a sender is not one
    /// template: Grab's rides and its food orders arrive under an identical
    /// subject, and learning them together scored a correct pattern at 0.52.
    func learn(
        senderDomain: String,
        from corpus: [CapturedEmail],
        policy: PatternSynthesisPolicy
    ) async -> [TemplateOutcome] {
        // Triage first: a sender's marketing outnumbers its receipts, and five
        // promos teach the model the shape of a discount banner.
        let templates = SenderTriage.templates(
            from: corpus.filter { $0.senderDomain.hasSuffix(senderDomain) }
        )
        guard !templates.isEmpty else {
            return [
                TemplateOutcome(
                    template: "",
                    discriminators: [],
                    emailCount: 0,
                    sampleSubject: "",
                    outcome: .insufficientEvidence(available: 0)
                )
            ]
        }

        var outcomes: [TemplateOutcome] = []
        for template in templates {
            outcomes.append(
                TemplateOutcome(
                    template: template.key,
                    discriminators: template.discriminators,
                    emailCount: template.emails.count,
                    sampleSubject: template.emails.first?.subject ?? "",
                    outcome: await learn(template: template, policy: policy)
                )
            )
        }
        return outcomes
    }

    private func learn(
        template: SenderTriage.Template,
        policy: PatternSynthesisPolicy
    ) async -> SynthesisOutcome {
        let fromSender = template.emails

        // Cheapest refusal first, and the only one that costs nothing at all:
        // if the layout's figures never change, it is a price list rather than
        // a ledger. Checked before the evidence bar because a brochure with
        // plenty of evidence is still a brochure.
        guard template.amountVariance >= policy.minimumAmountVariance else {
            return .notTransactional(amountVariance: template.amountVariance)
        }

        // Enough to verify against, not merely enough to read. A pattern perfect
        // on three emails has told you nothing.
        // The floor is the provisional one; a sender that clears only that still
        // has somewhere to go — the approval queue.
        guard fromSender.count >= policy.maxExamples + policy.minimumProvisionalEvidence else {
            return .insufficientEvidence(available: fromSender.count)
        }

        // The examples the model sees are HELD OUT of scoring. Verifying against
        // the same emails it was shown measures memorisation, not generalisation
        // — and generalising to the sender's next receipt is the entire point.
        let examples = Array(fromSender.prefix(policy.maxExamples))
        let holdout = Array(fromSender.dropFirst(policy.maxExamples))

        guard holdout.count >= policy.minimumProvisionalEvidence else {
            return .insufficientEvidence(available: holdout.count)
        }

        var feedback: PatternFeedback?
        var best: (pattern: ExtractionPattern, feedback: PatternFeedback)?
        var lastError: String?

        for attempt in 1...policy.maxAttempts {
            let proposal: ExtractionPattern
            do {
                proposal = try await synthesizer.propose(from: examples, feedback: feedback)
            } catch SynthesisError.gated(let reason) {
                return .gated(reason)
            } catch {
                // A failed call is not a failed pattern — try again within the
                // budget, and report the best real attempt if none succeed.
                //
                // Kept, not discarded: the framework has its own opinion about
                // languages, separate from our gate, and a refusal from inside
                // it looks exactly like a bad pattern from out here unless the
                // error survives to the report.
                lastError = String(describing: error)
                continue
            }

            let scored = verifier.verify(proposal, against: holdout, oracle: oracle)

            if best == nil || scored.accuracy > best!.feedback.accuracy {
                best = (proposal, scored)
            }

            if verifier.clearsBar(scored, policy: policy) {
                return .promoted(Self.stamped(proposal, as: template, with: scored, attempt: attempt), scored)
            }

            // Nothing could vouch for a single email — no reference parser for
            // this sender, no labels. Fall back to coverage, which asks a
            // weaker question ("does this fit the template's shape?") and
            // answers it without an oracle. The result is provisional, and its
            // rows go to a person.
            if scored.attempted == 0 {
                let measured = verifier.coverage(proposal, against: holdout)
                if measured.rate >= policy.coverageThreshold,
                   measured.evidence >= policy.minimumProvisionalEvidence {
                    return .provisional(
                        Self.stamped(proposal, as: template, with: nil, attempt: attempt),
                        coverage: measured.rate,
                        evidence: measured.evidence
                    )
                }

                // Retry with what coverage OBJECTED to, not with silence.
                //
                // This path used to fall through to `feedback = scored`, which
                // for a sender with no oracle is empty by construction —
                // `attempted` is 0, so `failures` is 0. The loop then spent its
                // remaining three attempts re-proposing with no idea what was
                // wrong, for exactly the senders discovery exists to reach.
                //
                // Concrete misses are what corrected blu twice. There is no
                // reason the no-oracle path should be denied them.
                feedback = PatternFeedback(
                    attempted: measured.evidence,
                    succeeded: Int((measured.rate * Double(measured.evidence)).rounded()),
                    failures: measured.failures
                )
                continue
            }

            feedback = scored
        }

        return .rejected(
            best: best.map { Self.stamped($0.pattern, as: template, with: $0.feedback, attempt: policy.maxAttempts) },
            feedback: best?.feedback,
            attempts: policy.maxAttempts,
            lastError: lastError
        )
    }

    /// Writes the measured numbers and the layout onto the artifact.
    ///
    /// A pattern that says it was verified against 111 emails at 0.99 is making
    /// a checkable claim, and the UI can say "verified on 111" rather than
    /// implying all patterns are equal.
    ///
    /// The layout is stamped HERE rather than proposed, because it isn't the
    /// model's to know: which emails cluster together is a fact about the
    /// corpus that `SenderTriage` measured before the model was called.
    private static func stamped(
        _ pattern: ExtractionPattern,
        as template: SenderTriage.Template,
        with feedback: PatternFeedback?,
        attempt: Int
    ) -> ExtractionPattern {
        ExtractionPattern(
            senderDomain: pattern.senderDomain,
            template: template.key,
            subjectContains: pattern.subjectContains,
            bodyContains: template.discriminators,
            amount: pattern.amount,
            merchant: pattern.merchant,
            nonSpendMarkers: pattern.nonSpendMarkers,
            version: attempt,
            proposedAt: pattern.proposedAt,
            // Zero and zero for a provisional pattern, deliberately: it has
            // been verified against nothing, and the UI should be able to say
            // so rather than imply a measurement nobody made.
            verifiedAgainst: feedback?.attempted ?? 0,
            accuracy: feedback?.accuracy ?? 0,
            author: pattern.author
        )
    }
}
