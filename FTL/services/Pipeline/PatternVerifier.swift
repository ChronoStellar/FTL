//
//  PatternVerifier.swift
//  FTL — services/Pipeline · Stage 4
//
//  Scores a candidate `ExtractionPattern` against real emails it was not shown.
//
//  This is the half of the loop that makes the other half safe. The model does
//  not grade its own work: it proposes, and this decides — deterministically,
//  against mail the proposal never saw. A wrong pattern costs a retry here
//  instead of a corrupted ledger, which is the entire reason synthesis is
//  allowed to run at all.
//
//  It needs to know what "right" looks like. Two sources, same protocol:
//
//  · `ParserOracle` — a hand-written parser. `BluReceiptParser` reads 112/112
//    real blu emails, so for that sender the truth is already in the codebase
//    and no human labelling is needed to start. The roadmap treats `labels.json`
//    as the blocker on the whole loop; for a sender with a reference parser, it
//    isn't.
//  · A labels-backed oracle, once `labels.json` exists, for senders with no
//    reference parser. Same protocol, so nothing above it changes.
//

import Foundation

/// What a correct read looks like for one email.
nonisolated protocol PatternOracle: Sendable {
    func expected(for email: CapturedEmail) -> ParsedReceipt?
}

/// Truth by hand-written parser. `BluReceiptParser`'s 112/112 is the bar a
/// synthesized pattern has to clear, so it's also the thing that measures it.
nonisolated struct ParserOracle<Parser: ReceiptParser>: PatternOracle {
    let parser: Parser

    init(_ parser: Parser) { self.parser = parser }

    func expected(for email: CapturedEmail) -> ParsedReceipt? {
        guard case .parsed(let receipt) = parser.parse(email) else { return nil }
        return receipt
    }
}

