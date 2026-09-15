//
//  HarnessStores.swift
//  FTL — services/Evaluation
//
//  In-memory versions of the three stores that only exist as SwiftData.
//
//  A harness run must not touch the real container — the approval queue, the
//  learned patterns and both memories are the app's actual state, and a test
//  that writes into them is a test that changes what it measures. Same
//  protocols, so nothing upstream can tell.
//

import Foundation

/// A `PatternStore` a run can write to, unlike `FixedPatternStore`.
actor MutablePatternStore: PatternStore {
    private var stored: [String: ExtractionPattern] = [:]
    private var revoked: Set<String> = []

    init(_ initial: [ExtractionPattern] = []) {
        for pattern in initial { stored[pattern.id] = pattern }
    }

    func save(_ pattern: ExtractionPattern) async throws { stored[pattern.id] = pattern }

    /// Best per sender AND layout, highest accuracy first — the same rule
    /// `SwiftDataPatternStore` applies, so precedence behaves identically.
    func active() async throws -> [ExtractionPattern] {
        Dictionary(grouping: stored.values.filter { !revoked.contains($0.id) }) {
            [$0.senderDomain, $0.template]
        }
        .compactMapValues { $0.max { ($0.accuracy, $0.version) < ($1.accuracy, $1.version) } }
        .values
        .sorted { ($0.senderDomain, $0.template) < ($1.senderDomain, $1.template) }
    }

    func all() async throws -> [ExtractionPattern] {
        stored.values.sorted { $0.id < $1.id }
    }

    func revoke(id: String) async throws { revoked.insert(id) }
}

actor InMemoryTagMemory: TagMemory {
    private var decisions: [ProvisionalEntry.ID: TagDecision] = [:]

    func record(_ new: [TagDecision]) async throws {
        for decision in new { decisions[decision.id] = decision }
    }

    func history(for keys: [TagKey]) async throws -> [TagKey: MerchantTagHistory] {
        let wanted = Set(keys)
        var byKey: [TagKey: [TagDecision]] = [:]
        for decision in decisions.values where wanted.contains(decision.key) {
            byKey[decision.key, default: []].append(decision)
        }
        return byKey.mapValues(Self.fold)
    }

    func scoreboard() async throws -> TagScoreboard {
        var byKey: [TagKey: [TagDecision]] = [:]
        for decision in decisions.values { byKey[decision.key, default: []].append(decision) }
        let all = Array(decisions.values)
        return TagScoreboard(
            decisions: all.count,
            suggested: all.filter { $0.suggested != nil }.count,
            agreed: all.filter { $0.wasCorrect == true }.count,
            byMerchant: byKey.values.map(Self.fold).sorted { $0.total > $1.total }
        )
    }

    private static func fold(_ rows: [TagDecision]) -> MerchantTagHistory {
        var choices: [CategoryID: Int] = [:]
        var nonSpend = 0
        for row in rows {
            if let chosen = row.chosen { choices[chosen, default: 0] += 1 } else { nonSpend += 1 }
        }
        return MerchantTagHistory(
            key: rows[0].key,
            merchantRaw: rows.max { $0.decidedAt < $1.decidedAt }?.merchantRaw ?? rows[0].merchantRaw,
            choices: choices,
            nonSpendCount: nonSpend,
            suggested: rows.filter { $0.suggested != nil }.count,
            agreed: rows.filter { $0.wasCorrect == true }.count
        )
    }
}

actor InMemoryPatternMemory: PatternMemory {
    private var observations: [ProvisionalEntry.ID: PatternObservation] = [:]

    func record(_ new: [PatternObservation]) async throws {
        for observation in new { observations[observation.id] = observation }
    }

    func records(for patternIDs: [String]) async throws -> [String: PatternRecord] {
        let wanted = Set(patternIDs)
        return Self.fold(observations.values.filter { wanted.contains($0.patternID) })
    }

    func scoreboard() async throws -> PatternScoreboard {
        PatternScoreboard(byPattern: Self.fold(observations.values).values.sorted { $0.settled > $1.settled })
    }

    private static func fold(_ rows: some Collection<PatternObservation>) -> [String: PatternRecord] {
        var byPattern: [String: [PatternObservation]] = [:]
        for row in rows { byPattern[row.patternID, default: []].append(row) }
        return byPattern.mapValues {
            PatternRecord(
                patternID: $0[0].patternID,
                accepted: $0.filter { $0.verdict == .accepted }.count,
                correctedKind: $0.filter { $0.verdict == .correctedKind }.count,
                correctedAmount: $0.filter { $0.verdict == .correctedAmount }.count,
                correctedMerchant: $0.filter { $0.verdict == .correctedMerchant }.count,
                dropped: $0.filter { $0.verdict == .dropped }.count
            )
        }
    }
}
