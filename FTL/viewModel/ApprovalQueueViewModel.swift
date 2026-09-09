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

import Foundation
import Observation

@Observable @MainActor
final class ApprovalQueueViewModel {
    private let store: ProvisionalStore
    private let approvals: ApprovalService
    private let ledger: LedgerStore
    /// Re-run on every load, deterministically. See `load()`.
    private let tagger: (any PurchaseTagger)?

    private(set) var phase: LoadPhase = .idle
    private(set) var entries: [ProvisionalEntry] = []
    private(set) var categories: [SpendCategory] = []

    /// Called after a row leaves the queue, so whatever is behind this sheet can
    /// catch up. Approving changes the hero total, a bucket's position against
    /// its ceiling, and the queue count on Home — all of which used to sit stale
    /// until the sheet was dismissed.
    var onSettled: (() -> Void)?

    init(
        store: ProvisionalStore,
        approvals: ApprovalService,
        ledger: LedgerStore,
        tagger: (any PurchaseTagger)? = nil
    ) {
        self.store = store
        self.approvals = approvals
        self.ledger = ledger
        self.tagger = tagger
    }

    // MARK: - Derived

    /// Flagged rows first — they are the ones that actually need a person.
    var sorted: [ProvisionalEntry] {
        entries.sorted { lhs, rhs in
            if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var isEmpty: Bool { entries.isEmpty }

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

            entries = pending
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
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
        do {
            try await approvals.reject([entry.id])
            await load()
            onSettled?()
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
