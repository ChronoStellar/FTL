//
//  CorpusEmailSource.swift
//  FTL — services/Evaluation
//
//  The recorded mailbox. Feeds `GmailRail` from `EmailCorpus` instead of the
//  network, so the whole pipeline can be run end to end — repeatably, offline,
//  in about a second — against a thousand real emails.
//
//  This is the difference between testing the PIECES and testing the PIPELINE.
//  Everything measured so far has been a component in isolation: the parser
//  reads 112/112, the pattern covers 96%, the triage separates 21 receipts from
//  107 promos. None of that says a Grab receipt arrives in the approval queue
//  with the right amount on it, because the wiring between the components has
//  never been run over more than a handful of emails.
//
//  Honest about what it does and does not honour:
//
//  · `from:(a OR b)` IS honoured, and deliberately so. That clause is generated
//    from the active parsers, and it decides which mail the rail even asks for
//    — a learned pattern missing from it is a pattern that never runs, which is
//    a real failure mode and one worth exercising.
//  · `newer_than:` is IGNORED. A recorded corpus is by definition historical;
//    applying a 14-day window to it would return nothing and test nothing. The
//    date window is a live-mail concern and is not what this is for.
//  · `limit` is honoured, so the rail's own cap is exercised too.
//

import Foundation

nonisolated struct CorpusEmailSource: CapturedEmailSource {
    let emails: [CapturedEmail]

    init(_ emails: [CapturedEmail]) {
        self.emails = emails
    }

    func fetchCaptured(query: String, limit: Int) async throws -> [CapturedEmail] {
        let domains = Self.senderDomains(in: query)
        let matching = domains.isEmpty
            ? emails
            : emails.filter { email in
                domains.contains { email.senderDomain.hasSuffix($0) }
            }
        // Newest first, like Gmail — so a `limit` smaller than the corpus takes
        // the same slice a real fetch would.
        return Array(matching.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Pulls the domains out of `from:(a OR b OR c)`.
    ///
    /// Parsed rather than passed in, so what gets filtered is the string the
    /// rail actually built. If `senderQuery` ever drops a domain, this notices.
    static func senderDomains(in query: String) -> [String] {
        guard let open = query.range(of: "from:("),
              let close = query[open.upperBound...].firstIndex(of: ")")
        else { return [] }
        return query[open.upperBound..<close]
            .components(separatedBy: " OR ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// A capture log that forgets when the run ends.
///
/// The real one is SwiftData-backed and permanent, which is right for the app
/// and wrong for a harness: a second run would report every email as already
/// seen and measure nothing. Same protocol, so the rail cannot tell.
actor InMemoryCaptureLog: CaptureLog {
    private var seen: Set<String> = []
    private var entries: [CaptureLogEntry] = []

    init() {}

    func unseen(from messageIDs: [String]) async throws -> Set<String> {
        Set(messageIDs).subtracting(seen)
    }

    func record(_ newEntries: [CaptureLogEntry]) async throws {
        for entry in newEntries {
            seen.insert(entry.messageID)
            entries.append(entry)
        }
    }

    func recentlySeenCount() async throws -> Int { seen.count }

    /// What the rail decided about each message, kept so a fixture run can
    /// assert on the verdict — including the ones that produce no row at all.
    /// `notAPurchase` and `skipped` are outcomes worth pinning: a promo that
    /// starts queueing is a regression the provisional store never sees.
    func recorded() -> [CaptureLogEntry] { entries }
}
