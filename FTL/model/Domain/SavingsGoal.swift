//
//  SavingsGoal.swift
//  FTL — model/Domain
//
//  ⚠️ SCOPE NOTE: a savings goal is not in the v0.6 spec. It arrived with the
//  design canvas (Ideation/FTL App.dc.html), which gives it a home card and a
//  detail screen. Built because the design calls for it; flagged here because it
//  is the one feature in the UI with no line in the spec behind it.
//
//  It stays inside Invariant 8 as long as it reports a rate against a target the
//  user set — "Rp 112.100 / day to make it" — and never suggests the target, the
//  deadline, or what to give up to reach it.
//

import Foundation

nonisolated struct SavingsGoal: Sendable, Hashable, Identifiable, Codable {
    let id: UUID
    var name: String
    var target: Money
    var saved: Money
    var deadline: Date

    var remaining: Money {
        let left = target.minorUnits - saved.minorUnits
        return Money(minorUnits: max(0, left), currency: target.currency)
    }

    var fraction: Double {
        guard target.minorUnits > 0 else { return 0 }
        return min(Double(saved.minorUnits) / Double(target.minorUnits), 1)
    }

    func daysRemaining(from now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: deadline)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    /// What must be set aside per day to land on the target by the deadline.
    /// Rounded to a legible figure — a to-the-rupiah rate implies a precision the
    /// number doesn't have.
    func dailyRate(from now: Date = .now, calendar: Calendar = .current) -> Money {
        let days = daysRemaining(from: now, calendar: calendar)
        guard days > 0 else { return remaining }
        let raw = Double(remaining.minorUnits) / Double(days)
        let rounded = (raw / 100).rounded() * 100
        return Money(minorUnits: Int(rounded), currency: target.currency)
    }
}
