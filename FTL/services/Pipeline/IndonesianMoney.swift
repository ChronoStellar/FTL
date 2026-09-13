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

    /// Matches "Rp18.000,00", "Rp 118.100", "IDR 7.000" — and "Rp 166 080".
    ///
    /// **Spaces group thousands too, and missing that read Steam 1000× low.**
    /// Steam's receipts write `Total: Rp 166 080`, where the group separator is
    /// a space rather than a dot. The old `([\d.]+)` stopped at the first
    /// space, so Rp 166.080 was recorded as **Rp 166** — the same thousandfold
    /// error this file exists to prevent, arriving through a separator nobody
    /// had seen yet. It also made the row impossible to deduplicate against
    /// the bank's `WL *STEAM PURCHASE` notification, because the two amounts
    /// were then off by three orders of magnitude.
    ///
    /// Only exact 3-digit groups extend the match, so a second, unrelated
    /// figure sitting after an amount cannot be swallowed into it. Measured
    /// over all 1,000 emails in the export: **11 parses change, every one of
    /// them Steam, every one a 1000× correction — and 0 blu emails move**, so
    /// the 116/116 parser is untouched.
    ///
    /// **Commas group thousands too, and that one is worse.** Some senders
    /// write US-style: `IDR 10,000,000` from bankmandiri, `Rp 25,600` from
    /// kai.id, `Rp260,000` from Traveloka. Under the old rule those read as
    /// **Rp 10**, **Rp 25** and **Rp 260** — a millionfold error, out of a
    /// bank.
    ///
    /// This is genuinely ambiguous in Indonesian, where the comma is the
    /// DECIMAL separator — and it is resolvable only because IDR has no minor
    /// unit (Invariant 4, `Money`). `,600` therefore cannot be a fraction of
    /// anything, so: **comma + exactly 3 digits is a group separator, comma +
    /// one or two digits stays the decimal** it has always been. `Rp18.000,00`
    /// is unaffected — `,00` is two digits and still falls to the fractional
    /// arm, which is still dropped.
    ///
    /// Measured the same way before changing it: **13 parses change — 9
    /// Traveloka, 3 bankmandiri, 1 kai.id — and 0 blu, 0 grab**, the only two
    /// senders with live patterns. Latent rather than active today, and
    /// `PatternDiscovery`'s near-miss top-up makes those senders more likely
    /// to be learned, not less.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?:Rp|IDR)\s*([\d.]+(?:[ \x{00A0}]\d{3})*(?:,\d{3})*)(?:,(\d{1,2}))?"#,
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
            // Every separator this pattern can match is a GROUP separator by
            // the time it reaches here — the decimal comma is captured
            // separately and deliberately discarded (IDR has no minor unit).
            let digits = text[r]
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: "")
            guard let whole = Int(digits) else { return nil }
            return Money.idr(whole)
        }
    }

    /// The amount labelled `Total`, falling back to `Amount`. blu leads with
    /// "Total" on a purchase and with "Amount" on a transfer.
    ///
    /// Any whitespace separates the two, not just a single space: an HTML table
    /// puts the label in one cell and the figure in the next, which strips to a
    /// newline. Matching on `label + " "` read 3 of 112 real emails.
    static func labelled(_ label: String, in text: String) -> Money? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        guard let range = text.range(
            of: escaped + #"\s+"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        return first(in: String(text[range.lowerBound...].prefix(40)))
    }
}