nonisolated struct PatternVerifier: Sendable {

    /// Runs `pattern` over every email the oracle can vouch for, and reports
    /// what it got wrong.
    ///
    /// Three fields decide pass or fail — amount, merchant, and the SPEND
    /// DIRECTION — and a fourth, the non-spend subtype, is reported without
    /// deciding anything. See the notes at each comparison for why the fourth
    /// one is advisory.
    ///
    /// Emails the oracle can't read are EXCLUDED, not counted as failures: they
    /// are cases where nobody knows the right answer, and scoring a candidate
    /// against an unknown would make accuracy a measure of the oracle's gaps
    /// rather than the pattern's quality. `attempted` is the number actually
    /// judged, which is what `PatternSynthesisPolicy.minimumEvidence` gates on.
    func verify(
        _ pattern: ExtractionPattern,
        against emails: [CapturedEmail],
        oracle: some PatternOracle
    ) -> PatternFeedback {
        let candidate = PatternDrivenParser(pattern: pattern)
        var attempted = 0
        var succeeded = 0
        var failures: [PatternFeedback.Failure] = []

        for email in emails {
            guard let truth = oracle.expected(for: email) else { continue }
            attempted += 1

            let result = candidate.parse(email)
            guard case .parsed(let got) = result else {
                failures.append(
                    .init(
                        emailID: email.id,
                        excerpt: Self.excerpt(email),
                        field: Self.missingField(from: result),
                        extracted: nil,
                        expected: "\(truth.amount.minorUnits) · \(truth.merchantRaw)"
                    )
                )
                continue
            }

            var wrong: [PatternFeedback.Failure] = []
            if got.amount != truth.amount {
                wrong.append(
                    .init(
                        emailID: email.id,
                        excerpt: Self.excerpt(email),
                        field: "amount",
                        extracted: String(got.amount.minorUnits),
                        expected: String(truth.amount.minorUnits)
                    )
                )
            }
            if !Self.merchantMatches(got.merchantRaw, truth.merchantRaw) {
                wrong.append(
                    .init(
                        emailID: email.id,
                        excerpt: Self.excerpt(email),
                        field: "merchant",
                        extracted: got.merchantRaw,
                        expected: truth.merchantRaw
                    )
                )
            }
            // Scored, from here on, because it moves a number. A refund or an
            // arriving payment read as `.spend` is added to what you spent —
            // the same failure that made blu's incoming transactions inflate
            // every bucket by the user's own income, arriving this time through
            // a pattern nobody wrote.
            //
            // Until now `verify` compared the amount and the merchant only, so
            // a pattern could get the direction of the money wrong on every
            // email and still score 1.00. That is the one thing coverage was
            // never able to catch either, and the reason the loop could not
            // learn a sender's refunds however many it saw.
            if got.kind != truth.kind {
                wrong.append(
                    .init(
                        emailID: email.id,
                        excerpt: Self.excerpt(email),
                        field: "kind",
                        extracted: got.kind.rawValue,
                        expected: truth.kind.rawValue
                    )
                )
            }

            if wrong.isEmpty { succeeded += 1 } else { failures.append(contentsOf: wrong) }

            // ADVISORY, and deliberately outside the pass/fail above: which
            // sort of non-spend a row is cannot change a total, because every
            // non-spend row is already excluded from every ceiling
            // (Invariant 5). It is a label on a row a person will read.
            //
            // So a wrong subtype teaches without blocking. It reaches the
            // model as a concrete miss on the next attempt — which is how the
            // loop learns to say "Refund" rather than merely "not spending" —
            // and it does not sink an otherwise correct pattern over a
            // distinction the oracle itself often INFERS. `BluReceiptParser`
            // concludes `.transfer` from a bank name sitting beside an account
            // number; no literal marker can be expected to reproduce that, and
            // failing a pattern for not reproducing it would be scoring the
            // oracle's reasoning rather than the pattern's reading.
            if got.nonSpendType != truth.nonSpendType, got.kind == truth.kind {
                failures.append(
                    .init(
                        emailID: email.id,
                        excerpt: Self.excerpt(email),
                        field: "nonSpendType",
                        extracted: got.nonSpendType?.rawValue ?? "unspecified",
                        expected: truth.nonSpendType?.rawValue ?? "unspecified"
                    )
                )
            }
        }

        return PatternFeedback(attempted: attempted, succeeded: succeeded, failures: failures)
    }

    nonisolated struct Coverage: Sendable {
        let rate: Double
        let evidence: Int
        /// Implausible reads, in the shape a retry can be fed.
        let failures: [PatternFeedback.Failure]
    }

    /// How often the pattern reads something PLAUSIBLE — an amount, plus a
    /// merchant that looks like a name rather than a slice of the receipt.
    ///
    /// This exists for senders with no oracle, and it is still a much weaker
    /// claim than `verify`: a pattern anchored on the wrong label reads a
    /// well-formed value from every email and scores 1.0 here. Coverage says
    /// "this pattern fits the template's shape", never "this pattern is
    /// correct". Callers must route the result to a human rather than trust it.
    ///
    /// What changed is the meaning of "something". It used to be "non-empty",
    /// which let the Grab patterns score 1.00 while returning
    /// `"Mahmud Prasetyo. 5.0 Compliments for driver Layanan Mantap Break"` as
    /// a merchant on 21 real rows. Non-empty is not a quality bar; it is barely
    /// a liveness check.
    func coverage(_ pattern: ExtractionPattern, against emails: [CapturedEmail]) -> Coverage {
        let candidate = PatternDrivenParser(pattern: pattern)
        var read = 0
        var considered = 0
        var failures: [PatternFeedback.Failure] = []

        for email in emails where candidate.canParse(email) {
            considered += 1
            guard case .parsed(let receipt) = candidate.parse(email) else { continue }
            guard receipt.amount.minorUnits > 0 else { continue }

            if let complaint = Self.implausibility(of: receipt.merchantRaw) {
                failures.append(
                    .init(
                        emailID: email.id,
                        excerpt: Self.excerpt(email),
                        field: "merchant",
                        extracted: receipt.merchantRaw,
                        expected: complaint
                    )
                )
                continue
            }
            read += 1
        }

        guard considered > 0 else { return Coverage(rate: 0, evidence: 0, failures: []) }
        return Coverage(
            rate: Double(read) / Double(considered),
            evidence: considered,
            failures: failures
        )
    }

    /// Why a read cannot be a merchant name, or nil if nothing is obviously
    /// wrong with it.
    ///
    /// One rule, because one rule is what the data supported. A value that runs
    /// to the anchor's window edge was never terminated — it stopped because it
    /// ran out of room, which means the anchor describes a starting point and
    /// no ending. That is structural, not a guess about what names look like.
    ///
    /// Measured against 137 real rows, using blu's hand-written merchants as
    /// the positive control and the two learned Grab patterns as the negative:
    ///
    ///     runs to the window edge   catches 16/21 bad,  0/116 good
    ///     contains an Rp value       catches  0/21 bad,  0/116 good
    ///     more than six words        catches 20/21 bad,  7/116 good
    ///     grouped number (9.000)     catches 11/21 bad,  1/116 good
    ///
    /// Only the first is free. It is also enough: it takes the ride pattern to
    /// 0/11 and the food pattern to 5/10, both far under `coverageThreshold`.
    ///
    /// A boilerplate-ratio rule — a merchant should not be made of the words
    /// that appear in every one of the sender's emails — was measured too. It
    /// separates well on average (blu 0.14, Grab food 0.71) but rejects 15 of
    /// 116 real blu merchants at a useful threshold, which would sink a GOOD
    /// pattern. Rejected on the numbers, not on taste.
    static func implausibility(of merchant: String) -> String? {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "a merchant name, but nothing was read" }
        // Trimming removes at most the leading space after the anchor, so a
        // value that filled the window lands within a character or two of it.
        if trimmed.count >= ExtractionPattern.Anchor.window - 2 {
            return "a merchant name that ENDS somewhere — this ran to the "
                + "\(ExtractionPattern.Anchor.window)-character limit, so the anchor has no terminator"
        }
        return nil
    }

    /// Promotion is not just "scored well" — it is "scored well against enough
    /// mail to mean something". A pattern that is perfect on three emails has
    /// told you nothing, which is why `minimumEvidence` exists alongside the
    /// threshold.
    func clearsBar(_ feedback: PatternFeedback, policy: PatternSynthesisPolicy) -> Bool {
        feedback.attempted >= policy.minimumEvidence
            && feedback.accuracy >= policy.promotionThreshold
    }

    // MARK: - Comparison

    /// Case- and whitespace-insensitive. A pattern that reads
    /// "KEMBANG TAHU MUSTOPA" where the oracle says "Kembang Tahu Mustopa" has
    /// found the right merchant; failing it would push synthesis toward
    /// over-fitting the oracle's exact casing rather than the receipt's shape.
    /// Invariant 3 is unaffected — `merchantRaw` is still stored exactly as read.
    static func merchantMatches(_ lhs: String, _ rhs: String) -> Bool {
        func normalize(_ value: String) -> String {
            value
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        return normalize(lhs) == normalize(rhs)
    }

    private static func missingField(from result: ReceiptParseResult) -> String {
        switch result {
        case .incomplete(let missing): return missing
        case .notAPurchase: return "classified as not a purchase"
        case .notApplicable: return "pattern did not claim the email"
        case .parsed: return ""
        }
    }

    /// Concrete text, fed back verbatim on a retry. A small model corrects far
    /// better from "you returned '' for this" than from "accuracy was 0.6".
    private static func excerpt(_ email: CapturedEmail) -> String {
        String(email.flatText.prefix(240))
    }
}
