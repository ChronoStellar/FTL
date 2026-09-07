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
    /// otherwise the snippet.
    var searchText: String {
        [subject, cleanBody ?? snippet].joined(separator: "\n")
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
