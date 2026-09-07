//
//  AddSpendViewModel.swift
//  FTL — viewModel · Phase 1
//
//  Manual entry — the fourth rail, and the only one that can catch cash.
//
//  A custom keypad rather than a TextField: the amount is the entire screen, IDR
//  has no decimals so a full keyboard is mostly wasted keys, and "000" is worth a
//  key of its own in a currency where every figure ends in at least three zeros.
//

import Foundation
import Observation

@Observable @MainActor
final class AddSpendViewModel {
    private let provisional: ProvisionalStore
    private let approvals: ApprovalService?
    private let ledger: LedgerStore
    private let calc: CalcTool
    private let interval: DateInterval

    /// Digits as typed. Kept as a string so leading zeros and backspace behave
    /// the way a keypad implies, rather than fighting an Int.
    private(set) var digits = ""
    var merchantText: String = ""
    private(set) var categories: [SpendCategory] = []
    var selectedCategoryID: CategoryID?
    private(set) var phase: LoadPhase = .idle

    /// Enough for Rp 999.999.999 — past any plausible single purchase.
    private let maxDigits = 9

    init(
        provisional: ProvisionalStore,
        approvals: ApprovalService? = nil,
        ledger: LedgerStore,
        calc: CalcTool,
        interval: DateInterval
    ) {
        self.provisional = provisional
        self.approvals = approvals
        self.ledger = ledger
        self.calc = calc
        self.interval = interval
    }

    // MARK: - Derived

    var amount: Money { Money.idr(Int(digits) ?? 0) }
    var hasAmount: Bool { amount.minorUnits > 0 }
    var amountDisplay: String { MoneyFormatter.rp(amount) }

    /// A tag is mandatory; the description field (`merchantText`) stays optional
    /// — see `commit()`. `load()` auto-selects the first category, so this is
    /// false only when the Sheet has no categories at all yet.
    var hasCategory: Bool { selectedCategoryID != nil }
    var canCommit: Bool { hasAmount && hasCategory }

    /// "Food would be Rp 534.000 left" — the consequence of this entry, stated
    /// before it is committed. A fact about the ceiling, not a warning.
    private(set) var consequence: String = "Tap a number to start"

    var keys: [KeypadKey] {
        (1...9).map { KeypadKey(label: "\($0)", kind: .digit("\($0)")) }
            + [
                KeypadKey(label: "000", kind: .digit("000")),
                KeypadKey(label: "0", kind: .digit("0")),
                KeypadKey(label: "delete.left", kind: .backspace),
            ]
    }

    // MARK: - Actions

    func load() async {
        do {
            categories = try await ledger.categories()
            if selectedCategoryID == nil { selectedCategoryID = categories.first?.id }
            await updateConsequence()
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    func press(_ key: KeypadKey) async {
        switch key.kind {
        case .digit(let value):
            let next = (digits + value).drop { $0 == "0" }
            digits = String(next.prefix(maxDigits))
        case .backspace:
            digits = String(digits.dropLast())
        }
        await updateConsequence()
    }

    func select(_ id: CategoryID) async {
        selectedCategoryID = id
        await updateConsequence()
    }

    /// Manual entries land in the cache like everything else (Invariant 1),
    /// and are approved immediately so the ledger is updated without requiring
    /// a redundant manual confirmation.
    func commit() async -> Bool {
        guard canCommit else { return false }
        phase = .loading
        let now = Date.now
        let money = amount
        let merchantName = merchantText.trimmingCharacters(in: .whitespaces)
        let rawMerchant = merchantName.isEmpty ? "Manual entry" : merchantName
        let cleanMerchant = merchantName.isEmpty ? nil : MerchantID(rawValue: merchantName)

        let transaction = NormalizedTransaction(
            id: UUID(),
            documentID: UUID(),
            source: .manual,
            date: now,
            amount: money,
            merchantRaw: rawMerchant,
            merchant: cleanMerchant,
            lineItems: [],
            fingerprint: Fingerprint(amount: money, date: now)
        )
        let entry = ProvisionalEntry(
            id: UUID(),
            transaction: transaction,
            resolution: ProvisionalEntry.Resolution(
                kind: .spend,
                nonSpendType: nil,
                categoryID: selectedCategoryID,
                merchantID: nil,
                splits: [],
                mergedFrom: []
            ),
            provenance: .manual,
            flags: [],
            status: .pending,
            createdAt: now
        )
        do {
            try await provisional.insert([entry])
            if let approvals {
                _ = try await approvals.approve([entry.id])
            }
            phase = .loaded
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    private func updateConsequence() async {
        guard hasAmount, let categoryID = selectedCategoryID,
              let category = categories.first(where: { $0.id == categoryID })
        else {
            consequence = "Tap a number to start"
            return
        }
        do {
            let positions = try await calc.budgetPositions(for: interval)
            guard let position = Self.find(categoryID, in: positions) else {
                consequence = "\(category.name) has no ceiling set"
                return
            }
            let after = position.node.ceiling.minorUnits - position.actual.minorUnits - amount.minorUnits
            let money = Money(minorUnits: abs(after), currency: amount.currency)
            consequence = after >= 0
                ? "\(category.name) would be \(MoneyFormatter.rp(money)) left"
                : "\(category.name) would be \(MoneyFormatter.rp(money)) over"
        } catch {
            consequence = ""
        }
    }

    private static func find(_ id: CategoryID, in positions: [BudgetPosition]) -> BudgetPosition? {
        for position in positions {
            if position.id == id { return position }
            if let match = find(id, in: position.children) { return match }
        }
        return nil
    }

    struct KeypadKey: Identifiable, Hashable {
        var id: String { label }
        let label: String
        let kind: Kind

        enum Kind: Hashable {
            case digit(String)
            case backspace
        }

        var isBackspace: Bool { kind == .backspace }
    }
}
