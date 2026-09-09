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

    /// Every bucket this amount could have landed in over the preceding `days`,
    /// self and neighbours included.
    ///
    /// `adjacent` covers ±1 bucket, which is ±3 days — right for two rails
    /// reporting one purchase, and far too narrow for a REFUND, which routinely
    /// arrives a fortnight after the charge it reverses. Rather than widen
    /// `dateWindowDays` for everyone (which would flood every duplicate check),
    /// a caller that is looking further back says so and pays for it in fetches.
    ///
    /// Still lossy, still over-collecting: this narrows the search, and the
    /// caller's own exact test decides. A fingerprint never concludes anything.
    func lookingBack(days: Int, calendar: Calendar = .current) -> Set<Fingerprint> {
        let steps = max(0, days / Self.dateWindowDays) + 1
        var buckets: Set<Fingerprint> = []
        for step in 0...steps {
            let shifted = Fingerprint(
                amountBucket: amountBucket,
                dateBucket: dateBucket - step,
                currency: currency
            )
            buckets.insert(shifted)
            buckets.formUnion(shifted.adjacent)
        }
        return buckets
    }

    private init(amountBucket: Int, dateBucket: Int, currency: CurrencyCode) {
        self.amountBucket = amountBucket
        self.dateBucket = dateBucket
        self.currency = currency
    }
}
