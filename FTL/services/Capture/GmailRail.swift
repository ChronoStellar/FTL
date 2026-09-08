//
//  GmailRail.swift
//  FTL — services/Capture · Phase 1 · Stage 1 #4
//
//  Gmail → deterministic parser → provisional cache. One sender to start.
//
//  What this does NOT do, deliberately:
//
//  · It does not approve anything. Manual entry auto-approves because a person
//    typed the number; nothing here was typed by anyone, so every row lands
//    `.pending` and waits for the human gate. Invariant 1, and the reason the
//    trust ladder is pinned to Assist.
//  · It does not call the model. A parser either recognises its template or it
//    doesn't. `PurchaseClassifier` is Phase 2 and is not wired here.
//  · It does not drop mail it can't read. A recognised template with a missing
//    field becomes a FLAGGED row, not a silent skip (Invariant 6).
//
//  Idempotency comes from `CaptureLog` — a record of every message id already
//  handled — rather than a `historyId` cursor. A cursor is an optimisation with
//  a failure mode: Gmail expires `startHistoryId` after roughly a week, and a
//  lost or stale one silently re-imports or skips. Asking "have I seen this
//  message?" is correct whether the sync window overlaps, restarts, or runs
//  twice at once. Worth revisiting when the volume justifies it; at a hundred
//  messages a month it does not.
//

import Foundation

nonisolated struct GmailRail: Sendable {
    private let exporter: GmailExporter
    private let parsers: [any ReceiptParser]
    private let provisional: ProvisionalStore
    private let log: CaptureLog

    /// How far back a sync looks. Overlap is free — the capture log dedupes —
    /// so this is sized to survive a week of not opening the app rather than
    /// tuned to the last run.
    private let window = "newer_than:14d"
    private let fetchLimit = 50

    init(
        exporter: GmailExporter,
        parsers: [any ReceiptParser],
        provisional: ProvisionalStore,
        log: CaptureLog
    ) {
        self.exporter = exporter
        self.parsers = parsers
        self.provisional = provisional
        self.log = log
    }

    struct Result: Sendable {
        var fetched = 0
        var alreadySeen = 0
        var queued = 0
        var flagged = 0
        var notAPurchase = 0
        var skipped = 0

        var summary: String {
            if fetched == 0 { return "No new mail in the window." }
            var parts = ["\(queued) queued"]
            if flagged > 0 { parts.append("\(flagged) flagged") }
            if skipped + notAPurchase > 0 { parts.append("\(skipped + notAPurchase) not receipts") }
            return parts.joined(separator: " · ")
        }
    }

    /// One pass. Safe to run repeatedly and concurrently-ish: anything already
    /// in the capture log is skipped before it costs a parse or a write.
    @discardableResult
    func sync() async throws -> Result {
        var result = Result()

        let query = ([window] + [senderQuery()]).joined(separator: " ")
        let emails = try await exporter.fetchCaptured(query: query, limit: fetchLimit)
        result.fetched = emails.count
        guard !emails.isEmpty else { return result }

        let unseen = try await log.unseen(from: emails.map(\.id))
        result.alreadySeen = emails.count - unseen.count

        var entries: [ProvisionalEntry] = []
        var logEntries: [CaptureLogEntry] = []

        for email in emails where unseen.contains(email.id) {
            guard let parser = parsers.first(where: { $0.canParse(email) }) else {
                logEntries.append(.init(messageID: email.id, verdict: .skipped, entryID: nil, parserID: nil))
                result.skipped += 1
                continue
            }

            switch parser.parse(email) {
            case .parsed(let receipt):
                let entry = Self.entry(from: receipt, email: email, parser: parser)
                entries.append(entry)
                logEntries.append(.init(messageID: email.id, verdict: .queued, entryID: entry.id, parserID: parser.id.rawValue))
                result.queued += 1

            case .incomplete(let missing):
                // The template matched but a field didn't. Queue it flagged so a
                // person sees it, rather than dropping a real purchase because
                // one regex moved.
                let receipt = ParsedReceipt(
                    date: email.date,
                    amount: .zero,
                    merchantRaw: email.subject,
                    kind: .spend,
                    nonSpendType: nil,
                    flags: [ReviewFlag(reason: .unparseable, detail: "missing \(missing)")]
                )
                let entry = Self.entry(from: receipt, email: email, parser: parser)
                entries.append(entry)
                logEntries.append(.init(messageID: email.id, verdict: .flagged, entryID: entry.id, parserID: parser.id.rawValue))
                result.flagged += 1

            case .notAPurchase:
                logEntries.append(.init(messageID: email.id, verdict: .notAPurchase, entryID: nil, parserID: parser.id.rawValue))
                result.notAPurchase += 1

            case .notApplicable:
                logEntries.append(.init(messageID: email.id, verdict: .skipped, entryID: nil, parserID: parser.id.rawValue))
                result.skipped += 1
            }
        }

        // Cache first, log second. If the log write fails the worst case is a
        // duplicate on the next run, which a person can reject. The other order
        // risks marking mail handled that never made it into the queue — spend
        // that silently disappears, which is the failure this app cares most
        // about avoiding.
        if !entries.isEmpty {
            try await provisional.insert(entries)
        }
        try await log.record(logEntries)

        return result
    }

    // MARK: - Building the row

    private static func entry(
        from receipt: ParsedReceipt,
        email: CapturedEmail,
        parser: any ReceiptParser
    ) -> ProvisionalEntry {
        let transaction = NormalizedTransaction(
            id: UUID(),
            documentID: UUID(),
            source: .email,
            date: receipt.date,
            amount: receipt.amount,
            // Invariant 3: exactly what the parser read, never tidied.
            merchantRaw: receipt.merchantRaw,
            merchant: nil,
            lineItems: [],
            fingerprint: Fingerprint(amount: receipt.amount, date: receipt.date)
        )

        return ProvisionalEntry(
            id: UUID(),
            transaction: transaction,
            resolution: ProvisionalEntry.Resolution(
                kind: receipt.kind,
                nonSpendType: receipt.nonSpendType,
                // The parser reads a receipt; it does not know the user's
                // buckets. Categorising is the approver's job (or, later, model
                // job 1) — guessing here would put spend in a bucket nobody chose.
                categoryID: nil,
                merchantID: nil,
                splits: [],
                mergedFrom: []
            ),
            provenance: .rule(parser.id),
            flags: receipt.flags,
            status: .pending,
            createdAt: .now
        )
    }

    /// `from:(a OR b)` over every parser's domain, so the fetch itself is
    /// narrow — model calls and bandwidth are never spent on LinkedIn.
    private func senderQuery() -> String {
        let domains = parsers.compactMap { ($0 as? DomainScopedParser)?.domain }
        guard !domains.isEmpty else { return "" }
        return "from:(" + domains.joined(separator: " OR ") + ")"
    }
}

/// A parser that knows which sender it belongs to, so the rail can narrow the
/// Gmail query instead of downloading everything and discarding most of it.
nonisolated protocol DomainScopedParser {
    var domain: String { get }
}
