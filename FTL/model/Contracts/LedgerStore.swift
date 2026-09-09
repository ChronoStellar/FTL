//
//  LedgerStore.swift
//  FTL — model/Contracts · Phase 1
//
//  The canonical store — Google Sheets. Written through ApprovalService alone.
//
//  Implementation: services/Ledger/SheetsLedgerStore
//

import Foundation

/// Just the bucket list.
///
/// Split out so a collaborator that only needs to know what the buckets ARE
/// doesn't have to be handed the whole ledger — `DefaultPurchaseTagger` needs
/// the taxonomy and has no business being able to append a transaction. Same
/// idea as `DomainScopedParser`: the narrowest thing that says what a caller
/// actually depends on.
///
/// The sheet is canonical (Stage 0.5): whatever it says the buckets are is what
/// the app offers, including to the model.
nonisolated protocol CategorySource: Sendable {
    func categories() async throws -> [SpendCategory]
}

nonisolated protocol LedgerStore: CategorySource {
    /// Append is idempotent on `LedgerTransaction.id`. A retry after an ambiguous
    /// failure must read back by id and skip what already landed — never append
    /// twice and never assume the first attempt failed.
    func append(_ transactions: [LedgerTransaction]) async throws

    /// Every row. The calc tool needs the whole ledger to compare months, and a
    /// per-month fetch against a rate-limited API would be six round trips to
    /// answer one question.
    func all() async throws -> [LedgerTransaction]

    func transactions(in interval: DateInterval) async throws -> [LedgerTransaction]

    func transaction(id: LedgerTransaction.ID) async throws -> LedgerTransaction?

    /// Removes a transaction from the canonical store.
    func delete(_ id: LedgerTransaction.ID) async throws

    /// Invalidates any cached ledger state and fetches fresh rows from the source.
    func reload() async throws -> [LedgerTransaction]
}

extension LedgerStore {
    func reload() async throws -> [LedgerTransaction] {
        try await all()
    }
}

nonisolated enum LedgerError: Error, Sendable {
    case notAuthenticated
    case rateLimited(retryAfter: TimeInterval?)
    case schemaMismatch(expected: [String], found: [String])
    case transport(String)
}
