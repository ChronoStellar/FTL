//
//  FoundationModelSynthesizer.swift
//  FTL — services/Agent · Stage 4 · ★ the one model call in the loop
//
//  The model reads ~5 emails from one sender and says WHERE the fields sit:
//  "the amount follows the word Total; the merchant follows bluAccount and ends
//  at Amount or bluVirtual". That is the whole job.
//
//  It also says which words mean the money went the OTHER WAY — a refund, or a
//  payment arriving. Three separate lists rather than one, because a small model
//  copying literals into three named buckets is a different and much easier task
//  than choosing an enum case per string, and because the previous single list
//  could only ever produce "not spending" with no way to say which kind.
//
//  Why this is a safe place for a model when the ledger is not:
//
//  · It proposes a RULE, not a value. Nothing it says reaches a row until
//    PatternVerifier has run the rule over emails the model never saw and scored
//    it against an oracle. A wrong proposal costs a retry.
//  · It runs ONCE PER SENDER, not once per email. The measured 3.8s p95 and the
//    battery cost amortise over every future receipt from that sender.
//  · Its output is an artifact you can read, diff, version and revoke — not an
//    opinion that evaporates after the call.
//  · Invariant 2 holds: it never does arithmetic. It emits anchor strings;
//    IndonesianMoney parses the figure, deterministically, later.
//  · Invariant 9 holds: LanguageGate runs before the call, not after.
//
//  It also does NOT get to grade itself. `ProposedPattern` deliberately has no
//  accuracy or evidence fields — those are stamped by the learner from what the
//  verifier measured.
//

import Foundation
import FoundationModels

/// What the model is allowed to say. Mirrors `ExtractionPattern` minus every
/// field that would let it make a claim about its own quality.
@Generable
struct ProposedPattern: Sendable {
    @Guide(description: "Step-by-step reasoning: quote the exact words in the examples that sit immediately before and after each field, and say what stays the same across all of them.")
    var thinking: String

    @Guide(description: "Words that appear in the SUBJECT of the emails that are receipts, e.g. ['Transaction', 'Refund']. Empty if every email from this sender is a receipt.")
    var subjectContains: [String]

    @Guide(description: "Every label that can appear immediately BEFORE the transaction amount, best first, e.g. ['Total', 'Amount']. Different receipts from one sender often label the figure differently — a purchase may say Total where a transfer says Amount. Copy each character for character. Do not include the amount itself.")
    var amountAfter: [String]

    @Guide(description: "Literal text that can appear immediately AFTER the amount and ends it, e.g. ['Transaction Date', 'Admin Fee']. List every variant seen across the examples. Empty if the amount is the last thing on the line.")
    var amountBefore: [String]

    @Guide(description: "Every label that can appear immediately BEFORE the merchant or counterparty name, best first, e.g. ['bluAccount'].")
    var merchantAfter: [String]

    @Guide(description: "Literal text that can appear immediately AFTER the merchant name and ends it, e.g. ['Amount', 'bluVirtual', 'Admin Fee']. List EVERY variant seen — different receipts from the same sender often end the name differently, and missing one loses those emails entirely.")
    var merchantBefore: [String]

    @Guide(description: "Literal text that appears ONLY in this sender's REFUND or money-back emails — a purchase being reversed. For example ['Refund', 'Dana Dikembalikan', 'Reversal']. Look at the subject lines as well as the bodies. Empty if none of the examples is a refund.")
    var refundMarkers: [String]

    @Guide(description: "Literal text that appears ONLY when money is ARRIVING rather than being spent — an incoming payment, someone paying you, a salary. For example ['Incoming', 'Dana Masuk', 'You received']. Empty if none of the examples is money arriving.")
    var incomingMarkers: [String]

    @Guide(description: "Literal text that marks the movement as an internal transfer, top-up or bank movement rather than a purchase — for example ['Admin Fee', 'Transfer', 'Top Up']. Do NOT repeat anything already listed as a refund or an incoming marker. Empty if this sender only ever sends purchase receipts.")
    var transferMarkers: [String]
}

