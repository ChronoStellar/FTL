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

    init(store: ProvisionalStore, ledger: LedgerStore) {
        self.store = store
        self.ledger = ledger
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
        return ApprovalResult(written: written, failed: [])
    }

    func reject(_ ids: [ProvisionalEntry.ID]) async throws {
        for id in ids {
            guard var entry = try await store.entries(withStatus: .pending).first(where: { $0.id == id }) else { continue }
            entry.status = .rejected  // kept, never deleted — this is the accuracy record
            try await store.update(entry)
        }
    }

    func amend(_ id: ProvisionalEntry.ID, to resolution: ProvisionalEntry.Resolution) async throws {
        guard var entry = try await store.entries(withStatus: .pending).first(where: { $0.id == id }) else { return }
        entry.resolution = resolution
        entry.provenance = .manual  // a corrected row is no longer the model's verdict
        try await store.update(entry)
    }
}
