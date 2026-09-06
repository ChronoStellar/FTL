//
//  ProvisionalStore.swift
//  FTL — model/Contracts · Phase 1
//
//  The on-device cache. Invariant 7: nothing in here is canonical. This is where
//  the model is allowed to be wrong, and where the user catches it.
//
//  Implementation: services/Persistence/GRDBProvisionalStore
//

import Foundation

nonisolated protocol ProvisionalStore: Sendable {
    func insert(_ entries: [ProvisionalEntry]) async throws

    /// Everything awaiting the human gate, newest first.
    func pending() async throws -> [ProvisionalEntry]

    func entries(withStatus status: ProvisionalEntry.Status) async throws -> [ProvisionalEntry]

    /// Dedup candidates: entries in this fingerprint's bucket and its neighbours.
    /// Used to build `RuleContext`, never to conclude a match on its own.
    func candidates(matching fingerprint: Fingerprint) async throws -> [ProvisionalEntry]

    /// Has this rail document already been captured? Keeps re-running a rail cheap
    /// and idempotent.
    func hasDocument(externalID: String, source: CaptureSource) async throws -> Bool

    func update(_ entry: ProvisionalEntry) async throws

    /// Called by ApprovalService only, after the ledger write succeeds. Ordering
    /// matters: mark promoted after the append is confirmed, so a crash re-tries a
    /// write the ledger will dedup by `id` rather than losing the row entirely.
    func markPromoted(_ ids: [ProvisionalEntry.ID]) async throws

    func loadCursor(for source: CaptureSource) async throws -> CaptureCursor?
    func saveCursor(_ cursor: CaptureCursor) async throws
}
