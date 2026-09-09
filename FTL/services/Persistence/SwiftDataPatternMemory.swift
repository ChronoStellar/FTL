//
//  SwiftDataPatternMemory.swift
//  FTL — services/Persistence
//
//  The queue's verdict on every row a learned pattern produced.
//
//  Fifth table in the one container. Like `SwiftDataTagMemory` it has no
//  upstream copy — the ledger re-reads from the Sheet and the queue can be
//  re-approved, but this is the only record of how a pattern has actually been
//  doing since it was promoted.
//

import Foundation
import SwiftData

@ModelActor
actor SwiftDataPatternMemory: PatternMemory {

    func record(_ observations: [PatternObservation]) async throws {
        guard !observations.isEmpty else { return }
        for observation in observations {
            let id = observation.id
            let existing = try modelContext.fetch(
                FetchDescriptor<PatternObservationRecord>(predicate: #Predicate { $0.id == id })
            )
            if let record = existing.first {
                try record.apply(observation)
            } else {
                modelContext.insert(try PatternObservationRecord(observation: observation))
            }
        }
        try modelContext.save()
    }

    func records(for patternIDs: [String]) async throws -> [String: PatternRecord] {
        guard !patternIDs.isEmpty else { return [:] }
        let wanted = Set(patternIDs)
        let rows = try modelContext.fetch(
            FetchDescriptor<PatternObservationRecord>(predicate: #Predicate { wanted.contains($0.patternID) })
        )
        return Self.fold(rows)
    }

    func scoreboard() async throws -> PatternScoreboard {
        let rows = try modelContext.fetch(FetchDescriptor<PatternObservationRecord>())
        return PatternScoreboard(
            byPattern: Self.fold(rows).values.sorted { $0.settled > $1.settled }
        )
    }

    /// Counted off the mirrored `verdictRaw` column, never by decoding the
    /// blob: this runs over every observation ever made each time the
    /// scoreboard opens, and a JSON decode per row to read one field is the
    /// cost that is invisible at fifty rows and a freeze at five thousand.
    private static func fold(_ rows: [PatternObservationRecord]) -> [String: PatternRecord] {
        var byPattern: [String: [PatternObservationRecord]] = [:]
        for row in rows { byPattern[row.patternID, default: []].append(row) }
        return byPattern.mapValues { group in
            PatternRecord(
                patternID: group[0].patternID,
                accepted: group.filter { $0.verdict == .accepted }.count,
                correctedKind: group.filter { $0.verdict == .correctedKind }.count,
                dropped: group.filter { $0.verdict == .dropped }.count
            )
        }
    }
}
