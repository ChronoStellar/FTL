//
//  ManualEntry.swift
//  FTL — services/Capture · Phase 1
//
//  The manual rail — the only one that catches cash — with exactly one
//  implementation of what a hand-entered spend becomes.
//
//  It exists because there are now two front doors onto the same act: the Add
//  Spend sheet and the Add Spend App Intent. Building the ProvisionalEntry in
//  both places is how the two slowly disagree about `source`, `provenance`, or
//  what an empty note means — the same two-representations drift that put a
//  self-parented row in the budgets tab.
//
//  Invariant 1 holds: this writes to the provisional cache and then asks
//  ApprovalService to promote it. There is still no other path into the ledger.
//  The immediate approval is not an exception to the human gate — the human
//  typed the number; re-confirming their own keystrokes is not review.
//

import Foundation

nonisolated struct ManualEntry: Sendable {
    private let provisional: ProvisionalStore
    private let approvals: ApprovalService?

    init(provisional: ProvisionalStore, approvals: ApprovalService?) {
        self.provisional = provisional
        self.approvals = approvals
    }

    /// Records a hand-entered spend and promotes it. Returns the entry as it
    /// was cached, so a caller can report what it wrote.
    @discardableResult
    func record(
        amount: Money,
        categoryID: CategoryID?,
        note: String?,
        at date: Date = .now
    ) async throws -> ProvisionalEntry {
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let transaction = NormalizedTransaction(
            id: UUID(),
            documentID: UUID(),
            source: .manual,
            date: date,
            amount: amount,
            // Invariant 3: merchantRaw is written once and never mutated. With
            // no note there is nothing a person typed, so it says so rather
            // than inventing a merchant.
            merchantRaw: trimmed.isEmpty ? "Manual entry" : trimmed,
            merchant: trimmed.isEmpty ? nil : MerchantID(rawValue: trimmed),
            lineItems: [],
            fingerprint: Fingerprint(amount: amount, date: date)
        )

        let entry = ProvisionalEntry(
            id: UUID(),
            transaction: transaction,
            resolution: ProvisionalEntry.Resolution(
                kind: .spend,
                nonSpendType: nil,
                categoryID: categoryID,
                merchantID: nil,
                splits: [],
                mergedFrom: []
            ),
            provenance: .manual,
            flags: [],
            status: .pending,
            createdAt: date
        )

        try await provisional.insert([entry])
        if let approvals {
            _ = try await approvals.approve([entry.id])
        }
        return entry
    }
}