nonisolated struct FoundationModelSynthesizer: PatternSynthesizer {
    private let languageGate: LanguageGate
    /// Low: this is a copying task, not a creative one. The right answer is
    /// literally present in the examples.
    private let options = GenerationOptions(temperature: 0.1)

    init(languageGate: LanguageGate = DefaultLanguageGate()) {
        self.languageGate = languageGate
    }

    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func propose(
        from examples: [CapturedEmail],
        feedback: PatternFeedback?
    ) async throws -> ExtractionPattern {
        guard !examples.isEmpty else { throw SynthesisError.noExamples }
        guard Self.isAvailable else { throw SynthesisError.modelUnavailable }

        // Invariant 9, applied PER EXAMPLE rather than to the batch.
        //
        // Gating the concatenated prompt lets one email veto a whole sender, and
        // it asks NLLanguageRecognizer for a single verdict over ~3,500 chars of
        // mostly boilerplate. blu's transaction block is English; its footer is
        // an Indonesian legal address, so the blob reads as Indonesian and the
        // sender becomes unlearnable — for reasons that have nothing to do with
        // the template.
        //
        // The roadmap's own argument for why synthesis survives the 4-of-4
        // Indonesian refusal is that it "only has to succeed on SOME examples".
        // That makes the gate a SELECTOR: keep what it passes, drop what it
        // doesn't, and every call still goes out gated.
        let usable = examples.filter { example in
            if case .allow = languageGate.canProcess(Self.excerpt(example), for: .anchorSynthesis) { return true }
            return false
        }
        // Two is the floor for generalising: one example can't tell a label from
        // a value, because everything in it looks constant.
        guard usable.count >= 2 else {
            throw SynthesisError.gated(.unsupportedLanguage)
        }

        let prompt = Self.prompt(examples: usable, feedback: feedback)

        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: prompt,
            generating: ProposedPattern.self,
            options: options
        )

        guard !response.content.amountAfter.isEmpty, !response.content.merchantAfter.isEmpty else {
            throw SynthesisError.emptyProposal
        }

        return Self.pattern(
            from: response.content,
            senderDomain: usable[0].senderDomain,
            version: (feedback == nil ? 1 : 2)
        )
    }

    // MARK: - Prompt

    /// Exposed so the debug probe can send the REAL instructions rather than a
    /// paraphrase — an isolation test that changes two things at once isolates
    /// nothing.
    static var probeInstructions: String { instructions }

    private static let instructions = """
    You are given a few emails from ONE sender. They share a template. Your job \
    is to describe WHERE each field sits in that template, using exact literal \
    text copied from the emails.

    You are NOT extracting values. Do not report an amount or a merchant name. \
    Report the surrounding words that would let a program find them in any \
    future email from this sender.

    RULES:
    1. Every string you emit must appear VERBATIM in the examples. Do not \
    paraphrase, translate, or tidy capitalisation.
    2. Anchors must be text that is the SAME in every email — a label, not a \
    value. "Total" is an anchor; "Rp18.000,00" is a value.
    3. When the examples disagree, list ALL the variants you saw — both the \
    labels before a field and the text that ends it. A missing variant silently \
    loses every email that uses it.
    4. The text you are given has had its whitespace collapsed, so fields sit \
    directly beside each other on one line.
    5. Never do arithmetic and never invent a field that isn't there.
    6. Some of these emails may not be purchases. A sender that takes money \
    also sends refunds, and often reports money arriving. Say which literal \
    words tell those apart — usually one word in the subject line — and put \
    each word under the right heading. Leave a heading empty rather than \
    guessing: a word that appears on ordinary receipts too would label every \
    purchase as a refund.
    """

    /// Framed in English PROSE, deliberately, and this is not a style choice.
    ///
    /// The framework language-identifies the prompt and throws
    /// `unsupportedLanguageOrLocale` when the answer is a language it does not
    /// support. Indonesian is not on its list; Dutch is. Measured with
    /// `NLLanguageRecognizer` over the real corpus, the previous shape —
    /// terse `--- EXAMPLE 1 ---` / `SUBJECT:` / `TEXT:` headers wrapped around
    /// receipt text — detected as:
    ///
    ///     blu   nl 0.49    → Dutch, supported, and blu synthesis worked
    ///     ride  id 0.83    → refused
    ///     food  id 1.00    → refused
    ///
    /// blu passing was the control that proved it: the difference between the
    /// sender that learned and the two that didn't was never the template, the
    /// examples or the model. It was which language a classifier guessed from
    /// the shape of the scaffolding.
    ///
    /// The headers were carrying almost no English while sitting next to 2,000
    /// characters of Indonesian, and — measured — the three-line header block
    /// was itself enough to flip a single ride excerpt from `en 1.00` to
    /// `id 0.83`. Replacing them with sentences puts real English in the prompt
    /// and takes all three to `en 1.00`, the Indonesian food layout included.
    ///
    /// So: keep the framing in prose, and keep it proportional to the receipt
    /// text it wraps. Compressing this back into terse labels will silently
    /// un-learn every non-English sender.
    private static func prompt(examples: [CapturedEmail], feedback: PatternFeedback?) -> String {
        var sections: [String] = [
            """
            These are emails from one sender that share a template. For each \
            field, report the exact literal text that appears immediately \
            before it and immediately after it in the emails below. The emails \
            are shown one after another, each with its subject line and then \
            its collapsed body text.
            """
        ]

        for (index, email) in examples.enumerated() {
            sections.append("""
            Email \(index + 1) of \(examples.count). Its subject line reads: \(email.subject)
            Its body text reads: \(excerpt(email))
            """)
        }

        // The retry is what makes this a loop rather than a single shot. Concrete
        // misses correct a small model far better than a score does.
        if let feedback, !feedback.failures.isEmpty {
            let misses = feedback.failures.prefix(6).map { failure in
                "The field '\(failure.field)' came back as \(failure.extracted.map { "\"\($0)\"" } ?? "nothing at all"), where the correct answer was \"\(failure.expected ?? "")\". That was read from this text: \(failure.excerpt.prefix(160))"
            }.joined(separator: "\n\n")

            sections.append("""
            Your previous attempt was not correct. It read \(feedback.succeeded) \
            of \(feedback.attempted) emails correctly, and here is exactly what \
            went wrong on the ones it missed.

            \(misses)

            Fix the anchors so that these cases work too, without breaking the \
            ones that already worked. If a field ends differently in different \
            emails, list every terminator you have seen.
            """)
        }

        return sections.joined(separator: "\n\n")
    }

    /// The transaction block, not the whole email.
    ///
    /// Everything the anchors describe sits in the first few hundred
    /// characters; the rest is a footer — support numbers, a registered office,
    /// a tax id. Sending it costs context, drags the detected language away from
    /// the template's own, and gives a small model more to summarise. The
    /// policy already caps examples for that reason; this is the same argument
    /// inside one example.
    static func excerpt(_ email: CapturedEmail) -> String {
        String(email.flatText.prefix(excerptLength))
    }

    private static let excerptLength = 400

    // MARK: - Mapping

    /// Provenance fields are stamped here as UNVERIFIED. The learner overwrites
    /// `verifiedAgainst` and `accuracy` from what the verifier measured — the
    /// model is never the source of its own score.
    private static func pattern(
        from proposal: ProposedPattern,
        senderDomain: String,
        version: Int
    ) -> ExtractionPattern {
        ExtractionPattern(
            senderDomain: senderDomain,
            // Layout is not the model's to know — `SenderTriage` measured which
            // emails cluster together before this call, and the learner stamps
            // both fields on the way out.
            template: "",
            subjectContains: proposal.subjectContains,
            bodyContains: [],
            amount: proposal.amountAfter.map {
                ExtractionPattern.Anchor(after: $0, before: proposal.amountBefore)
            },
            merchant: proposal.merchantAfter.map {
                ExtractionPattern.Anchor(after: $0, before: proposal.merchantBefore)
            },
            // Order is precedence — `PatternDrivenParser` takes the first
            // marker present — so the two specific directions go ahead of the
            // catch-all. A refund email that also carries a bank's "Admin Fee"
            // is a refund; read the other way round it would be filed as a
            // transfer and the word the sender actually used would be lost.
            nonSpendMarkers: proposal.refundMarkers.map { .init(contains: $0, type: .refund) }
                + proposal.incomingMarkers.map { .init(contains: $0, type: .incoming) }
                + proposal.transferMarkers.map { .init(contains: $0, type: .transfer) },
            version: version,
            proposedAt: .now,
            verifiedAgainst: 0,
            accuracy: 0,
            author: "on-device-foundation-model"
        )
    }
}

nonisolated enum SynthesisError: Error, Sendable {
    case noExamples
    case modelUnavailable
    /// The model returned no anchor at all. A retry can fix this; a promotion
    /// cannot, so it must not be mistaken for a scored-zero pattern.
    case emptyProposal
    case gated(GateDecision.Reason)
}
