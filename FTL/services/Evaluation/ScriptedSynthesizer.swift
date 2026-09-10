//
//  ScriptedSynthesizer.swift
//  FTL — services/Evaluation
//
//  A `PatternSynthesizer` that returns pre-written proposals instead of calling
//  the model.
//
//  The repo already has `UncallableLearner`, which asserts the model is NEVER
//  reached. Nothing exercised what happens when it IS — so propose → verify →
//  retry → promote, the actual loop, had no deterministic test anywhere.
//
//  ⚠️ **This proves the machinery, not the model.** A scripted synthesizer that
//  returns the right anchors demonstrates that the verifier scores, the retry
//  feeds concrete misses back, the plausibility rules fire, and promotion gates.
//  It says nothing whatsoever about whether a real on-device model would propose
//  those anchors. Do not read a green run here as evidence about the model —
//  that measurement is `Settings → Developer → Pattern synthesis`, on a device,
//  and it is nondeterministic by nature.
//
//  The scripts deliberately include failures, because a loop that is only ever
//  handed correct answers tests one branch:
//
//  · **nusabank** — attempt 1 leaves the merchant anchor with no terminator, so
//    the value runs to the window edge and `PatternVerifier.implausibility`
//    refuses it. Attempt 2, fed that concrete miss, adds the terminator.
//  · **dompetku** — every attempt is anchored on `Tujuan`, which is followed by
//    the same string in every email. There is no better anchor available, so it
//    fails all four attempts on the constant-merchant check. That is the
//    designed outcome: the sender's counterparty carries no information.
//

import Foundation

/// Keyed on sender + layout, then attempt number.
nonisolated struct ScriptedSynthesizer: PatternSynthesizer {
    private let attempts: Attempts

    init() { self.attempts = Attempts() }

    func propose(
        from examples: [CapturedEmail],
        feedback: PatternFeedback?
    ) async throws -> ExtractionPattern {
        guard let first = examples.first else { throw SynthesisError.noExamples }
        let key = Self.key(for: first)
        let attempt = await attempts.next(for: key)
        guard let script = Self.scripts[key] else { throw SynthesisError.emptyProposal }
        return script(attempt)
    }

    /// Which layout these examples are, decided the same way `SenderTriage`
    /// would — by a word that appears in one layout and not the other.
    static func key(for email: CapturedEmail) -> String {
        let domain = email.senderDomain
        let text = email.flatText.lowercased()
        if domain.hasSuffix("kirimin.example.com") {
            return text.contains("perjalanan") ? "kirimin/ride" : "kirimin/food"
        }
        return domain
    }

    private actor Attempts {
        private var counts: [String: Int] = [:]
        func next(for key: String) -> Int {
            counts[key, default: 0] += 1
            return counts[key]!
        }
    }

    // MARK: - The scripts

    private typealias Script = (Int) -> ExtractionPattern

    private static func pattern(
        _ domain: String,
        subject: [String],
        amount: ExtractionPattern.Anchor,
        merchant: ExtractionPattern.Anchor,
        markers: [ExtractionPattern.NonSpendMarker] = []
    ) -> ExtractionPattern {
        ExtractionPattern(
            senderDomain: domain, template: "", subjectContains: subject, bodyContains: [],
            amount: [amount], merchant: [merchant], nonSpendMarkers: markers,
            version: 1, proposedAt: .now, verifiedAgainst: 0, accuracy: 0,
            author: "scripted-fixture"
        )
    }

    private static let scripts: [String: Script] = [
        "nusabank.example.com": { attempt in
            pattern("nusabank.example.com",
                subject: ["Payment"],
                amount: .init(after: "Total", before: ["Reference"]),
                // Attempt 1: no terminator, so the merchant runs to the window
                // edge. Attempt 2 is what the concrete miss should teach.
                merchant: .init(after: "Merchant", before: attempt == 1 ? [] : ["Total"]))
        },
        "kirimin/ride": { _ in
            pattern("kirimin.example.com",
                subject: ["Kirimin Receipt"],
                amount: .init(after: "Total", before: ["Kode"]),
                merchant: .init(after: "Driver", before: ["Total"]))
        },
        "kirimin/food": { _ in
            pattern("kirimin.example.com",
                subject: ["Kirimin Receipt"],
                amount: .init(after: "Total", before: ["Kode"]),
                merchant: .init(after: "Restoran", before: ["Total"]))
        },
        "dompetku.example.com": { _ in
            // The only counterparty label this sender has, and it is followed by
            // the same words every time. No attempt can do better.
            pattern("dompetku.example.com",
                subject: ["Top Up"],
                amount: .init(after: "Total", before: ["ID"]),
                merchant: .init(after: "Tujuan", before: ["Total"]))
        },
    ]
}
