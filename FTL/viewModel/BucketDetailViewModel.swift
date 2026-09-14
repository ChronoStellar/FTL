//
//  BucketDetailViewModel.swift
//  FTL — viewModel · Phase 1
//
//  One bucket: spend against its ceiling, and the month's rows for it.
//
//  The ceiling is REPORTED here, not set. It used to be editable — an edit mode,
//  a ±50.000 stepper, six preset chips and an Undo in the title bar — and that
//  was the third place in the app that wrote the same number, after Settings →
//  Budget Ceilings and the income split. It was also the worst of the three:
//  a bucket's ceiling is a share of one income, and this screen is the only one
//  that let you move it with the other buckets out of sight, so the number most
//  in need of context was edited with none of it.
//
//  Set-up-by-income owns apportioning; Settings owns a one-off absolute figure.
//  This screen reports position against what they decided, which is what the
//  rest of it already did.
//

import Foundation
import Observation

@Observable @MainActor
final class BucketDetailViewModel {
    private let calc: CalcTool
    private let ledger: LedgerStore
    private let interval: DateInterval
    private let calendar: Calendar

    let categoryID: CategoryID
    let name: String

    /// Something the user did that did not work — a failed write, not a failed
    /// load. Settable from the view so dismissing the alert clears it; kept off
    /// `phase` so a failed save never blanks a screen that loaded fine.
    var actionError: String?

    private(set) var phase: LoadPhase = .idle
    private(set) var position: BudgetPosition?
    private(set) var transactions: [LedgerTransaction] = []

    init(
        categoryID: CategoryID,
        name: String,
        interval: DateInterval,
        calc: CalcTool,
        ledger: LedgerStore,
        calendar: Calendar = .current
    ) {
        self.categoryID = categoryID
        self.name = name
        self.interval = interval
        self.calc = calc
        self.ledger = ledger
        self.calendar = calendar
    }

    // MARK: - Derived

    var spent: Money { position?.actual ?? .zero }
    var ceiling: Money { position?.node.ceiling ?? .zero }
    var isOverCeiling: Bool { position?.standing == .overCeiling }

    var fraction: Double {
        guard ceiling.minorUnits > 0 else { return 0 }
        return Double(spent.minorUnits) / Double(ceiling.minorUnits)
    }

    var statusLabel: String {
        let remaining = ceiling - spent
        return remaining.minorUnits >= 0
            ? "\(MoneyFormatter.rp(remaining)) left"
            : "\(MoneyFormatter.rp(Money(minorUnits: -remaining.minorUnits, currency: remaining.currency))) over the ceiling"
    }

    var perDayLabel: String {
        let daysLeft = daysRemaining
        guard daysLeft > 0 else { return "closed" }
        guard !isOverCeiling else { return "over" }
        let remaining = max(0, (ceiling - spent).minorUnits)
        return MoneyFormatter.perDay(Money(minorUnits: remaining / daysLeft, currency: ceiling.currency))
    }

    /// Says where the number comes from, because this screen no longer sets it.
    var ceilingHint: String { "Set in Settings, or all at once by income" }

    private var daysRemaining: Int {
        let now = Date.now
        guard interval.containsLedgerDate(now) else { return 0 }
        return max(0, calendar.dateComponents([.day], from: now, to: interval.end).day ?? 0)
    }

    // MARK: - Actions

    func load() async {
        if case .idle = phase { phase = .loading }
        do {
            let positions = try await calc.budgetPositions(for: interval)
            position = Self.find(categoryID, in: positions)
            transactions = try await calc.transactions(in: interval, categoryID: categoryID, limit: 50)
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// A corrected row can leave this bucket entirely — retagging it, or
    /// marking it non-spend — so this reloads the whole screen rather than
    /// patching the row in place. The ceiling, the meter and the list all move.
    func updateTransaction(_ transaction: LedgerTransaction) async {
        do {
            try await ledger.update(transaction)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func deleteTransaction(_ transaction: LedgerTransaction) async {
        do {
            try await ledger.delete(transaction.id)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private static func find(_ id: CategoryID, in positions: [BudgetPosition]) -> BudgetPosition? {
        for position in positions {
            if position.id == id { return position }
            if let match = find(id, in: position.children) { return match }
        }
        return nil
    }
}
