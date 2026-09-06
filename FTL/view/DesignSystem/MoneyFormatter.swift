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

    /// Compact, for dense budget rows: "1.5M", "750k", "Rp 0".
    /// Deliberately lossy — the exact figure belongs on the detail screen.
    static func compact(_ money: Money) -> String {
        let value = Double(money.minorUnits) / pow(10, Double(money.currency.exponent))
        let magnitude = abs(value)
        let sign = value < 0 ? "-" : ""

        switch magnitude {
        case 1_000_000...:
            return "\(sign)\(trim(magnitude / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(trim(magnitude / 1_000))k"
        default:
            return "\(sign)\(trim(magnitude))"
        }
    }

    /// Full precision, grouped: "Rp 1.500.000".
    static func full(_ money: Money) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = money.currency.rawValue
        formatter.maximumFractionDigits = money.currency.exponent
        formatter.minimumFractionDigits = money.currency.exponent

        let value = Double(money.minorUnits) / pow(10, Double(money.currency.exponent))
        return formatter.string(from: NSNumber(value: value)) ?? "\(money.minorUnits)"
    }

    /// "0.6M of 0.5M" — the dashboard's whole vocabulary. A flat fact, no verb.
    /// Invariant 8 lives in the absence of anything else in this string.
    static func position(actual: Money, ceiling: Money) -> String {
        "\(compact(actual)) of \(compact(ceiling))"
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
