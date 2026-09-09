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
//  · It does not call the model TO READ AN EMAIL. A parser either recognises its
//    template or it doesn't. `PurchaseClassifier` is Phase 2 and is not wired
//    here. What it now does do is ask the tagger which BUCKET a row belongs in,
//    once the reading is finished and only for rows a parser already understood
//    — a different question, answered after the fact, and answered by a lookup
//    rather than a model for every merchant you have settled before. See
//    `PurchaseTagger`; the suggestion lands on a `.pending` row and changes
//    nothing about the gate.
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
    private let exporter: any CapturedEmailSource
    /// Hand-written reference parsers.
    ///
    /// Empty in the live app as of 2026-09-09 — see `activeParsers()`. A
    /// reference parser's job is to be the ORACLE the verifier scores proposals
    /// against, not to read mail in front of the loop.
    private let parsers: [any ReceiptParser]

    /// Patterns that ship with the app, merged with whatever the loop has
    /// learned. Same artifact, same executor — see `PresetPatterns`.
    private let presets: [ExtractionPattern]
    private let provisional: ProvisionalStore
    private let log: CaptureLog
    /// Patterns the loop has learned and promoted. Nil before Stage 4 is wired.
    private let patterns: PatternStore?

    /// The second tool. Nil leaves every row untagged for the approver to
    /// settle, which is what the rail did before it existed and remains the
    /// correct behaviour for a fixture run — a suggestion is the one part of
    /// this pipeline that has no deterministic answer to assert against.
    private let tagger: (any PurchaseTagger)?

    /// What the queue has said about each learned pattern's rows. Nil leaves
    /// every unverified pattern permanently flagged, which is the behaviour
    /// before this existed and the right default for a fixture run.
    private let trust: PatternMemory?

    /// How far back a sync looks. Overlap is free — the capture log dedupes —
    /// so this is sized to survive a week of not opening the app rather than
    /// tuned to the last run.
    private let window = "newer_than:14d"
    private let fetchLimit: Int

    init(
        exporter: any CapturedEmailSource,
        parsers: [any ReceiptParser],
        provisional: ProvisionalStore,
        log: CaptureLog,
        patterns: PatternStore? = nil,
        presets: [ExtractionPattern] = [],
        tagger: (any PurchaseTagger)? = nil,
        trust: PatternMemory? = nil,
        fetchLimit: Int = 50
    ) {
        self.fetchLimit = fetchLimit
        self.exporter = exporter
        self.parsers = parsers
        self.provisional = provisional
        self.log = log
        self.patterns = patterns
        self.presets = presets
        self.tagger = tagger
        self.trust = trust
    }

    /// Patterns read the mail. Hand-written parsers, if any are passed, sit
    /// behind them.
    ///
    /// **This order was reversed on 2026-09-09, and the reversal is the point.**
    /// It used to be `handWritten + learned`, justified as protecting real
    /// accuracy from the appearance of progress — `BluReceiptParser` reads
    /// 112/112 where its synthesized equivalent scored ~97%. The justification
    /// was sound and the consequence was fatal: the caller takes the FIRST
    /// parser that claims an email, so a learned pattern never read a blu email,
    /// so the loop was shut out of the one sender it could be verified against
    /// and no evidence ever accrued. The safety argument had quietly become the
    /// reason nothing could improve.
    ///
    /// What makes agent-first safe is not a reference parser winning — it is the
    /// approval queue, which every row passes through anyway (Invariant 1). A
    /// misread amount costs a person seeing a wrong number in a queue built
    /// for exactly that. And the accuracy argument turned out to be moot: a
    /// preset reproduces the hand-written parser EXACTLY (116/116), so nothing
    /// was traded away to get here.
    ///
    /// Loaded per sync rather than at init, so a pattern promoted while the app
    /// is running is live on the next fetch.
    private func activeParsers() async -> [any ReceiptParser] {
        let learned = (try? await patterns?.active()) ?? []
        // A learned pattern outranks a preset for the same sender and layout:
        // the preset is a starting point, and something measured against real
        // mail should be able to replace it.
        let learnedKeys = Set(learned.map { [$0.senderDomain, $0.template] })
        let survivingPresets = presets.filter { !learnedKeys.contains([$0.senderDomain, $0.template]) }

        // Most specific layout first. One sender can have several patterns, and
        // one of them may carry no `bodyContains` at all — the layout that is a
        // subset of another is matched by subject alone, so it claims everything
        // from that sender if it is asked first. Sorting by how many body
        // markers a pattern requires makes "ride receipt" outrank "any blu
        // email", without either pattern needing to know the other exists.
        let specificFirst = (learned + survivingPresets)
            .sorted { $0.bodyContains.count > $1.bodyContains.count }
        return specificFirst.map(PatternDrivenParser.init(pattern:)) + parsers
    }

    struct Result: Sendable {
        var fetched = 0
        var alreadySeen = 0
        var queued = 0
        var flagged = 0
        /// Rows that look like the other rail's copy of the same purchase.
        var duplicates = 0
        /// Refunds paired with the charge they undo.
        var reversals = 0
        /// Rows that arrived with a bucket already suggested. Reported because
        /// the difference between "the tagger is off" and "the tagger had
        /// nothing to say" is otherwise invisible from the queue.
        var tagged = 0
        var notAPurchase = 0
        var skipped = 0

        var summary: String {
            if fetched == 0 { return "No new mail in the window." }
            var parts = ["\(queued) queued"]
            if tagged > 0 { parts.append("\(tagged) pre-tagged") }
            if flagged > 0 { parts.append("\(flagged) flagged") }
            if duplicates > 0 { parts.append("\(duplicates) possible duplicates") }
            if reversals > 0 { parts.append("\(reversals) reversals") }
            if skipped + notAPurchase > 0 { parts.append("\(skipped + notAPurchase) not receipts") }
            return parts.joined(separator: " · ")
        }
    }

    /// One pass. Safe to run repeatedly and concurrently-ish: anything already
    /// in the capture log is skipped before it costs a parse or a write.
    @discardableResult
    func sync() async throws -> Result {
        var result = Result()

        let parsers = await activeParsers()
        let query = ([window] + [Self.senderQuery(for: parsers)]).joined(separator: " ")
        let emails = try await exporter.fetchCaptured(query: query, limit: fetchLimit)
        result.fetched = emails.count
        guard !emails.isEmpty else { return result }

        let unseen = try await log.unseen(from: emails.map(\.id))
        result.alreadySeen = emails.count - unseen.count

        // One read for the batch: which learned patterns the queue has already
        // stood behind often enough to stop flagging.
        let vouched = await Self.vouchedPatterns(among: parsers, using: trust)

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
                let entry = Self.entry(from: receipt, email: email, parser: parser, vouched: vouched)
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
                let entry = Self.entry(from: receipt, email: email, parser: parser, vouched: vouched)
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
            entries = try await flaggingDuplicates(entries)
            result.duplicates = entries.filter { entry in
                entry.flags.contains { $0.reason == .possibleDuplicate }
            }.count

            entries = try await flaggingReversals(entries)
            result.reversals = entries.filter { entry in
                entry.flags.contains { $0.reason == .reversal }
            }.count

            // Last, after duplicates are flagged and before anything is stored.
            //
            // After, because a row about to be dropped as somebody else's copy
            // of the same purchase is not worth a model call. Before the write,
            // because a suggestion added afterwards would be a second pass over
            // the store and a window in which the queue shows a row untagged
            // and then changes it under the reader.
            if let tagger {
                entries = await tagger.tag(entries)
                result.tagged = entries.filter { $0.resolution.suggestedTag != nil }.count
            }
            try await provisional.insert(entries)
        }
        try await log.record(logEntries)

        return result
    }

    /// Learned patterns whose rows the queue has accepted often enough to stop
    /// flagging. See `PatternTrustPolicy` and `PatternMemory`.
    private static func vouchedPatterns(
        among parsers: [any ReceiptParser],
        using trust: PatternMemory?
    ) async -> Set<String> {
        guard let trust else { return [] }
        let ids = parsers.compactMap { ($0 as? PatternDrivenParser)?.pattern.id }
        guard !ids.isEmpty, let records = try? await trust.records(for: ids) else { return [] }
        let policy = PatternTrustPolicy.default
        return Set(records.filter { policy.isVouchedFor($0.value) }.keys)
    }

    // MARK: - Duplicates

    /// One purchase, two emails: the merchant sends a receipt and the bank
    /// sends a card notification, and both are true records of the same money.
    ///
    /// Measured over 137 rows from the real corpus, EVERY Grab transaction was
    /// counted twice — once by `grab.com/…` and once by `blu-receipt` as
    /// `Grab* A-9MVBRDUGW7GDAV`. Rp 718,016 of Rp 7,026,838, so spending read
    /// **10% high**. Nothing was wrong with either parser; each read its own
    /// email correctly.
    ///
    /// Matched on EXACT amount, deliberately, rather than on `Fingerprint`'s
    /// ±Rp5,000 buckets. That tolerance exists to pair a statement line with a
    /// receipt whose totals genuinely differ by a tip or a service charge. This
    /// pairing is the opposite case — the bank charges precisely what the
    /// merchant billed — so the tolerance catches nothing extra and floods the
    /// queue: measured on the same rows, bucket matching would have flagged 48
    /// of 137 against this rule's 39, all nine extra of them wrong. A flag that
    /// fires on a third of the queue trains people to approve past it.
    ///
    /// The buckets still do the searching — `candidates(matching:)` is indexed
    /// on them — and the exact test filters what comes back.
    ///
    /// Flagged, never merged. Two rows both saying Rp 44.300 on 12 Aug might be
    /// one Grab ride billed twice or two rides at the same fare, and only the
    /// person who took them knows. Invariant 6.
    private func flaggingDuplicates(_ entries: [ProvisionalEntry]) async throws -> [ProvisionalEntry] {
        var flagged = entries
        for index in flagged.indices {
            let entry = flagged[index]
            let stored = (try? await provisional.candidates(matching: entry.transaction.fingerprint)) ?? []

            // Both directions: the pair usually arrives in the SAME sync, so
            // checking only what is already stored would miss every one of them.
            let others = stored + entries.filter { $0.id != entry.id }
            guard let twin = others.first(where: { Self.isSameCharge($0, as: entry) }) else { continue }

            flagged[index].flags.append(
                ReviewFlag(
                    reason: .possibleDuplicate,
                    detail: "Same amount and day as \(Self.ruleName(of: twin))"
                )
            )
        }
        return flagged
    }

    /// Same money, within a day, seen by two different rails.
    ///
    /// The differing-source test is what keeps a genuine repeat out of it: two
    /// Rp 13.000 coffees on one day, both read by `blu-receipt`, are two
    /// coffees. The same figure arriving once from the merchant and once from
    /// the bank is one purchase.
    ///
    /// A day of slack, not none. Measured on the 137 real rows: same-day only
    /// caught 19 of Grab's 21, missing a ride whose receipt arrived on the 10th
    /// and whose card charge posted on the 9th. Widening to ±1 day caught 20
    /// and flagged exactly one more row — its twin. ±2 and ±3 caught nothing
    /// further, so the slack stops here rather than at `Fingerprint`'s ±3.
    ///
    /// The 21st has no exact twin and cannot get one: blu split that fare into
    /// Rp 5.000 and Rp 46.500 against Grab's single Rp 51.500. Matching sums of
    /// charges is a different and much harder problem, and guessing at it would
    /// merge unrelated purchases.
    private static func isSameCharge(_ lhs: ProvisionalEntry, as rhs: ProvisionalEntry) -> Bool {
        guard lhs.transaction.amount == rhs.transaction.amount,
              ruleName(of: lhs) != ruleName(of: rhs)
        else { return false }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: min(lhs.transaction.date, rhs.transaction.date)),
            to: Calendar.current.startOfDay(for: max(lhs.transaction.date, rhs.transaction.date))
        ).day ?? .max
        return days <= dateSlackDays
    }

    /// See `isSameCharge` — measured, not assumed.
    private static let dateSlackDays = 1

    // MARK: - Reversals

    /// **A refund is a dedup problem.** One purchase, two rows, arriving weeks
    /// apart instead of a day apart — so it is found the same way a duplicate
    /// is, by the same fingerprint buckets, and settled the same way: flagged
    /// for a person, never netted.
    ///
    /// Netting is what this deliberately does NOT do. A refund is `.nonSpend`
    /// and excluded from every ceiling (Invariant 5), so a Rp 42.500 purchase
    /// you were refunded still reads as Rp 42.500 of spending. Making the
    /// refund reduce that total would be a non-spend row moving a spend figure,
    /// which contradicts the invariant rather than extending it — and it would
    /// need to be certain WHICH purchase was reversed, which is exactly the
    /// judgement `possibleDuplicate` already refuses to make on its own. What
    /// the person gets instead is the pair, named: "Reverses TOKO ROTI MANIS,
    /// 12 Sep". They decide what it means.
    ///
    /// Three tests, and each one exists to stop a specific wrong pairing:
    ///
    /// · **Exact amount.** Same choice, same reason as `isSameCharge`. A
    ///   partial refund therefore does not pair, and that is the honest state:
    ///   a tolerance wide enough to catch partials is wide enough to pair a
    ///   refund with an unrelated purchase of a similar size.
    /// · **Same normalized merchant.** The one test duplicates don't use, and
    ///   here it carries the weight: two Rp 50.000 charges a fortnight apart are
    ///   common, and the merchant is what says the refund belongs to this one.
    /// · **The charge came FIRST.** A reversal cannot precede what it reverses.
    ///   Without this, two refunds in a window pair with each other.
    private func flaggingReversals(_ entries: [ProvisionalEntry]) async throws -> [ProvisionalEntry] {
        var flagged = entries
        for index in flagged.indices {
            let refund = flagged[index]
            guard refund.resolution.nonSpendType == .refund else { continue }

            // One fetch per bucket in the lookback, which is why this runs only
            // for rows already known to be refunds. Those are rare — a handful
            // of blu's 116 — and the alternative is widening `dateWindowDays`
            // for every duplicate check in the app.
            var candidates: [ProvisionalEntry.ID: ProvisionalEntry] = [:]
            for bucket in refund.transaction.fingerprint.lookingBack(days: Self.reversalWindowDays) {
                for candidate in (try? await provisional.candidates(matching: bucket)) ?? [] {
                    candidates[candidate.id] = candidate
                }
            }
            // The purchase may well be in this same batch — a fetch after two
            // weeks away brings both — so the batch is searched too.
            for candidate in entries where candidate.id != refund.id {
                candidates[candidate.id] = candidate
            }

            let charge = candidates.values
                .filter { Self.isReversed(by: refund, $0) }
                // Nearest first: if a merchant charged the same amount twice,
                // the refund almost certainly undoes the more recent one.
                .max { $0.transaction.date < $1.transaction.date }

            guard let charge else { continue }
            flagged[index].flags.append(
                ReviewFlag(
                    reason: .reversal,
                    detail: "Undoes \(charge.transaction.merchantRaw) on "
                        + charge.transaction.date.formatted(.dateTime.day().month(.abbreviated))
                )
            )
        }
        return flagged
    }

    /// Refunds are slow. blu's arrive same-week; a card reversal through an
    /// acquirer can take a fortnight, and a disputed one longer. Thirty days is
    /// wide enough to catch the ordinary case and short enough that a merchant
    /// you use monthly doesn't pair with last month's identical charge.
    ///
    /// Unmeasured, unlike `dateSlackDays` — there are 4 refunds in the corpus
    /// and none of them has its original charge in it, because the bodies were
    /// stripped before this could be looked at. Revisit on real pairs.
    private static let reversalWindowDays = 30

    private static func isReversed(by refund: ProvisionalEntry, _ candidate: ProvisionalEntry) -> Bool {
        guard candidate.resolution.kind == .spend,
              candidate.transaction.amount == refund.transaction.amount,
              MerchantID(normalizing: candidate.transaction.merchantRaw)
                  == MerchantID(normalizing: refund.transaction.merchantRaw)
        else { return false }

        let charged = candidate.transaction.date
        let refunded = refund.transaction.date
        guard charged <= refunded else { return false }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: charged),
            to: Calendar.current.startOfDay(for: refunded)
        ).day ?? .max
        return days <= reversalWindowDays
    }

    private static func ruleName(of entry: ProvisionalEntry) -> String {
        if case .rule(let id) = entry.provenance { return id.rawValue }
        return "another source"
    }

    // MARK: - Building the row

    private static func entry(
        from receipt: ParsedReceipt,
        email: CapturedEmail,
        parser: any ReceiptParser,
        vouched: Set<String>
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

        // A pattern with no verification behind it says so on every row it
        // produces. Coverage proved it fits the template's shape; nothing
        // proved it read the right number, and the approval queue is where
        // that gets decided.
        //
        // `vouched` is what makes that a ladder rather than a permanent label.
        // On a mailbox with no hand-written parser NOTHING is ever verified at
        // synthesis — `verify` has no oracle, so `verifiedAgainst` is 0 for
        // every pattern, forever — and a flag that fires on every row of every
        // sender is a flag nobody reads. Once the queue itself has vouched for
        // enough of a pattern's rows (see `PatternTrustPolicy`), it stops.
        var flags = receipt.flags
        if let learned = parser as? PatternDrivenParser,
           learned.pattern.verifiedAgainst == 0,
           !vouched.contains(learned.pattern.id) {
            flags.append(
                ReviewFlag(
                    reason: .unverifiedPattern,
                    detail: "learned from \(learned.pattern.senderDomain), never verified"
                )
            )
        }

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
            flags: flags,
            status: .pending,
            createdAt: .now,
            // Kept apart from `provenance`, which a retag overwrites. These two
            // are what let the approval queue vouch for the parser that read
            // the email — see `PatternMemory`.
            readBy: parser.id,
            readAs: receipt.kind
        )
    }

    /// `from:(a OR b)` over every parser's domain, so the fetch itself is
    /// narrow — model calls and bandwidth are never spent on LinkedIn.
    ///
    /// Takes the ACTIVE parser list, not the hand-written one: a promoted
    /// pattern that isn't in this query would never be sent an email to parse,
    /// and the loop would look like it had learned nothing.
    private static func senderQuery(for parsers: [any ReceiptParser]) -> String {
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
