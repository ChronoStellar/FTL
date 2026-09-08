//
//  PatternDrivenParser.swift
//  FTL — services/Pipeline · Stage 4
//
//  Executes a stored `ExtractionPattern`. This is what a promoted pattern
//  becomes: an ordinary `ReceiptParser` with no model anywhere near it.
//
//  The whole point of the loop is that the model's output is an ARTIFACT, not an
//  opinion — something you can read, diff, version and revoke. This file is the
//  proof: a synthesized pattern and a hand-written parser are the same kind of
//  thing to everything downstream, and the rail can't tell them apart.
//

import Foundation

nonisolated struct PatternDrivenParser: ReceiptParser {
    let pattern: ExtractionPattern

    init(pattern: ExtractionPattern) {
        self.pattern = pattern
    }

    var id: RuleID { RuleID(rawValue: pattern.id) }

    func canParse(_ email: CapturedEmail) -> Bool {
        guard email.senderDomain.hasSuffix(pattern.senderDomain) else { return false }
        guard !pattern.subjectContains.isEmpty else { return true }
        return pattern.subjectContains.contains { needle in
            email.subject.range(of: needle, options: .caseInsensitive) != nil
        }
    }

    func parse(_ email: CapturedEmail) -> ReceiptParseResult {
        guard canParse(email) else { return .notApplicable }

        // flatText, always — anchors assume fields sit beside each other,
        // which is only true once whitespace is collapsed. See Anchor.before.
        let text = email.flatText

        guard let merchantRaw = Self.extractFirst(pattern.merchant, from: text), !merchantRaw.isEmpty else {
            return .incomplete(missing: "merchant")
        }
        guard let amount = pattern.amount.lazy
            .compactMap({ Self.extract($0, from: text) })
            .compactMap({ IndonesianMoney.first(in: $0) })
            .first
        else {
            return .incomplete(missing: "amount")
        }

        let isNonSpend = pattern.nonSpendMarkers.contains { marker in
            text.range(of: marker, options: .caseInsensitive) != nil
        }

        return .parsed(
            ParsedReceipt(
                date: email.date,
                amount: amount,
                merchantRaw: merchantRaw,
                kind: isNonSpend ? .nonSpend : .spend,
                // Which KIND of non-spend needs more than a substring match, and
                // guessing between transfer/topup/refund would be inventing.
                // Flagged as non-spend and left for the approver to narrow.
                nonSpendType: nil,
                flags: []
            )
        )
    }

    // MARK: - Anchors

    /// The first anchor in `anchors` that yields a non-empty value.
    static func extractFirst(_ anchors: [ExtractionPattern.Anchor], from text: String) -> String? {
        anchors.lazy.compactMap { extract($0, from: text) }.first { !$0.isEmpty }
    }

    /// The text after `after`'s Nth occurrence, up to the EARLIEST terminator.
    ///
    /// An empty `before` means "up to `Anchor.window` characters" — not "to end
    /// of line", which the contract originally said. That assumed the one-line
    /// shape of a Gmail snippet; a real HTML receipt is a table, every field on
    /// its own line, so end-of-line after a label like `Total` captures
    /// *nothing*. Anchors run on `CapturedEmail.flatText`, where lines don't
    /// exist, and an open anchor is bounded by length instead.
    static func extract(_ anchor: ExtractionPattern.Anchor, from text: String) -> String? {
        var searchStart = text.startIndex
        var found: Range<String.Index>?

        for _ in 0..<max(1, anchor.occurrence) {
            guard let next = text.range(
                of: anchor.after,
                options: .caseInsensitive,
                range: searchStart..<text.endIndex
            ) else { return nil }
            found = next
            searchStart = next.upperBound
        }
        guard let found else { return nil }

        let tail = text[found.upperBound...]

        guard !anchor.before.isEmpty else {
            return tail.prefix(ExtractionPattern.Anchor.window)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Terminators are searched over `searchSpan`, not `window` — see the
        // note on those constants. A value can be short while its end marker
        // sits far away, with the rest of the receipt in between.
        let bounded = tail.prefix(ExtractionPattern.Anchor.searchSpan)
        // Earliest terminator present wins — a template that ends the merchant
        // with `bluVirtual` in one layout and `Amount` in another is one
        // pattern, not two.
        let stop = anchor.before
            .compactMap { bounded.range(of: $0, options: .caseInsensitive)?.lowerBound }
            .min()
        guard let stop else {
            // None of them are there. Returning the whole window instead would
            // hand back a merchant with half the receipt glued on, and score as
            // a near-miss rather than the miss it is.
            return nil
        }
        return bounded[bounded.startIndex..<stop]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
