//
//  HomeViewModel.swift
//  FTL — viewModel · Phase 1
//
//  The home screen: total spent against the month's ceiling, the approval queue,
//  the buckets, the goal, and recent ledger rows.
//
//  Formats; never computes. Every figure here arrived from CalcTool (Invariant 2).
//

import Foundation
import Observation

@Observable @MainActor
final class HomeViewModel {
    private let calc: CalcTool
    private let ledger: LedgerStore
    private let provisional: ProvisionalStore
    private let calendar: Calendar

    private(set) var phase: LoadPhase = .idle
    private(set) var months: [MonthSummary] = []
    private(set) var selectedMonthID: Date?
    private(set) var buckets: [BudgetPosition] = []
    private(set) var recent: [LedgerTransaction] = []
    private(set) var pending: [ProvisionalEntry] = []

    init(
        calc: CalcTool,
        ledger: LedgerStore,
        provisional: ProvisionalStore,
        calendar: Calendar = .current
    ) {
        self.calc = calc
        self.ledger = ledger
        self.provisional = provisional
        self.calendar = calendar
    }

    // MARK: - Derived

    var month: MonthSummary? {
        months.first { $0.id == selectedMonthID } ?? months.last
    }

    /// "September" for the current year, "September 2025" otherwise — the nav
    /// title stays short until the year actually disambiguates something.
    var monthTitle: String {
        guard let month else { return "" }
        let isThisYear = calendar.component(.year, from: month.interval.start)
            == calendar.component(.year, from: .now)
        return month.interval.start.formatted(
            isThisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year()
        )
    }

    var pendingCount: Int { pending.count }
    var hasPending: Bool { !pending.isEmpty }

    /// Total value sitting in the cache. Stated on the queue card so the user can
    /// see how much of the picture is missing, not just how many rows.
    var pendingTotal: Money {
        Money.sum(pending.map(\.transaction.amount))
    }

    var queueTitle: String {
        pendingCount == 1 ? "1 charge to approve" : "\(pendingCount) charges to approve"
    }

    /// "Rp 2.068.000 left over 9 days", or the closed-month equivalent.
    var remainingLabel: String {
        guard let month else { return "" }
        if month.isCurrent {
            let left = max(0, month.remaining.minorUnits)
            let money = Money(minorUnits: left, currency: month.ceiling.currency)
            return "\(MoneyFormatter.rp(money)) left over \(month.daysRemaining) days"
        }
        return month.isOverCeiling
            ? "\(MoneyFormatter.rp(Money(minorUnits: -month.remaining.minorUnits, currency: month.ceiling.currency))) over"
            : "\(MoneyFormatter.rp(month.remaining)) under the ceiling"
    }

    var perDayLabel: String {
        guard let month else { return "" }
        guard let perDay = month.perDayRemaining else { return "closed" }
        return MoneyFormatter.perDay(perDay)
    }

    var percentLabel: String {
        guard let month, month.ceiling.minorUnits > 0 else { return "" }
        return "\(Int((month.fraction * 100).rounded()))%"
    }

    // MARK: - Actions

    func load(forceReload: Bool = false) async {
        if case .idle = phase { phase = .loading }
        do {
            if forceReload {
                _ = try? await ledger.reload()
            }
            months = try await calc.monthSummaries(limit: 6)
            if selectedMonthID == nil { selectedMonthID = months.last?.id }
            try await reloadSelectedMonth()
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    func selectMonth(_ summary: MonthSummary) async {
        selectedMonthID = summary.id
        do {
            try await reloadSelectedMonth()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Same reload as a delete, and for the same reason: an edited amount or
    /// kind moves the hero total, the bucket meters and the month summaries,
    /// not just the row that was touched.
    func updateTransaction(_ transaction: LedgerTransaction) async {
        do {
            try await ledger.update(transaction)
            months = try await calc.monthSummaries(limit: 6)
            try await reloadSelectedMonth()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    func deleteTransaction(_ transaction: LedgerTransaction) async {
        do {
            try await ledger.delete(transaction.id)
            months = try await calc.monthSummaries(limit: 6)
            try await reloadSelectedMonth()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func reloadSelectedMonth() async throws {
        guard let month else { return }
        buckets = try await calc.budgetPositions(for: month.interval)
        recent = try await calc.transactions(in: month.interval, categoryID: nil, limit: 5)
        pending = try await provisional.pending()
        await updateWidgetSnapshot()
    }

    /// Delegates to `WidgetSnapshotWriter` — the same builder
    /// `BackgroundRefresh` uses, so a fetch that happens while the app is shut
    /// updates the home screen exactly the way opening the app does.
    private func updateWidgetSnapshot() async {
        await WidgetSnapshotWriter(calc: calc, provisional: provisional).write()
        // The daily reminder quotes this count, so it is re-pointed wherever the
        // count is recomputed rather than only where it is displayed. Every
        // settle path — approve, drop, the queue sheet closing — comes back
        // through here.
        await NotificationSchedule.refreshDigest(pendingCount: pending.count)
    }
}
