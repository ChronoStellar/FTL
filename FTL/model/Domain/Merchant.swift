//
//  Merchant.swift
//  FTL — model/Domain
//
//  The merchant dictionary: a fuzzy-matched lookup table populated by use, not a
//  model call. Every resolved merchant makes the next one cheaper, which is what
//  shrinks the model's share over time.
//

import Foundation

nonisolated struct MerchantID: Sendable, Hashable, Codable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    /// The key a tag accrues against, derived from `merchantRaw`.
    ///
    /// Invariant 3 is why this is a separate value rather than a cleanup pass:
    /// `merchantRaw` is written once and never mutated, so the shop's identity
    /// has to be COMPUTED from it every time instead of stored over it. That
    /// also means a better rule here retroactively improves every past row,
    /// because nothing was overwritten to get the old one.
    ///
    /// Three things, and only three, because each is a spelling difference the
    /// same shop actually produces across rails:
    ///
    /// · **case** — `bigA bakehouse SURABAYA` and `BIGA BAKEHOUSE SURABAYA` are
    ///   one shop, and lowercasing is the whole difference between them;
    /// · **punctuation and runs of whitespace** — a stripped HTML cell and a
    ///   Gmail snippet space the same name differently;
    /// · **a trailing payment reference** — `Grab* A-9MVBRDUGW7GDAV` is Grab
    ///   with a booking id glued on, and the id is different every time, so left
    ///   in it makes every purchase a merchant seen once.
    ///
    /// Nothing else. Stripping city names or corporate suffixes would merge
    /// shops that are genuinely different branches with genuinely different
    /// budgets, and a wrong merge is invisible: it shows up as a tagger that is
    /// confidently wrong about a merchant you never actually settled.
    init(normalizing merchantRaw: String) {
        let words = merchantRaw.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .compactMap { token -> String? in
                let core = String(token.filter { $0.isLetter || $0.isNumber || $0 == "-" })
                guard !core.isEmpty, !Self.isReference(core) else { return nil }
                let kept = core.filter { $0.isLetter || $0.isNumber }
                return kept.isEmpty ? nil : kept
            }
        self.init(rawValue: words.joined(separator: " "))
    }

    /// A booking id, not a name. Deliberately narrow — a rule that fires on a
    /// real merchant is much worse than one that misses a reference, because a
    /// dropped word silently merges two shops while a kept one only splits one
    /// shop into two keys that each accrue honestly.
    ///
    /// `a-9mvbrdugw7gdav` matches on the first clause; `7eleven` matches
    /// neither, which is the case that ruled out "mixes letters and digits" on
    /// its own.
    private static func isReference(_ token: String) -> Bool {
        let hasLetter = token.contains { $0.isLetter }
        let digits = token.filter { $0.isNumber }.count
        if token.contains("-"), hasLetter, digits > 0 { return true }
        return token.count >= 8 && digits * 2 >= token.count
    }
}

nonisolated struct Merchant: Sendable, Hashable, Identifiable, Codable {
    let id: MerchantID
    var canonicalName: String
    /// Default bucket for this merchant. A dictionary hit categorizes without the
    /// model — this field is the whole reason the deterministic path is wide.
    var defaultCategoryID: CategoryID?
    /// Raw descriptors seen for this merchant, across rails. Grows by use.
    var knownRawForms: [String]
    /// True once a human has confirmed it. Unconfirmed entries are hints, and a
    /// hint must never settle a row on its own.
    var isConfirmed: Bool
}
