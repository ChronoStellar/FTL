//
//  PatternSynthesis.swift
//  FTL — model/Contracts · Phase 3 · ★ the agentic loop
//
//  The model learns a sender's template instead of a person hand-writing a parser
//  for every bank and merchant. This is where agency belongs.
//
//  The loop:
//
//      observe        a sender with unparsed emails
//        ↓
//      PROPOSE        ★ model reads ~5 examples, emits an ExtractionPattern
//        ↓
//      VERIFY         deterministic: run the pattern over the OTHER emails
//        ↓            from that sender and score it
//      ┌─────────────┴─────────────┐
//      │ passes                     │ fails
//      ▼                            ▼
//   PROMOTE                    feed failures back, re-propose
//   stored rule                 (bounded — see maxAttempts)
//
//  Why this shape and not "ask the model about each email":
//
//  · A wrong pattern is caught by the verifier against real emails, not by the
//    user's ledger. The model's mistakes cost a retry, not a corrupted total.
//  · Synthesis runs ONCE PER SENDER. The measured 3.8s p95 and battery cost stop
//    mattering; a minute of thinking amortised over a thousand future emails.
//  · The 4-of-4 Indonesian refusal hurts far less: synthesis only has to succeed
//    on SOME examples, and whether it succeeded is decided deterministically.
//  · The output is an artifact you can read, diff, version and revoke — not an
//    opinion that evaporates after the call.
//  · Runtime keeps NO model in it. A promoted pattern is executed by
//    PatternDrivenParser, an ordinary deterministic ReceiptParser.
//
//  Invariants 1, 2 and 6 hold unchanged: the model still never writes to the
//  ledger, never does arithmetic, and escalates by flagging.
//

import Foundation

// MARK: - The artifact

/// What the model produces and the verifier judges. Deliberately NOT a regex:
/// regex synthesis is brittle for a small model and unreadable when wrong.
/// Anchors describe *where* a field sits relative to words in the text, which is
/// tractable under guided generation and reads like an explanation.
nonisolated struct ExtractionPattern: Sendable, Hashable, Codable, Identifiable {
    var id: String { senderDomain + ":" + version.description }

    let senderDomain: String
    /// Applies to emails whose subject contains ANY of these. Empty means every
    /// email from the sender.
    ///
    /// A list, not one string: blu's receipts say "Transaction" and its refunds
    /// say "Refund", and a pattern that can only name one silently disowns the
    /// other four emails.
    let subjectContains: [String]

    /// Tried in order; the first that yields a value wins.
    ///
    /// One anchor per field could not express blu: a QRIS purchase labels the
    /// figure `Total`, a card transfer labels it `Amount`. Measured, the
    /// fallback is worth ~3 points of accuracy on its own.
    let amount: [Anchor]
    let merchant: [Anchor]
    /// Substrings that mark the movement as non-spend — "Admin Fee", a bank name.
    let nonSpendMarkers: [String]

    // MARK: Provenance — how far this can be trusted, and why

    let version: Int
    let proposedAt: Date
    /// Emails the verifier scored it against. A pattern verified on 3 emails is
    /// not the same claim as one verified on 116, and the UI should say so.
    let verifiedAgainst: Int
    let accuracy: Double
    /// Which model produced it, or "hand-written" for the reference parsers.
    let author: String

    /// "The value after the word Total, up to the word Amount."
    nonisolated struct Anchor: Sendable, Hashable, Codable {
        /// Text immediately before the value.
        let after: String

        /// Anything that can end the value. The EARLIEST one present wins;
        /// empty means "up to `window` characters".
        ///
        /// Two corrections live here, both found by running the schema against
        /// 112 real blu emails rather than reasoning about it:
        ///
        /// 1. It used to be one string. blu has several layouts —
        ///    `bluAccount SHOPEE bluVirtual Card …` has no `Amount` after the
        ///    merchant at all, where `bluAccount Kembang Tahu … Amount Rp…`
        ///    does. One terminator scored 48%; the list scored 96%.
        /// 2. Empty used to mean "to end of line", which assumed the one-line
        ///    shape of a Gmail snippet. A real HTML receipt is a table: each
        ///    field strips onto its own line, so end-of-line after a label like
        ///    `Total` captures nothing. Anchors run against
        ///    `CapturedEmail.flatText`, where lines don't exist, so an open
        ///    anchor is bounded by length instead.
        let before: [String]

        /// Nth occurrence when `after` repeats — blu says "Rp" many times.
        let occurrence: Int

        /// How far an OPEN anchor (no terminator) reads. Wide enough for a
        /// merchant name and a figure, short enough not to swallow the footer.
        static let window = 60

        /// How far to LOOK for a terminator. Deliberately much larger than
        /// `window`, and confusing the two cost a real run: the model correctly
        /// proposed "the amount sits between `Total` and `Transaction Date`",
        /// but in blu's layout those are 95 characters apart, so a 60-character
        /// search found no terminator and scored a correct pattern at 12%.
        ///
        /// The two bounds answer different questions. `window` asks "how much
        /// text can this value plausibly be?"; this asks "how far away may its
        /// end marker sit?" — and a marker can be far while the value is short,
        /// because everything between them is the rest of the receipt.
        static let searchSpan = 400

        init(after: String, before: [String] = [], occurrence: Int = 1) {
            self.after = after
            self.before = before
            self.occurrence = occurrence
        }
    }
}

