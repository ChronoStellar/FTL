//
//  MonthSummary.swift
//  FTL — model/Domain
//
//  One month's total against its ceiling. Feeds the month picker and the home
//  hero. Produced by CalcTool — the figures are computed, never narrated.
//

import Foundation

nonisolated struct MonthSummary: Sendable, Hashable, Identifiable {
    var id: Date { interval.start }

    let interval: DateInterval
    let spent: Money
    let ceiling: Money

    /// True for the month currently in progress. A closed month has no days left
    /// and no per-day rate — reporting one would be fiction.
    let isCurrent: Bool
    let daysRemaining: Int

    var fraction: Double {
        guard ceiling.minorUnits > 0 else { return 0 }
        return Double(spent.minorUnits) / Double(ceiling.minorUnits)
    }

    var isOverCeiling: Bool { spent.minorUnits > ceiling.minorUnits }

    /// Positive when under the ceiling, negative when over.
    var remaining: Money { ceiling - spent }

    /// What is left per remaining day. Nil for a closed month.
    var perDayRemaining: Money? {
        guard isCurrent, daysRemaining > 0 else { return nil }
        let left = max(0, remaining.minorUnits)
        return Money(minorUnits: left / daysRemaining, currency: ceiling.currency)
    }
}
