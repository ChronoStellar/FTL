//
//  EditTransactionViewModel.swift
//  FTL — viewModel · Phase 1
//
//  A ledger row, opened for correction. Amount, kind, bucket and note — the
//  four fields that can be wrong on a row the app captured for you.
//
//  `date` is deliberately NOT offered. It stays `let` on `LedgerTransaction`
//  alongside `merchantRaw` and `source`: when a receipt was dated is a fact
//  about the receipt, not a judgement about the row, and nothing in the capture
//  pipeline can get it wrong the way it can get an amount wrong.
//
//  It holds the draft and nothing else: it takes a `CategorySource`, NOT a
//  `LedgerStore`, so it can read what the buckets are and is structurally
//  incapable of writing a transaction. The write stays with the screen that owns
//  the list — `HomeViewModel.updateTransaction`, `BucketDetailViewModel
//  .updateTransaction` — which is exactly where `deleteTransaction` already
//  lives, and which is why `CategorySource` was split out of `LedgerStore` in
//  the first place.
//
//  Invariant 3 needs no defending here: `merchantRaw` is `let` on
//  `LedgerTransaction`, so `edited` cannot rewrite it however this file is
//  changed later. It is shown, read-only, because a person correcting a figure
//  needs to see the string the row was parsed out of.
//
//  Invariant 4: the amount is held as digits, never a Double. IDR has no minor
//  units, so what is typed is what is stored.
//

import Foundation
import Observation

@Observable @MainActor
final class EditTransactionViewModel {
    private let categorySource: CategorySource

    /// The row as it stands in the Sheet. Kept whole so `edited` can copy every
    /// field this screen does not offer — splits, line items, merged sources,
    /// provenance, flags — through untouched rather than rebuilding a row and
    /// silently dropping what it forgot about.
    let original: LedgerTransaction

    var amountDigits: String
    var kind: TransactionKind
    /// Only meaningful while `kind == .nonSpend`. Kept across a toggle to spend
    /// and back so flipping the control twice doesn't lose the choice.
    var nonSpendType: NonSpendType
    var categoryID: CategoryID?
    var note: String

    private(set) var categories: [SpendCategory] = []
    private(set) var phase: LoadPhase = .idle

    init(transaction: LedgerTransaction, categories categorySource: CategorySource) {
        self.categorySource = categorySource
        self.original = transaction
        self.amountDigits = String(transaction.amount.minorUnits)
        self.kind = transaction.kind
        self.nonSpendType = transaction.nonSpendType ?? .transfer
        self.categoryID = transaction.categoryID
        self.note = transaction.notes ?? ""
    }

    // MARK: - Derived

    var amount: Money {
        Money(minorUnits: Int(amountDigits) ?? 0, currency: original.amount.currency)
    }

    var title: String { original.merchant ?? original.merchantRaw }

    /// Zero is not a correction, it is a row that should be deleted instead —
    /// and Delete is on this screen, so there is somewhere to send it.
    var canSave: Bool { amount.minorUnits > 0 && hasChanges }

    var hasChanges: Bool { edited != original }

    /// The row as corrected. Every field the screen does not offer is carried
    /// over from `original` verbatim.
    var edited: LedgerTransaction {
        var copy = original
        copy.amount = amount
        copy.kind = kind
        // Invariant 5: a non-spend row is LABELLED. Clearing the type when a row
        // goes back to spend keeps the two fields from disagreeing — a spend row
        // carrying `.refund` is a row that reads differently depending on which
        // column you look at.
        copy.nonSpendType = kind == .nonSpend ? nonSpendType : nil
        copy.categoryID = categoryID
        copy.notes = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : note.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    // MARK: - Actions

    func load() async {
        if case .idle = phase { phase = .loading }
        do {
            categories = try await categorySource.categories()
            phase = .loaded
        } catch {
            // A category list that won't load does not block the edit: the
            // amount and the kind are both still correctable, and the bucket
            // picker falls back to whatever the row already carries.
            categories = []
            phase = .loaded
        }
    }

    /// Digits only, and bounded. A paste of "Rp 34.500" would otherwise arrive
    /// as an unparseable string and silently read as zero.
    func sanitizeAmount() {
        let digits = amountDigits.filter(\.isNumber)
        let trimmed = String(digits.prefix(Self.maxDigits))
        if trimmed != amountDigits { amountDigits = trimmed }
    }

    /// Enough for Rp 999.999.999.
    private static let maxDigits = 9
}
