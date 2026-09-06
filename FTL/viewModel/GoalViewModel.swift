//
//  GoalViewModel.swift
//  FTL — viewModel · Phase 1
//
//  ⚠️ Not in the v0.6 spec — see model/Domain/SavingsGoal for the scope note.
//
//  Reports the daily rate implied by a target and a deadline the user set. It
//  never proposes either, and never says where the money should come from.
//

import Foundation
import Observation

@Observable @MainActor
final class GoalViewModel {
    private let goals: GoalStore
    private let calendar: Calendar

    private(set) var phase: LoadPhase = .idle
    private(set) var goal: SavingsGoal?
    private(set) var goalBeforeEdit: SavingsGoal?

    var editingField: Field?

    static let amountStep = 500_000
    /// Deadlines step a month at a time; a to-the-day picker implies a precision
    /// a savings target rarely has.
    static let deadlineStepMonths = 1

    init(goals: GoalStore, calendar: Calendar = .current) {
        self.goals = goals
        self.calendar = calendar
    }

    // MARK: - Derived

    var canUndo: Bool { goalBeforeEdit != nil }
    var dailyRate: Money { goal?.dailyRate(calendar: calendar) ?? .zero }
    var remaining: Money { goal?.remaining ?? .zero }
    var saved: Money { goal?.saved ?? .zero }
    var fraction: Double { goal?.fraction ?? 0 }

    var deadlineLabel: String {
        goal?.deadline.formatted(.dateTime.day().month(.abbreviated).year()) ?? "—"
    }

    var note: String {
        guard let goal else { return "" }
        let days = goal.daysRemaining(calendar: calendar)
        return "\(MoneyFormatter.rp(goal.remaining)) over \(days) days. Tap a row to change it."
    }

    // MARK: - Actions

    func load() async {
        if case .idle = phase { phase = .loading }
        do {
            goal = try await goals.goal()
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    func stepAmount(by delta: Int) async {
        guard var goal else { return }
        if goalBeforeEdit == nil { goalBeforeEdit = goal }
        let next = max(1_000_000, goal.target.minorUnits + delta)
        goal.target = Money(minorUnits: next, currency: goal.target.currency)
        await save(goal)
    }

    func stepDeadline(by months: Int) async {
        guard var goal else { return }
        if goalBeforeEdit == nil { goalBeforeEdit = goal }
        guard let next = calendar.date(byAdding: .month, value: months, to: goal.deadline) else { return }
        // A deadline in the past makes the daily rate meaningless.
        guard next > Date.now else { return }
        goal.deadline = next
        await save(goal)
    }

    func undo() async {
        guard let original = goalBeforeEdit else { return }
        goalBeforeEdit = nil
        editingField = nil
        await save(original)
    }

    private func save(_ goal: SavingsGoal) async {
        do {
            try await goals.save(goal)
            self.goal = goal
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    enum Field: Hashable {
        case amount
        case deadline
    }
}
