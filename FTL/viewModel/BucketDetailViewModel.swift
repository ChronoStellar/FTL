//
//  BucketDetailViewModel.swift
//  FTL — viewModel · Phase 1
//
//  One bucket: spend against its ceiling, an editable ceiling, and the month's
//  rows for it.
//
//  Editing steps by a fixed amount with an Undo in the title bar rather than a
//  text field — a ceiling is a decision the user adjusts, not a value they type,
//  and a reversible nudge invites the adjustment.
//

import Foundation
import Observation

@Observable @MainActor
final class BucketDetailViewModel {
    private let calc: CalcTool
    private let budgets: BudgetStore
    private let interval: DateInterval
    private let calendar: Calendar

    let categoryID: CategoryID
    let name: String

    private(set) var phase: LoadPhase = .idle
    private(set) var position: BudgetPosition?
    private(set) var transactions: [LedgerTransaction] = []

    var isEditingCeiling = false
    /// The ceiling before editing began. Non-nil means Undo is available.
    private(set) var ceilingBeforeEdit: Money?

    /// Rp 50.000 — large enough that a tap moves the number visibly, small enough
    /// that landing on a specific figure doesn't take a dozen taps.
    static let ceilingStep = 50_000

    init(
        categoryID: CategoryID,
        name: String,
        interval: DateInterval,
        calc: CalcTool,
        budgets: BudgetStore,
        calendar: Calendar = .current
    ) {
        self.categoryID = categoryID
        self.name = name
        self.interval = interval
        self.calc = calc
        self.budgets = budgets
        self.calendar = calendar
    }

    // MARK: - Derived

    var spent: Money { position?.actual ?? .zero }
    var ceiling: Money { position?.node.ceiling ?? .zero }
    var isOverCeiling: Bool { position?.standing == .overCeiling }
    var canUndo: Bool { ceilingBeforeEdit != nil }

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

    var ceilingHint: String {
        isEditingCeiling
            ? "Steps \(MoneyFormatter.rp(Money.idr(Self.ceilingStep))) · Undo is in the title bar"
            : "What you set for \(name) each month"
    }

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

    func beginEditing() { isEditingCeiling = true }

    func step(by delta: Int) async {
        guard let current = position?.node.ceiling else { return }
        if ceilingBeforeEdit == nil { ceilingBeforeEdit = current }
        let next = Money(
            minorUnits: max(0, current.minorUnits + delta),
            currency: current.currency
        )
        await apply(next)
    }

    func undo() async {
        guard let original = ceilingBeforeEdit else { return }
        ceilingBeforeEdit = nil
        isEditingCeiling = false
        await apply(original)
    }

    private func apply(_ ceiling: Money) async {
        do {
            try await budgets.setCeiling(ceiling, for: categoryID, in: interval)
            await load()
        } catch {
            phase = .failed(String(describing: error))
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
