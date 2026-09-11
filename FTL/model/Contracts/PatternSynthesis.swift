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
    /// Sender, layout, version. The layout is in here because one sender has
    /// more than one — Grab's rides and its food orders are different documents
    /// under an identical subject, and keying on the sender alone made the
    /// second pattern overwrite the first.
    var id: String {
        template.isEmpty
            ? senderDomain + ":" + version.description
            : senderDomain + "/" + template + ":" + version.description
    }

    /// Whether a `RuleID` names a learned pattern rather than a hand-written
    /// parser.
    ///
    /// The two are deliberately indistinguishable to the rail — that is the
    /// whole point of `PatternDrivenParser` — but `PatternMemory` has to tell
    /// them apart, because queue evidence about `blu-receipt` would be evidence
    /// about a person's Swift, not about anything the loop learned.
    ///
    /// Keyed on the shape `id` builds: a trailing `:version`. A hand-written
    /// parser's id is a slug (`blu-receipt`) and has no colon, so this is a
    /// property of the format rather than a naming convention anyone has to
    /// remember.
    static func namesPattern(_ ruleID: RuleID) -> Bool {
        guard let colon = ruleID.rawValue.lastIndex(of: ":") else { return false }
        return Int(ruleID.rawValue[ruleID.rawValue.index(after: colon)...]) != nil
    }

    /// Which TEMPLATE a rule reads, independent of which attempt at it this
    /// is — the same trailing `:N` this file already strips to answer
    /// "is this a pattern at all", stripped here to answer "which one".
    ///
    /// This exists for `TagContext.layout` (`TagKey`, tag accrual). Without
    /// it, re-promoting a pattern to a better version — exactly what
    /// `DiscoverySync` and a manual re-run both do — silently changes the
    /// layout key every learned-sender row accrues under: `grab.com/
    /// compliments:1` and `grab.com/compliments:2` are the SAME real
    /// template, read one attempt apart, and treating them as two different
    /// layouts would orphan a merchant's whole tag history on every
    /// re-synthesis — a much bigger and more general effect than the
    /// Grab/Shopee splitting `TagKey` was actually built for. A hand-written
    /// parser's id has no colon at all, so it passes through unchanged.
    static func templateIdentity(of ruleID: RuleID) -> String {
        guard let colon = ruleID.rawValue.lastIndex(of: ":"),
              Int(ruleID.rawValue[ruleID.rawValue.index(after: colon)...]) != nil
        else { return ruleID.rawValue }
        return String(ruleID.rawValue[ruleID.rawValue.startIndex..<colon])
    }

    let senderDomain: String

    /// Which of the sender's layouts this reads. Empty for a sender with only
    /// one, and for the layout that is a subset of another. See `SenderTriage`.
    let template: String

    /// Applies to emails whose subject contains ANY of these. Empty means every
    /// email from the sender.
    ///
    /// A list, not one string: blu's receipts say "Transaction" and its refunds
    /// say "Refund", and a pattern that can only name one silently disowns the
    /// other four emails.
    let subjectContains: [String]

    /// Applies only to emails whose body contains ALL of these — the layout
    /// discriminator, and the reason `subjectContains` isn't enough.
    ///
    /// Every one of Grab's 21 receipts has the subject "Your Grab E-Receipt",
    /// and half of them are a ride receipt while half are a food order with no
    /// field in common. Subject matching handed the verifier a holdout of two
    /// different documents and scored a correct pattern at 0.52.
    ///
    /// Chosen deterministically by `SenderTriage`, not proposed by the model:
    /// it is a fact about which emails cluster together, and the clustering
    /// already computed it. It also turns out to filter marketing for free —
    /// `compliments` selects 11 ride receipts out of Grab's 128 emails.
    let bodyContains: [String]

    /// Tried in order; the first that yields a value wins.
    ///
    /// One anchor per field could not express blu: a QRIS purchase labels the
    /// figure `Total`, a card transfer labels it `Amount`. Measured, the
    /// fallback is worth ~3 points of accuracy on its own.
    let amount: [Anchor]
    let merchant: [Anchor]

    /// Text that marks the movement as non-spend, each carrying WHICH kind of
    /// non-spend it marks. Tried in order; the first one present wins, the same
    /// rule as `Anchor`.
    ///
    /// This used to be a bare `[String]`, and a pattern could therefore say
    /// "not spending" and nothing more. That covered a transfer adequately and
    /// covered the two cases that actually change what a person sees not at
    /// all:
    ///
    /// · a **refund**, which is the sender undoing a purchase you already have
    ///   a row for;
    /// · **money received**, which is not a purchase in either direction.
    ///
    /// Both were reachable only by hand — `BluReceiptParser` reads its own
    /// subject line for "Refund" and "Incoming" — so every sender the loop
    /// learns instead of a person writing it lost the distinction. A learned
    /// pattern could label a refund `nonSpend` if the model happened to guess a
    /// marker, and could never say what it was.
    ///
    /// The lesson from the anchors applies unchanged: the loop can only correct
    /// what the schema lets it say.
    let nonSpendMarkers: [NonSpendMarker]

    // MARK: Provenance — how far this can be trusted, and why

    let version: Int
    let proposedAt: Date
    /// Emails the verifier scored it against. A pattern verified on 3 emails is
    /// not the same claim as one verified on 116, and the UI should say so.
    let verifiedAgainst: Int
    let accuracy: Double
    /// Which model produced it, or "hand-written" for the reference parsers.
    let author: String

    /// "If the text contains the word Refund, this is a refund."
    nonisolated struct NonSpendMarker: Sendable, Hashable, Codable {
        /// Literal text, matched case-insensitively against `flatText` — which
        /// includes the SUBJECT line, and that is where senders usually say it.
        /// blu's refunds are announced in the subject and nowhere else.
        let contains: String

        /// Which kind of non-spend this marker means, or nil for "not spending,
        /// and the pattern cannot say what it is".
        ///
        /// Nil is a real and honest answer — "Admin Fee" tells you a bank was
        /// involved, not what the movement was — and `PatternDrivenParser`
        /// flags a row it settles that way rather than picking a type. Inventing
        /// a subtype from a substring is exactly the guessing Invariant 6 exists
        /// to prevent.
        let type: NonSpendType?

        init(contains: String, type: NonSpendType? = nil) {
            self.contains = contains
            self.type = type
        }

        func matches(_ text: String) -> Bool {
            !contains.isEmpty && text.range(of: contains, options: .caseInsensitive) != nil
        }
    }

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

