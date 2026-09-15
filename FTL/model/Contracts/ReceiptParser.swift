//
//  ReceiptParser.swift
//  FTL — model/Contracts · Phase 1
//
//  Deterministic extraction, one parser per sender template.
//
//  This is the wide path. Your largest receipt source (blu, 116 emails) has ten
//  unique subjects and ninety-five identical ones — that is a template, and a
//  template is a regex job. The model earns its place on what has no template.
//
//  Parsers are pure: same email in, same result out, no I/O and no clock. That is
//  what makes them table-testable against a thousand real messages in milliseconds.
//

import Foundation

nonisolated protocol ReceiptParser: Sendable {
    /// Stable name, used in reports and in `ProvisionalEntry.Provenance`.
    var id: RuleID { get }

    /// Cheap and total. The registry asks every parser this before parsing.
    func canParse(_ email: CapturedEmail) -> Bool

    /// `.notApplicable` when this isn't the parser's template after all —
    /// `canParse` is a filter, not a promise.
    func parse(_ email: CapturedEmail) -> ReceiptParseResult
}

nonisolated enum ReceiptParseResult: Sendable, Hashable {
    case parsed(ParsedReceipt)
    /// Definitively not a purchase — marketing, a promo, a notification.
    case notAPurchase
    /// Recognised the template but couldn't read a required field. Becomes a
    /// flagged cache row, never a guess (Invariant 6).
    case incomplete(missing: String)
    case notApplicable
}

nonisolated struct ParsedReceipt: Sendable, Hashable {
    var date: Date
    var amount: Money
    /// Exactly as extracted, never cleaned up (Invariant 3).
    var merchantRaw: String
    var kind: TransactionKind
    var nonSpendType: NonSpendType?
    /// Anything the parser noticed but couldn't settle.
    var flags: [ReviewFlag]
}
