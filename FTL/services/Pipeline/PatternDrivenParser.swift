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

nonisolated struct PatternDrivenParser: ReceiptParser, DomainScopedParser {
    let pattern: ExtractionPattern

    init(pattern: ExtractionPattern) {
        self.pattern = pattern
    }

    var id: RuleID { RuleID(rawValue: pattern.id) }

    /// So GmailRail's query covers senders that only a learned pattern
    /// knows about — otherwise a promoted pattern is never sent any mail.
    var domain: String { pattern.senderDomain }

    func canParse(_ email: CapturedEmail) -> Bool {
        guard email.senderDomain.hasSuffix(pattern.senderDomain) else { return false }

        if !pattern.subjectContains.isEmpty {
            let subjectMatches = pattern.subjectContains.contains { needle in
                email.subject.range(of: needle, options: .caseInsensitive) != nil
            }
            guard subjectMatches else { return false }
        }

        // ALL of them, where the subject needs only one. The subject list says
        // "any of the sender's receipt types"; this says "this layout, not the
        // other one it shares a subject with", so any missing word means a
        // different document.
        return pattern.bodyContains.allSatisfy { marker in
            email.flatText.range(of: marker, options: .caseInsensitive) != nil
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

        // First marker present wins, list order deciding — the same precedence
        // rule the anchors use, and the same reason: the synthesizer emits the
        // specific markers (a refund, money arriving) ahead of the generic ones,
        // so a receipt carrying both a bank's "Admin Fee" and its own word
        // "Refund" is read as the refund it is.
        let marker = pattern.nonSpendMarkers.first { $0.matches(text) }

        return .parsed(
            ParsedReceipt(
                date: email.date,
                amount: amount,
                merchantRaw: merchantRaw,
                kind: marker == nil ? .spend : .nonSpend,
                // The marker's own type, when it has one. A pattern that says
                // "the word Refund means a refund" is making a checkable claim
                // and `PatternVerifier` checks it; a pattern that only knows
                // "Admin Fee means not spending" is not, and gets nil.
                nonSpendType: marker?.type,
                // Untyped is the honest uncertainty, so it is the one that
                // flags: the row is money that moved without being a purchase,
                // and which sort is a question only a person can close. Naming
                // a subtype would be inventing one from a substring.
                //
                // A TYPED marker is not flagged, for the same reason
                // `BluReceiptParser` does not flag its refunds: the word came
                // from the sender's own email, and a flag that fires on the
                // sender's own statement is a flag nobody reads.
                flags: marker.map { $0.type == nil
                    ? [ReviewFlag(reason: .ambiguousKind, detail: "Read as non-spend from \"\($0.contains)\"")]
                    : []
                } ?? []
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