/// Hand-written so patterns stored before layouts existed still decode.
///
/// In an extension, not the struct body, so the memberwise initialiser survives.
/// Synthesised decoding requires every key to be present regardless of property
/// defaults, and a promoted pattern already on disk has neither `template` nor
/// `bodyContains` — throwing on it would silently retire what the loop learned,
/// which is the one thing persistence was added to prevent.
extension ExtractionPattern {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            senderDomain: try container.decode(String.self, forKey: .senderDomain),
            template: try container.decodeIfPresent(String.self, forKey: .template) ?? "",
            subjectContains: try container.decode([String].self, forKey: .subjectContains),
            bodyContains: try container.decodeIfPresent([String].self, forKey: .bodyContains) ?? [],
            amount: try container.decode([Anchor].self, forKey: .amount),
            merchant: try container.decode([Anchor].self, forKey: .merchant),
            nonSpendMarkers: try container.decodeIfPresent([NonSpendMarker].self, forKey: .nonSpendMarkers) ?? [],
            version: try container.decode(Int.self, forKey: .version),
            proposedAt: try container.decode(Date.self, forKey: .proposedAt),
            verifiedAgainst: try container.decode(Int.self, forKey: .verifiedAgainst),
            accuracy: try container.decode(Double.self, forKey: .accuracy),
            author: try container.decode(String.self, forKey: .author)
        )
    }
}

/// Decodes from a bare string as well as an object, so every pattern promoted
/// before markers carried a type still loads — as an untyped marker, which is
/// exactly what it was.
///
/// The same argument as `ExtractionPattern.init(from:)` above: throwing here
/// would silently retire what the loop learned, and persistence exists to stop
/// precisely that.
extension ExtractionPattern.NonSpendMarker {
    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let legacy = try? single.decode(String.self) {
            self.init(contains: legacy)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            contains: try container.decode(String.self, forKey: .contains),
            type: try container.decodeIfPresent(NonSpendType.self, forKey: .type)
        )
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

    /// A provisional pattern needs less evidence, precisely because it is not
    /// trusted: every row it produces is flagged for a human.
    ///
    /// Lowered from 10 when the unit stopped being the sender and became the
    /// LAYOUT. Grab's 21 receipts are two layouts of 11 and 10; holding out 5
    /// examples from each leaves 6 and 5, so a per-sender bar of 10 makes every
    /// multi-layout sender permanently unlearnable — the exact senders this
    /// change exists to reach.
    ///
    /// Five is thinner than it looks: at `coverageThreshold` 0.9, five held-out
    /// emails means all five must read, because four of five is 0.8.
    var minimumProvisionalEvidence = 5

    /// A lower `minimumProvisionalEvidence` for a sender's OTHER layouts,
    /// once at least one of its layouts is already active.
    ///
    /// The volume floor exists to answer one question — "is this sender
    /// real, or a brochure?" — and an active pattern for the sender has
    /// already answered it. A second, rarer layout from the SAME sender
    /// (blu's refunds against its 95 identical transaction receipts) doesn't
    /// need to re-clear that bar from nothing; it only needs enough of its
    /// own emails to propose from and a thin real holdout to check against.
    ///
    /// Reported directly: pure-agent mode (no preset, no oracle) missed real
    /// mail that the preset used to cover, because minority layouts never
    /// reached the normal floor. `PatternDiscovery.candidates` and
    /// `run(over:isRead:knownSenders:)` apply this instead of
    /// `minimumProvisionalEvidence` for any sender in the caller's
    /// `knownSenders` set.
    ///
    /// ⚠️ Unmeasured, unlike `minimumProvisionalEvidence` above — a judgment
    /// call, not a further-tuned number. Two is thin: `maxExamples` +
    /// this is 7 emails total, meaning as few as 2 held out to verify
    /// against, and `coverageThreshold` 0.9 at 2 means both must read.
    /// Revisit once there are real minority-layout runs to measure instead
    /// of one report ("we just missed a bit more emails").
    var minimumProvisionalEvidenceForKnownSender = 2

