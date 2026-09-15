//
//  DateInterval+Ledger.swift
//  FTL — model/Domain
//
//  `DateInterval.contains` is CLOSED at both ends, and `Calendar.dateInterval(of:
//  .month, for:)` ends at the first instant of the next month. So a transaction
//  stamped exactly midnight on the 1st is contained by two consecutive months and
//  gets counted in both — a silent double-count in every monthly total.
//
//  Every ledger date comparison goes through this half-open check instead.
//

import Foundation

extension DateInterval {
    /// `start <= date < end` — the correct test for bucketing a transaction into
    /// a calendar period.
    nonisolated func containsLedgerDate(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
