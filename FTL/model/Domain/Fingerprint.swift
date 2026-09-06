//
//  Fingerprint.swift
//  FTL — model/Domain
//
//  f(amount ± window, date ± window) — the deterministic blocking key that lets
//  the same purchase seen on two rails land in the same bucket without a model.
//
//  Fingerprints are deliberately lossy: they over-collect candidates, and a rule
//  (or, failing that, a flag) settles the real match. A fingerprint never decides
//  anything on its own.
//

import Foundation

nonisolated struct Fingerprint: Sendable, Hashable, Codable {
    /// Amount rounded into a bucket so a service charge or rounding difference
    /// still collides. Width is `Self.amountWindow`.
    let amountBucket: Int
    /// Days since reference epoch, bucketed by `Self.dateWindowDays`.
    let dateBucket: Int
    let currency: CurrencyCode

    /// Cross-rail lag: an email receipt and its statement line can be days apart.
    static let dateWindowDays = 3
    /// Tolerates tips, service charges, and rounding without merging different buys.
    static let amountWindowMinorUnits = 5_000

    init(amount: Money, date: Date, calendar: Calendar = .current) {
        self.amountBucket = amount.minorUnits / Self.amountWindowMinorUnits
        let days = calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: date).day ?? 0
        self.dateBucket = days / Self.dateWindowDays
        self.currency = amount.currency
    }

    /// Neighbouring buckets, so a pair straddling a bucket edge is still considered.
    /// Callers block on `self` *and* these before concluding "no candidate".
    var adjacent: [Fingerprint] {
        [(-1, 0), (1, 0), (0, -1), (0, 1)].map { da, dd in
            Fingerprint(amountBucket: amountBucket + da, dateBucket: dateBucket + dd, currency: currency)
        }
    }

    private init(amountBucket: Int, dateBucket: Int, currency: CurrencyCode) {
        self.amountBucket = amountBucket
        self.dateBucket = dateBucket
        self.currency = currency
    }
}
