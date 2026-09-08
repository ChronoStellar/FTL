//
//  CapturedEmail.swift
//  FTL — model/Domain
//
//  One email as the Gmail export hands it over. Field names match the JSON
//  exactly so the fixture decodes with no mapping layer — the thing under test
//  should be the thing you actually have.
//
//  `bodyPlain` is optional and frequently absent: receipts are HTML emails, and
//  in the current export only 19% of purchase-ish messages kept a plain body.
//  `snippet` is always present and, for templated senders, often carries the
//  whole transaction. Parsers should treat body as a bonus, not a precondition.
//

import Foundation

nonisolated struct CapturedEmail: Sendable, Hashable, Codable, Identifiable {
    let id: String
    let threadId: String?
    let from: String
    let to: String?
    let subject: String
    /// Gmail's ~200-character preview. Always present.
    let snippet: String
    /// Milliseconds since epoch, as a string — Gmail's own format.
    let internalDate: String
    let labelIds: [String]?
    let bodyPlain: String?
    let bodyHtml: String?

    init(
        id: String,
        threadId: String?,
        from: String,
        to: String?,
        subject: String,
        snippet: String,
        internalDate: String,
        labelIds: [String]?,
        bodyPlain: String?,
        bodyHtml: String?
    ) {
        self.id = id
        self.threadId = threadId
        self.from = from
        self.to = to
        self.subject = subject
        self.snippet = snippet
        self.internalDate = internalDate
        self.labelIds = labelIds
        self.bodyPlain = bodyPlain
        self.bodyHtml = bodyHtml
    }

    /// A live Gmail fetch, in the same shape as the recorded corpus. The export
    /// and the rail share one decoder (`GmailExporter`), so a parser sees no
    /// difference between an email that arrived this morning and one from
    /// `sample.json`.
    init(exported: ExportedEmail) {
        self.init(
            id: exported.id,
            threadId: exported.threadId,
            from: exported.from,
            to: exported.to,
            subject: exported.subject,
            snippet: exported.snippet,
            internalDate: exported.internalDate,
            labelIds: exported.labelIds,
            bodyPlain: exported.bodyPlain,
            bodyHtml: exported.bodyHtml
        )
    }

    /// Cleaned body text: plain body if present, or decoded/stripped HTML layout.
    var cleanBody: String? {
        if let bodyPlain, !bodyPlain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bodyPlain
        }
        if let bodyHtml {
            return HTMLNormalizer.strip(bodyHtml)
        }
        return nil
    }

    /// Everything a parser may read, in priority order: body when present,
    /// otherwise the snippet. Keeps line structure — the model reads this.
    var searchText: String {
        [subject, cleanBody ?? snippet].joined(separator: "\n")
    }

    /// `searchText` with every run of whitespace collapsed to one space.
    ///
    /// **Parsers must match against this, not `searchText`.** The two sources
    /// carry the same words in different shapes: a Gmail snippet is one long
    /// line ("Total Rp18.000,00"), while a stripped HTML body puts each table
    /// cell on its own ("Total\nRp18.000,00"). A parser written against one
    /// silently fails on the other — which is exactly what happened when the
    /// rail started delivering real bodies to a parser measured on snippets.
    /// Flattening makes them the same text.
    var flatText: String {
        searchText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True if the email mentions Indonesian currency (Rp, Rp., IDR).
    var hasCurrencyMarker: Bool {
        TransactionMarkerDetector.hasCurrencyMarker(in: searchText)
    }

    var date: Date {
        Date(timeIntervalSince1970: (Double(internalDate) ?? 0) / 1000)
    }

    /// "blubybcadigital.id" — the dispatch key for a per-sender parser.
    var senderDomain: String {
        guard let at = from.range(of: "@") else { return "" }
        let tail = from[at.upperBound...]
        let cleaned = tail.prefix { $0 != ">" && $0 != " " && $0 != "," }
        return String(cleaned).lowercased()
    }
}
