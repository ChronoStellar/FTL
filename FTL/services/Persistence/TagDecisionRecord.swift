//
//  TagDecisionRecord.swift
//  FTL — services/Persistence
//
//  One settled queue row, kept forever.
//
//  Same split as `ProvisionalEntryRecord`: the handful of columns anything
//  queries or groups by are real columns, and the rest round-trips through a
//  JSON blob so a field added to `TagDecision` doesn't need a SwiftData
//  migration to keep compiling.
//
//  Unlike the provisional queue, nothing here is ever deleted or superseded.
//  This table IS the accuracy record — the evidence Invariant 10 says the third
//  rung has to be earned against — and a table that forgets the decisions that
//  went badly would report a hit rate that only ever goes up.
//

import Foundation
import SwiftData

@Model
final class TagDecisionRecord {
    /// The provisional entry that was settled. Unique, so a retried promotion
    /// updates one row rather than counting as a second agreement.
    @Attribute(.unique) var id: UUID

    /// Queried and grouped on: the whole point of the table is "what did you
    /// decide about THIS merchant", and per-merchant scope is what makes the
    /// evidence honest (Invariant 10 — auto is never a global switch).
    var merchantKey: String
    var decidedAt: Date

    /// Mirrored so a scoreboard can count without decoding every blob.
    /// `chosenCategory` is empty for a row settled as non-spend, which is a real
    /// answer and not a missing value — see `TagDecision.chosen`.
    var chosenCategory: String
    var suggestedCategory: String?
    var hadSuggestion: Bool
    var wasCorrect: Bool

    var payload: Data

    init(decision: TagDecision) throws {
        self.id = decision.id
        self.merchantKey = decision.merchant.rawValue
        self.decidedAt = decision.decidedAt
        self.chosenCategory = decision.chosen?.rawValue ?? ""
        self.suggestedCategory = decision.suggested?.categoryID.rawValue
        self.hadSuggestion = decision.suggested != nil
        self.wasCorrect = decision.wasCorrect ?? false
        self.payload = try JSONEncoder().encode(decision)
    }

    func decision() throws -> TagDecision {
        try JSONDecoder().decode(TagDecision.self, from: payload)
    }

    func apply(_ decision: TagDecision) throws {
        self.merchantKey = decision.merchant.rawValue
        self.decidedAt = decision.decidedAt
        self.chosenCategory = decision.chosen?.rawValue ?? ""
        self.suggestedCategory = decision.suggested?.categoryID.rawValue
        self.hadSuggestion = decision.suggested != nil
        self.wasCorrect = decision.wasCorrect ?? false
        self.payload = try JSONEncoder().encode(decision)
    }
}
