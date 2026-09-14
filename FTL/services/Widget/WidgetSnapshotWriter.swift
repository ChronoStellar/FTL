//
//  WidgetSnapshotWriter.swift
//  FTL — services/Widget
//
//  Builds the widget snapshot from the ledger, from anywhere.
//
//  It used to be a private method on `HomeViewModel`, which meant the widgets
//  were only ever as fresh as the last time somebody opened the Home screen.
//  Everything else that changes the numbers — approving a row, correcting an
//  amount, and above all `BackgroundRefresh`, whose entire job is to run while
//  the app is closed — left them showing the previous figures. A widget is the
//  one surface a person reads WITHOUT opening the app, so "updated when the app
//  is open" is close to the opposite of what it needs.
//
//  Reads through `CalcTool` like every other number in this app (Invariant 2 —
//  the arithmetic is not re-implemented here).
//

import Foundation

@MainActor
struct WidgetSnapshotWriter {
    private let calc: CalcTool
    private let provisional: ProvisionalStore
    private let calendar: Calendar

    init(calc: CalcTool, provisional: ProvisionalStore, calendar: Calendar = .current) {
        self.calc = calc
        self.provisional = provisional
        self.calendar = calendar
    }

    /// Recomputes and publishes. Silent on failure by design: every caller is
    /// doing something else and none of them should fail because a home screen
    /// widget could not be refreshed.
    @discardableResult
    func write() async -> Bool {
        guard let summary = try? await calc.monthSummaries(limit: 6),
              let currentMonth = summary.first(where: { $0.isCurrent }) ?? summary.last
        else { return false }

        let today = calendar.dateInterval(of: .day, for: .now)
            ?? DateInterval(start: .now, duration: 86_400)
        let todaySpent = (try? await calc.evaluate(LedgerQuery(interval: today)))?.total.minorUnits ?? 0
        let allowance = currentMonth.perDayRemaining?.minorUnits ?? 0

        let positions = (try? await calc.budgetPositions(for: currentMonth.interval)) ?? []
        // Named buckets only. `unallocated` is the implicit child — offering it
        // as a quick-log destination would invite spending to be filed under
        // "I didn't say", which is the one bucket nobody should be choosing.
        let buckets = (positions.first?.children ?? positions)
            .filter { $0.id != .unallocated }
            .prefix(4)
            .map { WidgetBucket(id: $0.node.id.rawValue, name: $0.node.name) }

        let pending = (try? await provisional.pending())?.count ?? 0

        return WidgetDataManager.shared.saveSnapshot(
            WidgetDataSnapshot(
                dailyAllowance: allowance,
                todaySpent: todaySpent,
                todayRemaining: allowance - todaySpent,
                monthRemaining: currentMonth.remaining.minorUnits,
                monthCeiling: currentMonth.ceiling.minorUnits,
                daysRemaining: currentMonth.daysRemaining,
                monthTitle: Self.monthTitle(for: currentMonth, calendar: calendar),
                currencyCode: currentMonth.ceiling.currency.rawValue,
                isOverDailyBudget: allowance > 0 && todaySpent > allowance,
                isOverMonthCeiling: currentMonth.isOverCeiling,
                pendingApprovalCount: pending,
                topBuckets: Array(buckets)
            )
        )
    }

    private static func monthTitle(for month: MonthSummary, calendar: Calendar) -> String {
        month.interval.start.formatted(.dateTime.month(.wide))
    }
}
