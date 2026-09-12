//
//  ApprovalQueueViewModel.swift
//  FTL — viewModel · Phase 1
//
//  The human gate. Everything the pipeline produced waits here, and approving is
//  the only route into the canonical ledger (Invariant 1).
//
//  Per-row rather than multi-select: each card carries its own tag chips, a Drop
//  and an Approve. The design settles one row at a time because retagging is the
//  common case, and a batch approve would quietly rubber-stamp the model's guess
//  on rows the user never actually looked at.
//
//  `approveAll` is the one exception, and it is scoped narrowly on purpose —
//  see `bulkApprovable`. It exists for the ordinary case (a bucket you already
//  chose, or a merchant memory has settled) rather than for waving through
//  whatever the model just guessed at for a sender with no history behind it.
//

import Foundation
import Observation

@Observable @MainActor
final class ApprovalQueueViewModel {
    private let store: ProvisionalStore
    private let approvals: ApprovalService
    private let ledger: LedgerStore
    /// Re-run on every load, deterministically. See `load()`.
    private let tagger: (any PurchaseTagger)?
    /// Re-checked on every load, same reasoning as `tagger` — see
    /// `reviseUnverifiedFlags`.
    private let trust: (any PatternMemory)?

    private(set) var phase: LoadPhase = .idle
    private(set) var entries: [ProvisionalEntry] = []
    private(set) var categories: [SpendCategory] = []
    private(set) var settlingIDs: Set<ProvisionalEntry.ID> = []

    func isSettling(_ id: ProvisionalEntry.ID) -> Bool {
        settlingIDs.contains(id)
    }

    /// User-chosen, this screen only — not persisted. `needsAttention` always
    /// wins first regardless of this choice; flagged rows are not something a
    /// sort preference should be able to bury.
    var sortOption: SortOption = .oldestFirst

    nonisolated enum SortOption: String, CaseIterable, Identifiable, Equatable {
        case oldestFirst
        case newestFirst
        case amountHighToLow
        case amountLowToHigh

        var id: String { rawValue }

        var label: String {
            switch self {
            case .oldestFirst: return "Oldest first"
            case .newestFirst: return "Newest first"
            case .amountHighToLow: return "Largest amount"
            case .amountLowToHigh: return "Smallest amount"
            }
        }
    }

    /// Called after a row leaves the queue, so whatever is behind this sheet can
    /// catch up. Approving changes the hero total, a bucket's position against
    /// its ceiling, and the queue count on Home — all of which used to sit stale
    /// until the sheet was dismissed.
    var onSettled: (() -> Void)?

    init(
        store: ProvisionalStore,
        approvals: ApprovalService,
        ledger: LedgerStore,
        tagger: (any PurchaseTagger)? = nil,
        trust: (any PatternMemory)? = nil
    ) {
        self.store = store
        self.approvals = approvals
        self.ledger = ledger
        self.tagger = tagger
        self.trust = trust
    }

    // MARK: - Derived

