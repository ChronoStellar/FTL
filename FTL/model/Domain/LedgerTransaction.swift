//
//  LedgerTransaction.swift
//  FTL — model/Domain
//
//  The canonical row, as written to the Google Sheets `transactions` tab. Reached
//  through exactly one path: ApprovalService promoting an approved ProvisionalEntry.
//  Nothing else constructs one.
//
//  Column order here is the Sheets column order — see services/Ledger/SheetsSchema.
//

import Foundation

nonisolated struct LedgerTransaction: Sendable, Hashable, Identifiable, Codable {
    /// Idempotency key for the Sheets append. A retried append is detected by
    /// reading this back, never by appending again and hoping.
    let id: UUID

    let date: Date

    /// `var` so a person can correct a figure the parser got wrong — the one
    /// field on this row where "what the app read" and "what was actually
    /// charged" can differ and only a human can say which is right. Written
    /// through `LedgerStore.update`; still never by the model (Invariant 1),
    /// and still never a `Double` (Invariant 4).
    ///
    /// Everything around it stays `let` on purpose. `id`, `merchantRaw`,
    /// `source`, `capturedAt` and `approvedAt` are records of how this row came
    /// to exist, not judgements about it, and a correction is not allowed to
    /// rewrite its own history.
    var amount: Money

    /// Invariant 3 — preserved forever, per source.
    let merchantRaw: String
    var merchant: String?
    var categoryID: CategoryID?

    var kind: TransactionKind
    var nonSpendType: NonSpendType?

    let source: CaptureSource
    /// Rail rows folded into this one, so a merge stays reversible after the fact.
    var sourcesMerged: [UUID]
    var splits: [Split]
    var lineItems: [LineItem]

    /// Carried over from the cache so the ledger records whether a rule or the
    /// model produced this row, and what a human saw before approving it.
    var provenance: ProvisionalEntry.Provenance
    var flags: [ReviewFlag]

    let capturedAt: Date
    let approvedAt: Date
    var notes: String?

    /// Only spend counts toward a ceiling. The single place this rule is expressed.
    var countsTowardBudget: Bool { kind == .spend }
}
