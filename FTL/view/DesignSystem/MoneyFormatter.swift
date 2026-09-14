//
//  MoneyFormatter.swift
//  FTL — view/DesignSystem
//
//  Presentation only. This is the one place a `Money` becomes a decimal string —
//  the arithmetic itself stays in integer minor units (Invariant 4).
//

import Foundation

enum MoneyFormatter {

    /// "4.432.000" — the design's default. Dot thousands separators, no symbol,
    /// no decimals for IDR. Pinned to a fixed locale so the ledger reads the same
    /// on every device rather than reshaping itself around a system setting.
    static func grouped(_ money: Money) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.maximumFractionDigits = money.currency.exponent
        formatter.minimumFractionDigits = money.currency.exponent

        let value = Double(money.minorUnits) / pow(10, Double(money.currency.exponent))
        return formatter.string(from: NSNumber(value: value)) ?? "\(money.minorUnits)"
    }

    /// "Rp 4.432.000".
    static func rp(_ money: Money) -> String {
        "\(money.currency.symbol) \(grouped(money))"
    }

    /// "Rp 264.333 / day".
    static func perDay(_ money: Money) -> String {
        "\(rp(money)) / day"
    }

    /// "622.000 left" or "138.000 over" — the bucket row's status. Reports which
    /// side of the ceiling the figure falls on and stops there (Invariant 8).
    static func standing(remaining: Money) -> String {
        remaining.minorUnits >= 0
            ? "\(grouped(remaining)) left"
            : "\(grouped(Money(minorUnits: -remaining.minorUnits, currency: remaining.currency))) over"
    }
}