    /// Flagged rows first — they are the ones that actually need a person.
    /// Within a group, OLDEST transaction first.
    ///
    /// It used to be newest CAPTURED first (`createdAt`), which is when a row
    /// entered the queue rather than when the purchase happened — and on a
    /// big first sync those two disagree badly. `DefaultPurchaseTagger`'s
    /// model-call budget only reaches a handful of merchants per batch, and
    /// capture order tends to be newest-mail-first, so the tagged rows and
    /// the untagged ones clumped by fetch recency rather than interleaving:
    /// a screenful of blank chips with a few tagged rows buried under them
    /// read as "the tagger did nothing", when it had actually done exactly
    /// what its budget allowed. Sorting by the transaction's own date instead
    /// spreads tagged and untagged rows through the list in the order a
    /// person actually recognises their spending, which is what the date on
    /// each card (see `ApprovalQueueSheet`) is for.
    ///
    /// `sortOption` only ever decides the tie-break within a group — flagged
    /// rows still come first no matter which one is picked. A sort preference
    /// choosing to bury the rows that actually need a person would defeat the
    /// point of flagging them at all.
    var sorted: [ProvisionalEntry] {
        entries.sorted { lhs, rhs in
            if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
            switch sortOption {
            case .oldestFirst: return lhs.transaction.date < rhs.transaction.date
            case .newestFirst: return lhs.transaction.date > rhs.transaction.date
            case .amountHighToLow: return lhs.transaction.amount.minorUnits > rhs.transaction.amount.minorUnits
            case .amountLowToHigh: return lhs.transaction.amount.minorUnits < rhs.transaction.amount.minorUnits
            }
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Safe for `approveAll`: not flagged, has a real bucket selected, and —
    /// when that bucket is only a SUGGESTION nobody has confirmed yet — the
    /// suggestion is grounded in your own past decisions (`.memory`) rather
    /// than a fresh model guess with no history behind it.
    ///
    /// Invariant 10's whole point is that trust is earned per merchant from
    /// your approvals, not from the model's confidence in itself; a bulk
    /// action is exactly the place that has to be enforced rather than
    /// assumed. A memory-backed suggestion is different: it is just your own
    /// established pattern for that merchant repeated back to you, which is
    /// what approving it individually would do anyway.
    var bulkApprovable: [ProvisionalEntry] {
        sorted.filter { entry in
            guard !entry.needsAttention, selectedTag(for: entry).id != nil else { return false }
            guard suggestionNote(for: entry) != nil else { return true }
            if case .model = entry.resolution.suggestedTag?.basis { return false }
            return true
        }
    }

    var bulkApprovableTotal: Money {
        Money.sum(bulkApprovable.map(\.transaction.amount))
    }

    /// The tag options on each card: every bucket, plus the escape hatch. A
    /// transfer or top-up is not spending, and the user needs to say so without
    /// deleting the row (Invariant 5).
    func tagOptions() -> [TagOption] {
        categories.map { TagOption(id: $0.id, name: $0.name) }
            + [TagOption(id: nil, name: "Not a spend")]
    }

    func selectedTag(for entry: ProvisionalEntry) -> TagOption {
        guard entry.resolution.kind == .spend else { return TagOption(id: nil, name: "Not a spend") }
        guard let id = entry.resolution.categoryID,
              let match = categories.first(where: { $0.id == id })
        else { return TagOption(id: nil, name: "Not a spend") }
        return TagOption(id: match.id, name: match.name)
    }

    func approveLabel(for entry: ProvisionalEntry) -> String {
        let tag = selectedTag(for: entry)
        return tag.id == nil ? "Approve · excluded" : "Approve to \(tag.name)"
    }

    /// Where the pre-selected bucket came from, or nil when nothing suggested
    /// one and the selection is just the default.
    ///
    /// A suggestion a person cannot tell apart from a decision is worse than no
    /// suggestion: they approve it believing they chose it, the app records
    /// agreement, and the hit rate measures its own output. This line is what
    /// keeps the approval an actual decision — and the counts are deliberately
    /// concrete, because "seen 4 times, 4 to Groceries" is checkable in a way
    /// that "high confidence" is not (Invariant 10).
    ///
    /// Silent once a person has retagged: `amend` sets provenance to `.manual`,
    /// and at that point the bucket on screen is theirs, not a proposal.
    func suggestionNote(for entry: ProvisionalEntry) -> String? {
        guard case .manual = entry.provenance else { return note(for: entry) }
        return nil
    }

    private func note(for entry: ProvisionalEntry) -> String? {
        guard let suggested = entry.resolution.suggestedTag else { return nil }
        // A bucket deleted from the sheet since the suggestion was made. The
        // row is still fine — the chip falls back to "Not a spend" like any
        // untagged row — but naming a bucket that no longer exists would be
        // worse than saying nothing.
        guard let bucket = categories.first(where: { $0.id == suggested.categoryID })?.name else {
            return nil
        }

        switch suggested.basis {
        case .memory(let agreed, let total):
            return "🧠 Memory: Suggested \(bucket) — you chose it \(agreed) of the last \(total) times here"
        case .model:
            return "🤖 Agent: Suggested \(bucket) — proposed by on-device model (new merchant)"
        }
    }

    // MARK: - Actions

    /// Reads the queue, then re-derives the tagger's memory half against what
    /// you have decided by now.
    ///
    /// The refresh is here, on the READ, and that is the fix for the flow the
    /// first version got wrong. Tagging used to happen once at capture, so a
    /// sync of five rows from one merchant looked up what was known before you
    /// had settled any of them — and settling the first taught the other four
    /// nothing until the next fetch. Rows already waiting from a previous sync
    /// never got a suggestion at all.
    ///
    /// Costs nothing extra to run: `categories()` is already being read for the
    /// chips, and the refresh is a lookup with no model in it. It writes only
    /// the rows whose suggestion actually changed.
    func load() async {
        if case .idle = phase { phase = .loading }
        do {
            var pending = try await store.pending()
            categories = try await ledger.categories()
            let existingLedger = (try? await ledger.all()) ?? []

            // Auto-settle any pending rows that have already been recorded in canonical ledger
            //
            // These leave the queue without anyone seeing them, so each one
            // says why and names the row it matched — a wrong match here takes
            // real spending out of the queue silently, and the log is the only
            // way back to it. See `LedgerDeduplicator` for the measurement
            // behind the rule, including the one case it cannot resolve.
            var alreadySettledIDs: [ProvisionalEntry.ID] = []
            pending.removeAll { entry in
                guard let twin = existingLedger.first(where: { LedgerDeduplicator.isDuplicate(entry, as: $0) })
                else { return false }
                PipelineDebugStub.recordSettlement(
                    entryID: entry.id,
                    merchant: entry.transaction.merchantRaw,
                    parserOrigin: entry.readBy?.origin,
                    verdict: "auto-settled at queue load: already in ledger as \(twin.id) "
                        + "(\(twin.merchantRaw), \(twin.date.formatted(.dateTime.day().month(.abbreviated))))"
                )
                alreadySettledIDs.append(entry.id)
                return true
            }
            if !alreadySettledIDs.isEmpty {
                try? await store.markPromoted(alreadySettledIDs)
            }

            if let tagger {
                let changed = await tagger.refresh(pending, among: categories)
                for entry in changed {
                    // Best-effort, per row. A failed write means one row shows
                    // its old suggestion next time, which is the state it was
                    // already in — not a reason to fail opening the queue.
                    try? await store.update(entry)
                }
                let updates = Dictionary(changed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                pending = pending.map { updates[$0.id] ?? $0 }
            }

            pending = await reviseUnverifiedFlags(in: pending)

            entries = pending
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Clears `unverifiedPattern` from a row whose pattern has, since
    /// capture, earned the trust `PatternTrustPolicy` requires.
    ///
    /// Same lesson `tagger.refresh` above already applies to suggestions,
    /// applied here to the flag instead: `GmailRail` stamps
    /// `unverifiedPattern` once, at capture, based on whether the pattern
    /// was vouched THEN — but vouching is a live, reversible number
    /// (Invariant 10), and a row that has been sitting in the queue since
    /// before its pattern crossed `PatternTrustPolicy`'s bar has no way to
    /// find that out on its own. Freezing it there is the same shape of bug
    /// as the tagger's first version, just in a different field.
    ///
    /// One direction only, deliberately: a pattern's trust DROPPING again
    /// does not re-flag an already-pending row here. That needs the full
    /// `ExtractionPattern` (to confirm `verifiedAgainst == 0` still holds,
    /// same condition `GmailRail` checks at capture) rather than just its
    /// id, and re-flagging a row someone may already be looking at is a
    /// different judgment call than quietly clearing a stale caution. Left
    /// as a follow-up rather than done by half.
    private func reviseUnverifiedFlags(in pending: [ProvisionalEntry]) async -> [ProvisionalEntry] {
        guard let trust else { return pending }

        let flaggedPatternIDs = Set(
            pending
                .filter { $0.flags.contains { $0.reason == .unverifiedPattern } }
                .compactMap { $0.readBy?.rawValue }
        )
        guard !flaggedPatternIDs.isEmpty else { return pending }

        let vouched = await PatternTrustPolicy.vouched(among: Array(flaggedPatternIDs), using: trust)
        guard !vouched.isEmpty else { return pending }

        var revised: [ProvisionalEntry] = []
        revised.reserveCapacity(pending.count)
        for var entry in pending {
            guard let patternID = entry.readBy?.rawValue,
                  vouched.contains(patternID),
                  entry.flags.contains(where: { $0.reason == .unverifiedPattern })
            else {
                revised.append(entry)
                continue
            }
            entry.flags.removeAll { $0.reason == .unverifiedPattern }
            // Best-effort, same reasoning as the tagger's refresh above: a
            // failed write leaves the row exactly as flagged as it already
            // was — not a reason to fail opening the queue.
            try? await store.update(entry)
            revised.append(entry)
        }
        return revised
    }

    func retag(_ entry: ProvisionalEntry, to option: TagOption) async {
        var resolution = entry.resolution
        if let id = option.id {
            resolution.kind = .spend
            resolution.categoryID = id
            resolution.nonSpendType = nil
        } else {
            // Labelled, kept, excluded from totals — never deleted.
            resolution.kind = .nonSpend
            resolution.categoryID = nil
        }
        do {
            try await approvals.amend(entry.id, to: resolution)
            await load()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Approving reloads, and the reload is what teaches the rest of the queue.
    ///
    /// `load()` re-runs the tagger's memory half, so the second row from a
    /// merchant you just settled comes back pre-tagged — the sequential
    /// accrual the design describes, actually happening within one sitting
    /// rather than at the next fetch.
    func approve(_ entry: ProvisionalEntry) async {
        guard !settlingIDs.contains(entry.id) else { return }
        settlingIDs.insert(entry.id)
        defer { settlingIDs.remove(entry.id) }

        do {
            let result = try await approvals.approve([entry.id])
            await load()
            onSettled?()
            if let failure = result.failed.first {
                phase = .failed(failure.error)
            }
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    func drop(_ entry: ProvisionalEntry) async {
        guard !settlingIDs.contains(entry.id) else { return }
        settlingIDs.insert(entry.id)
        defer { settlingIDs.remove(entry.id) }

        do {
            try await approvals.reject([entry.id])
            await load()
            onSettled?()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Everything `bulkApprovable` allows, in one write. `ApprovalService`
    /// already reports partial failure per row (Invariant 1's contract, not
    /// something added for this) — one bad row does not strand the rest.
    ///
    /// Scoping is `bulkApprovable`'s job, not this method's: by the time this
    /// runs, every id it is given is either a bucket you already chose or a
    /// suggestion your own history backs up. A flagged row or a fresh model
    /// guess never reaches here.
    func approveAll() async {
        let ids = bulkApprovable.map(\.id)
        guard !ids.isEmpty else { return }
        let newIDs = ids.filter { !settlingIDs.contains($0) }
        guard !newIDs.isEmpty else { return }
        for id in newIDs { settlingIDs.insert(id) }
        defer { for id in newIDs { settlingIDs.remove(id) } }

        do {
            let result = try await approvals.approve(newIDs)
            await load()
            onSettled?()
            if !result.failed.isEmpty {
                phase = .failed("\(result.failed.count) of \(newIDs.count) didn't go through — the rest are approved.")
            }
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    struct TagOption: Identifiable, Hashable {
        /// Nil means "Not a spend".
        let id: CategoryID?
        let name: String
    }
}
