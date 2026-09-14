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

    /// Replaces the row carrying the same `id`, in place.
    ///
    /// A second write path into the canonical store, and deliberately so — but
    /// read Invariant 1 before adding a third. What that invariant forbids is
    /// the MODEL writing, and what `ApprovalService` is sole owner of is
    /// PROMOTION: provisional → canonical. This is neither. It is a person
    /// correcting a row they are already looking at, which is exactly the
    /// authority `delete` below already carries — and correcting a figure is
    /// strictly less destructive than removing it.
    ///
    /// Invariant 3 is carried by the TYPE, not by this comment: `merchantRaw`,
    /// `id`, `source`, `capturedAt` and `approvedAt` are all `let` on
    /// `LedgerTransaction`, so an edit physically cannot rewrite the raw string
    /// the reconciliation join key depends on.
    ///
    /// Throws `.rowNotFound` rather than no-op'ing when the id is absent. An
    /// edit that silently saves nothing is the worst outcome available here:
    /// the user watches the sheet close over a figure that never changed.
    func update(_ transaction: LedgerTransaction) async throws

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

/// `LocalizedError` because these now reach a person. Action failures surface in
/// an alert via `localizedDescription`, and the default for a bare Swift enum is
/// its case name — `rowNotFound(id: 9F2C…)` is a stack trace wearing a sentence's
/// clothes.
nonisolated enum LedgerError: Error, Sendable, LocalizedError {
    case notAuthenticated
    case rateLimited(retryAfter: TimeInterval?)
    case schemaMismatch(expected: [String], found: [String])
    /// An update or delete named an id the store no longer has.
    case rowNotFound(id: UUID)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You're signed out of Google. Sign in again from Settings."
        case .rateLimited(let retryAfter):
            guard let retryAfter else { return "Google is rate-limiting the sheet. Try again shortly." }
            return "Google is rate-limiting the sheet. Try again in \(Int(retryAfter.rounded())) seconds."
        case .schemaMismatch(let expected, let found):
            return "The sheet's columns don't match what the app writes.\n"
                + "Expected \(expected.count) (\(expected.prefix(3).joined(separator: ", "))…), "
                + "found \(found.count)."
        case .rowNotFound:
            // Almost always a real race: the row was deleted or the sheet was
            // edited by hand between this screen loading and the write.
            return "That row is no longer in the sheet — it may have been deleted or edited elsewhere. Pull to refresh."
        case .transport(let detail):
            return "Couldn't reach the sheet. \(detail)"
        }
    }
}
