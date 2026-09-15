//
//  PatternObservationRecord.swift
//  FTL — services/Persistence
//
//  One settled queue row, attributed to the learned pattern that produced it.
//
//  Same split as the other records: the columns anything groups by are real
//  columns, the rest round-trips through a JSON blob. Nothing here is ever
//  deleted — this table is the accuracy record for tool 1, and a table that
//  forgets the rows that went badly reports a number that only goes up.
//

import Foundation
import SwiftData

@Model
final class PatternObservationRecord {
    /// The provisional entry that was settled. Unique, so a retried promotion
    /// updates one row rather than counting as a second vote.
    @Attribute(.unique) var id: UUID

    /// `ExtractionPattern.id` — sender, layout AND version. Grouped on, and the
    /// version is part of it deliberately: evidence for v1 must not be
    /// inherited by v2, or a regression arrives already trusted.
    var patternID: String
    var settledAt: Date
    var verdictRaw: String

    var payload: Data

    init(observation: PatternObservation) throws {
        self.id = observation.id
        self.patternID = observation.patternID
        self.settledAt = observation.settledAt
        self.verdictRaw = observation.verdict.rawValue
        self.payload = try JSONEncoder().encode(observation)
    }

    func apply(_ observation: PatternObservation) throws {
        self.patternID = observation.patternID
        self.settledAt = observation.settledAt
        self.verdictRaw = observation.verdict.rawValue
        self.payload = try JSONEncoder().encode(observation)
    }

    var verdict: PatternObservation.Verdict? {
        PatternObservation.Verdict(rawValue: verdictRaw)
    }
}
