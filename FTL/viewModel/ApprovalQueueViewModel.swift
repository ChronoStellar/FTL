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

    private(set) var phase: LoadPhase = .idle
    private(set) var entries: [ProvisionalEntry] = []
    private(set) var categories: [SpendCategory] = []

    init(store: ProvisionalStore, approvals: ApprovalService, ledger: LedgerStore) {
        self.store = store
        self.approvals = approvals
        self.ledger = ledger
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
    var modelTaggedCount: Int { entries.filter { $0.provenance.isModel }.count }

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

    // MARK: - Actions

    func load() async {
        if case .idle = phase { phase = .loading }
        do {
            entries = try await store.pending()
            categories = try await ledger.categories()
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

    func approve(_ entry: ProvisionalEntry) async {
        do {
            let result = try await approvals.approve([entry.id])
            await load()
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