// MARK: - Propose (★ model)

nonisolated protocol PatternSynthesizer: Sendable {
    /// Reads a handful of examples and proposes a pattern. `feedback` carries the
    /// previous attempt's failures — this is what makes it a loop rather than a
    /// single shot.
    ///
    /// Must be gated by LanguageGate (Invariant 9), schema-bound via guided
    /// generation, and must never see more than `maxExamples` emails: a small
    /// model given a hundred receipts will summarise, not generalise.
    func propose(
        from examples: [CapturedEmail],
        feedback: PatternFeedback?
    ) async throws -> ExtractionPattern
}

// MARK: - Verify (deterministic)

/// The tool the loop calls. Pure, fast, and the only thing allowed to say a
/// pattern is good — the model does not grade its own work.
nonisolated struct PatternFeedback: Sendable, Hashable, Codable {
    let attempted: Int
    let succeeded: Int
    /// Concrete misses, fed back verbatim. A small model corrects far better from
    /// "you returned '' for this text" than from "accuracy was 0.6".
    let failures: [Failure]

    var accuracy: Double { attempted == 0 ? 0 : Double(succeeded) / Double(attempted) }

    nonisolated struct Failure: Sendable, Hashable, Codable {
        let emailID: String
        let excerpt: String
        let field: String
        let extracted: String?
        let expected: String?
    }
}

// MARK: - The loop

nonisolated struct PatternSynthesisPolicy: Sendable {
    /// One runaway tool loop hit 30 calls in the feasibility run. Bounded, always.
    var maxAttempts = 4
    /// A small model given too many examples summarises instead of generalising.
    var maxExamples = 5
    /// Below this a pattern is discarded rather than promoted. Set high: a
    /// deterministic rule that is wrong 1 time in 10 is worse than no rule, because
    /// nobody reviews a rule the way they review a model's guess.
    var promotionThreshold = 0.95
    /// Never promote off a handful of examples, however well it scored.
    var minimumEvidence = 20

    static let `default` = PatternSynthesisPolicy()
}

nonisolated enum SynthesisOutcome: Sendable {
    case promoted(ExtractionPattern, PatternFeedback)
    /// Tried, never cleared the bar. Carries the best attempt so a human can look.
    case rejected(best: ExtractionPattern?, feedback: PatternFeedback?, attempts: Int)
    /// Not enough emails from this sender to verify anything. Wait, don't guess.
    case insufficientEvidence(available: Int)
    case gated(GateDecision.Reason)
}

/// Where the loop is driven. The implementation owns the propose→verify→retry
/// cycle and the call budget; it is deliberately not the model's job to decide
/// when to stop.
nonisolated protocol PatternLearner: Sendable {
    func learn(
        senderDomain: String,
        from corpus: [CapturedEmail],
        policy: PatternSynthesisPolicy
    ) async -> SynthesisOutcome
}

// MARK: - Which senders to look at

/// The second half of "learn which emails to fetch". Also proposed, also verified:
/// a sender is worth syncing when a pattern for it actually held up, not when the
/// model said it looked promising.
nonisolated struct SenderProfile: Sendable, Hashable, Codable {
    let domain: String
    let emailsSeen: Int
    /// Nil until a pattern has been promoted for it.
    let patternID: String?
    let status: Status

    nonisolated enum Status: String, Sendable, Codable {
        /// Confirmed receipts — sync it.
        case receiptSource
        /// Confirmed noise — never fetch, never spend a model call.
        case ignored
        /// Enough volume to be worth a synthesis attempt.
        case candidate
        /// Attempted and failed. Needs a person, or a bigger model.
        case unlearnable
    }
}
