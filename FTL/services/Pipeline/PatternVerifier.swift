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

            if wrong.isEmpty { succeeded += 1 } else { failures.append(contentsOf: wrong) }
        }

        return PatternFeedback(attempted: attempted, succeeded: succeeded, failures: failures)
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