    /// Share of the held-out emails a pattern must read SOMETHING plausible
    /// from before it is worth a person's attention.
    var coverageThreshold = 0.9

    /// How many DIFFERENT figure-fingerprints a layout must produce before it is
    /// worth a model call. See `SenderTriage.Template.distinctAmounts`.
    ///
    /// This is the check that lets the agent point itself at unknown senders
    /// without spending its budget learning to read a discount banner. Ranked by
    /// volume alone, the top candidates in the real corpus are Apple's "your
    /// iCloud storage is full" and Traveloka's discount campaign — both
    /// templated, both full of Rp, neither a transaction. A pattern learned from
    /// either reads a figure out of every email and scores 1.0 coverage, which
    /// is exactly the failure coverage cannot detect.
    ///
    /// An absolute count, not a share of the mail. It was a ratio (≥0.5) until
    /// 2026-09-09, and the ratio's denominator is your email count — so it was
    /// bounded above by (distinct fingerprints) ÷ (how much you use the sender),
    /// and a merchant got *harder* to learn the more you transacted with it.
    /// Measured, real senders produce 10–50 distinct fingerprints and every
    /// brochure in the corpus produces exactly ONE, so five sits in a 10× gap.
    ///
    /// Widening the scan window was tried at the same time and REJECTED on the
    /// measurement: falling back to the whole body when the head yields nothing
    /// takes Traveloka from 1 fingerprint to 14 and turns a brochure into a
    /// candidate. A promotion has no transaction block, and finding no figures
    /// in the head is the honest signal for that.
    var minimumDistinctAmounts = 5

    static let `default` = PatternSynthesisPolicy()
}

nonisolated enum SynthesisOutcome: Sendable {
    case promoted(ExtractionPattern, PatternFeedback)

    /// Cleared a COVERAGE bar, with no oracle able to say whether what it read
    /// was right.
    ///
    /// For a sender with no reference parser and no labels there is nothing to
    /// score against, and coverage is emphatically not correctness — a pattern
    /// anchored on the wrong label reads a value from every email and scores
    /// 100%. So this is not promotion: it means "worth showing a person". Rows
    /// produced by such a pattern are flagged in the approval queue, and the
    /// human gate that already exists does the verifying.
    ///
    /// This is the trust ladder working as designed — Assist, never Auto.
    case provisional(ExtractionPattern, coverage: Double, evidence: Int)
    /// Tried, never cleared the bar. Carries the best attempt so a human can look.
    ///
    /// `lastError` is the last thing the model call itself threw, if any. A
    /// proposal that scored badly and a call that never returned a proposal are
    /// different failures with the same verdict, and reporting them identically
    /// is how a framework-level refusal gets misread as a bad pattern.
    case rejected(
        best: ExtractionPattern?,
        feedback: PatternFeedback?,
        attempts: Int,
        lastError: String?
    )
    /// Not enough emails from this sender to verify anything. Wait, don't guess.
    case insufficientEvidence(available: Int)

    /// The layout repeats the same figures in every email, so it is an
    /// advertisement, a statement of prices, or a notification — not a record
    /// of transactions. Refused BEFORE the model call, not after: this is the
    /// check that lets the loop point itself at unknown senders without
    /// spending its budget learning to read a discount banner.
    case notTransactional(distinctAmounts: Int, of: Int)
    case gated(GateDecision.Reason)
}

/// What one run produced for one of the sender's layouts.
nonisolated struct TemplateOutcome: Sendable {
    /// The layout's readable key, e.g. `compliments`. Empty for a sender with
    /// one layout.
    let template: String
    /// What made this layout distinguishable — the pattern's `bodyContains`.
    let discriminators: [String]
    /// How many of the sender's emails are in this layout.
    let emailCount: Int
    /// A real subject line from it, so a person can tell which one this is.
    let sampleSubject: String
    let outcome: SynthesisOutcome
}

/// Where the loop is driven. The implementation owns the propose→verify→retry
/// cycle and the call budget; it is deliberately not the model's job to decide
/// when to stop.
nonisolated protocol PatternLearner: Sendable {
    /// One outcome PER LAYOUT, not per sender.
    ///
    /// This used to return a single outcome, and that was the bug behind Grab's
    /// rejection: it forced two unrelated document shapes through one pattern
    /// and scored the result against a holdout containing both. A sender has as
    /// many templates as it has, and the loop has to be able to say so.
    func learn(
        senderDomain: String,
        from corpus: [CapturedEmail],
        policy: PatternSynthesisPolicy
    ) async -> [TemplateOutcome]
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
