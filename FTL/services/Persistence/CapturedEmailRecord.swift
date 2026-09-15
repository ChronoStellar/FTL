//
//  CapturedEmailRecord.swift
//  FTL — services/Persistence
//
//  One row per Gmail message the rail has already handled.
//
//  This, not a `historyId` cursor, is what makes capture idempotent. A cursor
//  says "start here" and is wrong the moment it's lost, stale, or the sync
//  window overlaps — and Gmail expires `startHistoryId` after about a week,
//  forcing a full resync exactly when you least expect it. A record of what has
//  been seen is correct under all of those: re-fetch the same message a hundred
//  times and it still produces one queue row.
//
//  `verdict` is kept for messages that produced NO entry too — a promo, or an
//  email the parser declined. Without that, every sync would re-examine the same
//  rejected mail forever.
//

import Foundation
import SwiftData

@Model
final class CapturedEmailRecord {
    /// Gmail's message id. Unique: the whole point.
    @Attribute(.unique) var messageID: String

    var seenAt: Date
    /// Raw value of `Verdict` — SwiftData stores the string, the rail reads the
    /// case.
    var verdictRaw: String
    /// The provisional entry this became, when it became one. Nil for mail that
    /// produced nothing, so a row here is not a promise that spend exists.
    var entryID: UUID?
    /// Which parser claimed it, for reports and for spotting a parser that
    /// quietly stopped matching.
    var parserID: String?

    init(messageID: String, verdict: Verdict, entryID: UUID? = nil, parserID: String? = nil, seenAt: Date = .now) {
        self.messageID = messageID
        self.verdictRaw = verdict.rawValue
        self.entryID = entryID
        self.parserID = parserID
        self.seenAt = seenAt
    }

    var verdict: Verdict { Verdict(rawValue: verdictRaw) ?? .skipped }

    nonisolated enum Verdict: String, Sendable {
        /// Parsed cleanly; `entryID` points at the queued row.
        case queued
        /// Recognised the template but a required field was missing. Still
        /// queued, but flagged — Invariant 6: escalate, never guess.
        case flagged
        /// A parser positively identified it as not a purchase.
        case notAPurchase
        /// No parser claimed it. Not an error — most mail isn't a receipt.
        case skipped
    }
}
