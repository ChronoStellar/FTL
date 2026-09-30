//
//  DefaultApprovalService.swift
//  FTL — services/Ledger
//
//  The human gate, and Invariant 1: the only path from the provisional cache into
//  the canonical ledger. No rail, no rule, and above all no model writes to
//  LedgerStore.
//

import Foundation

/// The single write path (Invariant 1). Note the ordering: append to the ledger
/// first, mark promoted only once that succeeded. A crash between the two costs a
/// retry the ledger dedups by `id`; the reverse order would lose the row.
actor DefaultApprovalService: ApprovalService {
    private let store: ProvisionalStore
    private let ledger: LedgerStore
    /// Where the tagger's accuracy accrues. Nil in `sample()`; a nil memory
    /// changes nothing except that nothing is learned.
    private let tags: TagMemory?
    /// Where the LOOP's accuracy accrues, and on an unseen mailbox the only
    /// oracle it has. See `PatternMemory`.
    private let patterns: PatternMemory?
    /// What you call each shop, so a rename outlives the row it was typed on.
    private let merchants: MerchantMemory?

    init(
        store: ProvisionalStore,
        ledger: LedgerStore,
        tags: TagMemory? = nil,
        patterns: PatternMemory? = nil,
        merchants: MerchantMemory? = nil
    ) {
        self.store = store
        self.ledger = ledger
        self.tags = tags
        self.patterns = patterns
        self.merchants = merchants
    }

    func approve(_ ids: [ProvisionalEntry.ID]) async throws -> ApprovalResult {
        let pending = try await store.pending().filter { ids.contains($0.id) }
        let existingLedger = try await ledger.all()
        var toAppend: [LedgerTransaction] = []
        var written: [LedgerTransaction] = []

        for entry in pending {
            let tx = LedgerTransaction(
                id: entry.id,
                date: entry.transaction.date,
                amount: entry.transaction.amount,
                merchantRaw: entry.transaction.merchantRaw,
                merchant: Self.displayMerchant(for: entry),
                categoryID: entry.resolution.categoryID,
                kind: entry.resolution.kind,
                nonSpendType: entry.resolution.nonSpendType,
                source: entry.transaction.source,
                sourcesMerged: entry.resolution.mergedFrom,
                splits: entry.resolution.splits,
                lineItems: entry.transaction.lineItems,
                provenance: entry.provenance,
                flags: entry.flags,
                capturedAt: entry.createdAt,
                approvedAt: .now,
                notes: entry.notes
            )
            written.append(tx)

            // Auto-dropped rather than flagged, deliberately — but never
            // without a record. A dropped row is still marked promoted below,
            // so the only thing separating "this was its twin" from "captured
            // spending vanished" is this line. See `LedgerDeduplicator` for
            // what the rule can and cannot tell apart.
            if let twin = existingLedger.first(where: { LedgerDeduplicator.isDuplicate($0, tx) }) {
                PipelineDebugStub.recordSettlement(
                    entryID: entry.id,
                    merchant: entry.transaction.merchantRaw,
                    parserOrigin: entry.readBy?.origin,
                    verdict: "auto-dropped: duplicate of ledger row \(twin.id) "
                        + "(\(twin.merchantRaw), \(twin.date.formatted(.dateTime.day().month(.abbreviated))))"
                )
                continue
            }
            // Deduplicate against twins in the same approval batch
            if let twin = toAppend.first(where: { LedgerDeduplicator.isDuplicate($0, tx) }) {
                PipelineDebugStub.recordSettlement(
                    entryID: entry.id,
                    merchant: entry.transaction.merchantRaw,
                    parserOrigin: entry.readBy?.origin,
                    verdict: "auto-dropped: duplicate of \(twin.merchantRaw) in this same approval batch"
                )
                continue
            }
            toAppend.append(tx)
        }

        if !toAppend.isEmpty {
            try await ledger.append(toAppend)
        }
        try await store.markPromoted(written.map(\.id))
        await recordDecisions(from: pending)
        await observePatterns(pending) { Self.verdict(for: $0) }
        for entry in pending {
            let v = Self.verdict(for: entry).rawValue
            PipelineDebugStub.recordSettlement(
                entryID: entry.id,
                merchant: entry.transaction.merchantRaw,
                parserOrigin: entry.readBy?.origin,
                verdict: v
            )
        }
        return ApprovalResult(written: written, failed: [])
    }

    func reject(_ ids: [ProvisionalEntry.ID]) async throws {
        var rejected: [ProvisionalEntry] = []
        for id in ids {
            guard var entry = try await store.entries(withStatus: .pending).first(where: { $0.id == id }) else { continue }
            entry.status = .rejected  // kept, never deleted — this is the accuracy record
            try await store.update(entry)
            rejected.append(entry)
        }
        await observePatterns(rejected) { _ in .dropped }
        for entry in rejected {
            PipelineDebugStub.recordSettlement(
                entryID: entry.id,
                merchant: entry.transaction.merchantRaw,
                parserOrigin: entry.readBy?.origin,
                verdict: "dropped"
            )
        }
    }

    /// What an approved row says about the pattern that read the email.
    ///
    /// Both tests compare against what was READ, not against what the row now
    /// says — a verdict about how the email was parsed, unlike a category
    /// change, which is a verdict about a budget and belongs to the other tool.
    ///
    /// A corrected name only counts against the PATTERN when it changes which
    /// shop the row is about.
    ///
    /// `MerchantID(normalizing:)` already folds case, punctuation and the
    /// trailing payment reference, so `GRAB* A-9MVBRDUGW7GDAV` → `Grab` keys to
    /// the same merchant either way: the pattern found the right string and a
    /// person tidied it. Cosmetic, not a miss. Renaming a row the pattern read
    /// as `Total Belanja` to `Hokky Supermarket` keys somewhere else entirely —
    /// it grabbed a label instead of a shop, and that is a miss.
    ///
    /// Without this split `MerchantMemory` would be self-defeating: it fills the
    /// name in on every future row from that shop, and every one of those would
    /// then score as a fresh failure for a pattern nobody had to correct —
    /// pinning its acceptance rate at zero forever.
    ///
    /// Known imprecision: adding detail the email never carried — `INDOMARET` →
    /// `Indomaret Kemang` — keys differently and so reads as a miss. Harsh, and
    /// the right side to err on, because the app cannot tell "you grabbed the
    /// wrong string" from "the string was incomplete".
    static func merchantWasMisread(_ entry: ProvisionalEntry) -> Bool {
        guard let corrected = entry.resolution.merchantName else { return false }
        return MerchantID(normalizing: corrected) != MerchantID(normalizing: entry.transaction.merchantRaw)
    }

    /// Ordered worst-first, and the order is a claim about the pattern:
    ///
    /// 1. `correctedAmount` — it could not find the number, which is the one
    ///    thing the email states outright and nothing else can excuse.
    /// 2. `correctedMerchant` — it found the number and put the wrong name on
    ///    it. Bad, and recoverable by eye in a way a wrong figure is not.
    /// 3. `correctedKind` — direction is inferred rather than stated, so this
    ///    is the miss with the best excuse.
    ///
    /// Every test compares against what was READ, by VALUE, so correcting a row
    /// and then correcting it back is not counted as a miss — because it isn't
    /// one.
    static func verdict(for entry: ProvisionalEntry) -> PatternObservation.Verdict {
        if let read = entry.readAmount, read != entry.transaction.amount { return .correctedAmount }
        if merchantWasMisread(entry) { return .correctedMerchant }
        if entry.resolution.kind != (entry.readAs ?? entry.resolution.kind) { return .correctedKind }
        return .accepted
    }

    /// Attributes a settled row to the learned pattern that produced it.
    ///
    /// Only learned patterns. Queue evidence about `blu-receipt` is evidence
    /// about somebody's Swift, not about anything the loop did, and mixing the
    /// two would let a hand-written parser's rows inflate the number the loop
    /// is judged on — see `ExtractionPattern.namesPattern`.
    ///
    /// Best-effort and after the fact, for the same reason `recordDecisions` is:
    /// a memory write that fails must never fail an approval that already
    /// reached the sheet.
    private func observePatterns(
        _ entries: [ProvisionalEntry],
        verdict: (ProvisionalEntry) -> PatternObservation.Verdict
    ) async {
        guard let patterns, !entries.isEmpty else { return }
        let observations = entries.compactMap { entry -> PatternObservation? in
            guard let readBy = entry.readBy, ExtractionPattern.namesPattern(readBy) else { return nil }
            return PatternObservation(
                id: entry.id,
                patternID: readBy.rawValue,
                verdict: verdict(entry),
                settledAt: .now
            )
        }
        guard !observations.isEmpty else { return }
        try? await patterns.record(observations)
    }

    /// The gate is the right place for this and the only one.
    ///
    /// Every promotion passes through here, exactly once, by Invariant 1 — so a
    /// decision recorded here is recorded for every route into the ledger with
    /// no second call site to keep in step. Recording it in the queue's view
    /// model instead would miss anything approved from an intent, and recording
    /// it in the rail would count a suggestion nobody had looked at yet.
    ///
    /// AFTER the ledger write, deliberately. The record says "this is what you
    /// decided", and until the append succeeds you have not decided anything
    /// that survived. Best-effort for the same reason: a memory write that
    /// fails must not fail an approval that already reached the sheet, because
    /// the row would then be promoted, unmarked, and offered again.
    ///
    /// Only approvals. A dropped row is not a tagging decision — you rejected
    /// the transaction, not the bucket — and scoring the tagger on rows that
    /// never became spending would measure the parser's mistakes as the
    /// tagger's.
    ///
    /// A useful consequence of putting this at the gate rather than in the
    /// queue: `ManualEntry` promotes through here too, so every spend you type
    /// in by hand seeds the merchant memory with a decision that had no
    /// suggestion to be right or wrong about. The tagger therefore starts
    /// knowing your regular shops before it has ever suggested anything, and
    /// those rows do not touch the hit rate.
    private func recordDecisions(from entries: [ProvisionalEntry]) async {
        guard let tags, !entries.isEmpty else { return }
        let decisions = entries.map { entry in
            TagDecision(
                id: entry.id,
                key: TagKey(
                    merchant: MerchantID(normalizing: entry.transaction.merchantRaw),
                    // `readBy`, not `provenance` — stable across a retag, and
                    // the same choice `TagContext.layout` makes, for the same
                    // reason: the accrual key must describe what actually
                    // produced this row, not whatever it was last corrected to.
                    // `templateIdentity(of:)`, not the raw RuleID, for the
                    // same reason too — strips the trailing `:version` so a
                    // pattern re-promoted to a better attempt doesn't orphan
                    // everything accrued under the old one. Must match
                    // `TagContext.layout` exactly, or the write and read
                    // sides of this key would silently disagree.
                    layout: entry.readBy.map(ExtractionPattern.templateIdentity(of:))
                ),
                merchantRaw: entry.transaction.merchantRaw,
                suggested: entry.resolution.suggestedTag,
                chosen: entry.resolution.categoryID,
                chosenKind: entry.resolution.kind,
                decidedAt: .now
            )
        }
        try? await tags.record(decisions)
    }

    /// What the ledger row's `merchant` column gets: the corrected name if
    /// somebody typed one, otherwise the parser's reading of the raw string.
    ///
    /// One definition, used by promotion above and by `verdict` below, so "was
    /// the name corrected" and "what name gets written" can never disagree.
    static func displayMerchant(for entry: ProvisionalEntry) -> String {
        entry.resolution.merchantName ?? parsedMerchant(for: entry)
    }

    /// The name the pipeline produced with nobody's help.
    static func parsedMerchant(for entry: ProvisionalEntry) -> String {
        entry.transaction.merchantRaw.capitalized
    }

    func correctMerchant(_ id: ProvisionalEntry.ID, to name: String?) async throws {
        guard var entry = try await store.entries(withStatus: .pending).first(where: { $0.id == id }) else { return }

        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty, or the same string the parser already produced, is not a
        // correction — storing it would record a miss nobody made and would
        // leave the row permanently looking edited.
        let corrected = (trimmed?.isEmpty == false && trimmed != Self.parsedMerchant(for: entry)) ? trimmed : nil
        guard corrected != entry.resolution.merchantName else { return }

        entry.resolution.merchantName = corrected
        entry.provenance = .manual

        try await store.update(entry)

        // The point of the whole exercise: say it once. Keyed on the normalized
        // merchant, so the next receipt from this shop — with a different
        // booking reference glued on, as every one of them has — arrives
        // already named. Best-effort: a memory write that fails must not fail
        // the correction the person is looking at.
        let merchant = MerchantID(normalizing: entry.transaction.merchantRaw)
        if let corrected {
            try? await merchants?.remember(corrected, for: merchant)
        } else {
            // Cleared the override — "actually, the raw was fine". Leaving the
            // old name remembered would put it straight back.
            try? await merchants?.forget(merchant)
        }
    }

    func correctAmount(_ id: ProvisionalEntry.ID, to amount: Money) async throws {
        guard var entry = try await store.entries(withStatus: .pending).first(where: { $0.id == id }) else { return }
        guard amount != entry.transaction.amount else { return }

        // Stamped once, on the FIRST correction, so the record is what the
        // parser read rather than whatever the previous edit left behind. A
        // second correction back to the original then reads as untouched,
        // which is the truth about the parser even though two edits happened.
        if entry.readAmount == nil { entry.readAmount = entry.transaction.amount }

        entry.transaction.amount = amount
        // The fingerprint is f(amount, date) — the blocking key dedup and
        // refund pairing both search on. Leaving it stale would keep this row
        // filed under a figure it no longer has, so the duplicate it was
        // supposed to collide with never turns up in the same bucket.
        entry.transaction.fingerprint = Fingerprint(amount: amount, date: entry.transaction.date)

        // Both of these flags assert a COMPARISON — "same amount and merchant as
        // <row>" — and the amount they compared just changed. Left on, the card
        // goes on naming a twin it no longer matches, which is worse than no
        // flag: it is a specific claim that is now false, sitting on the row a
        // person is about to approve.
        //
        // Dropping them does not lose the check. `approve` still tests every row
        // against the ledger and against its own batch with `LedgerDeduplicator`
        // before anything is written, and the next sync re-flags from scratch.
        entry.flags.removeAll { $0.reason == .possibleDuplicate || $0.reason == .reversal }

        entry.provenance = .manual  // a corrected row is no longer the pipeline's verdict

        try await store.update(entry)
    }

    func amend(_ id: ProvisionalEntry.ID, to resolution: ProvisionalEntry.Resolution) async throws {
        guard var entry = try await store.entries(withStatus: .pending).first(where: { $0.id == id }) else { return }
        let suggestion = entry.resolution.suggestedTag
        entry.resolution = resolution
        // A retag is the most valuable event the tagger has — it is the only
        // place the app finds out it was wrong — so what was SUGGESTED survives
        // being corrected. A caller that builds a fresh resolution rather than
        // editing the existing one would otherwise erase the miss and leave the
        // hit rate measuring only the rows nobody had to fix.
        entry.resolution.suggestedTag = resolution.suggestedTag ?? suggestion
        entry.provenance = .manual  // a corrected row is no longer the model's verdict
        try await store.update(entry)
    }
}
