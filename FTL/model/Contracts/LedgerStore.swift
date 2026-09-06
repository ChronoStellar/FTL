//
//  LedgerStore.swift
//  FTL — model/Contracts · Phase 1
//
//  The canonical store — Google Sheets. Written through ApprovalService alone.
//
//  Implementation: services/Ledger/SheetsLedgerStore
//

import Foundation

nonisolated protocol LedgerStore: Sendable {
    /// Append is idempotent on `LedgerTransaction.id`. A retry after an ambiguous
    /// failure must read back by id and skip what already landed — never append
    /// twice and never assume the first attempt failed.
    func append(_ transactions: [LedgerTransaction]) async throws

    func transactions(in interval: DateInterval) async throws -> [LedgerTransaction]

    func transaction(id: LedgerTransaction.ID) async throws -> LedgerTransaction?

    /// The merchant dictionary, read for RuleContext and grown by use — a lookup
    /// table, not a model call.
    func merchants() async throws -> [Merchant]
    func upsertMerchant(_ merchant: Merchant) async throws

    func categories() async throws -> [SpendCategory]
}

nonisolated enum LedgerError: Error, Sendable {
    case notAuthenticated
    case rateLimited(retryAfter: TimeInterval?)
    case schemaMismatch(expected: [String], found: [String])
    case transport(String)
}
