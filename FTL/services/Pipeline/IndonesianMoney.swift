//
//  IndonesianMoney.swift
//  FTL — services/Pipeline
//
//  "Rp18.000,00" → Money(18_000, .idr).
//
//  Indonesian formatting is the mirror of US: dots group thousands, the comma is
//  the decimal separator. Handing that string to NumberFormatter under a US
//  locale reads it as 18.0 — a thousandfold error, silently. So it is parsed by
//  hand, and the fractional part is dropped because IDR has no minor unit.
//

import Foundation

enum IndonesianMoney {

    /// Matches "Rp18.000,00", "Rp 118.100", "IDR 7.000".
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?:Rp|IDR)\s*([\d.]+)(?:,(\d{1,2}))?"#,
        options: [.caseInsensitive]
    )

    /// The first amount in the text, or nil.
    static func first(in text: String) -> Money? {
        all(in: text).first
    }

    /// Every amount, in order of appearance. Callers pick — "Total" is usually
    /// first, but a transfer leads with "Amount" and appends "Admin Fee".
    static func all(in text: String) -> [Money] {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            let digits = text[r].replacingOccurrences(of: ".", with: "")
            guard let whole = Int(digits) else { return nil }
            return Money.idr(whole)
        }
    }

    /// The amount labelled `Total`, falling back to `Amount`. blu leads with
    /// "Total" on a purchase and with "Amount" on a transfer.
    static func labelled(_ label: String, in text: String) -> Money? {
        guard let range = text.range(of: label + " ", options: .caseInsensitive) else { return nil }
        return first(in: String(text[range.lowerBound...].prefix(40)))
    }
}
