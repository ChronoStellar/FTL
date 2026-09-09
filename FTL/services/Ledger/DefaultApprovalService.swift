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

    init(
        store: ProvisionalStore,
        ledger: LedgerStore,
        tags: TagMemory? = nil,
        patterns: PatternMemory? = nil
    ) {
        self.store = store
        self.ledger = ledger
        self.tags = tags
        self.patterns = patterns
    }

    func approve(_ ids: [ProvisionalEntry.ID]) async throws -> ApprovalResult {
        let pending = try await store.pending().filter { ids.contains($0.id) }
        let written = pending.map { entry in
            LedgerTransaction(
                id: entry.id,
                date: entry.transaction.date,
                amount: entry.transaction.amount,
                merchantRaw: entry.transaction.merchantRaw,
                merchant: entry.transaction.merchantRaw.capitalized,
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
                notes: nil
            )
        }
        try await ledger.append(written)
        try await store.markPromoted(written.map(\.id))
        await recordDecisions(from: pending)
        await observePatterns(pending) { entry in
            // The parser's reading survived, or the person flipped the
            // direction on the way through. Either is a verdict about how the
            // email was READ — unlike a category change, which is a verdict
            // about a budget and belongs to the other tool.
            entry.resolution.kind == (entry.readAs ?? entry.resolution.kind)
                ? .accepted
                : .correctedKind
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
                merchant: MerchantID(normalizing: entry.transaction.merchantRaw),
                merchantRaw: entry.transaction.merchantRaw,
                suggested: entry.resolution.suggestedTag,
                chosen: entry.resolution.categoryID,
                chosenKind: entry.resolution.kind,
                decidedAt: .now
            )
        }
        try? await tags.record(decisions)
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
