//
//  Money.swift
//  FTL — model/Domain
//
//  Invariant 4: money is never a Double. Amounts are integer minor units so that
//  summing a ledger is exact; formatting is the only place a decimal appears.
//

import Foundation

nonisolated struct CurrencyCode: Sendable, Hashable, Codable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue.uppercased() }

    /// Digits after the decimal point. IDR is quoted whole, so 0.
    var exponent: Int {
        switch rawValue {
        case "IDR", "JPY", "KRW", "VND": return 0
        default: return 2
        }
    }

    static let idr = CurrencyCode(rawValue: "IDR")

    /// Short symbol used in the UI. Falls back to the code itself.
    var symbol: String {
        switch rawValue {
        case "IDR": return "Rp"
        case "USD": return "$"
        case "EUR": return "€"
        default: return rawValue
        }
    }
}

nonisolated struct Money: Sendable, Hashable, Codable {
    /// Positive = outflow, matching the ledger's `amount` column.
    let minorUnits: Int
    let currency: CurrencyCode

    init(minorUnits: Int, currency: CurrencyCode = .idr) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    static func idr(_ whole: Int) -> Money { Money(minorUnits: whole, currency: .idr) }

    static let zero = Money(minorUnits: 0)

    var isZero: Bool { minorUnits == 0 }

    /// Adding across currencies is a programmer error, not a runtime fallback —
    /// v0.6 dropped FX, so a mixed-currency sum means something upstream is wrong.
    static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot add \(lhs.currency.rawValue) to \(rhs.currency.rawValue)")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot subtract \(rhs.currency.rawValue) from \(lhs.currency.rawValue)")
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currency: lhs.currency)
    }

    static func sum(_ amounts: [Money], currency: CurrencyCode = .idr) -> Money {
        amounts.reduce(Money(minorUnits: 0, currency: currency), +)
    }
}
