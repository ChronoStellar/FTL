//
//  SwiftDataPatternStore.swift
//  FTL — services/Persistence
//
//  What the loop has learned, and which of it is currently in force.
//

import Foundation
import SwiftData

nonisolated protocol PatternStore: Sendable {
    func save(_ pattern: ExtractionPattern) async throws
    /// The best surviving pattern per sender — what the rail should execute.
    func active() async throws -> [ExtractionPattern]
    /// Everything, revoked included, for a screen that wants to show history.
    func all() async throws -> [ExtractionPattern]
    func revoke(id: String) async throws
}

@ModelActor
actor SwiftDataPatternStore: PatternStore {

    func save(_ pattern: ExtractionPattern) async throws {
        let id = pattern.id
        let existing = try modelContext.fetch(
            FetchDescriptor<ExtractionPatternRecord>(predicate: #Predicate { $0.id == id })
        )
        // Re-running synthesis can land on the same version number. Replace that
        // row rather than failing the unique constraint — same identity, newer
        // measurement.
        for record in existing { modelContext.delete(record) }
        modelContext.insert(try ExtractionPatternRecord(pattern: pattern))
        try modelContext.save()
    }

    /// One per sender LAYOUT: highest accuracy wins, newest breaks a tie.
    ///
    /// Not "the latest version" — a later attempt can score worse, and shipping
    /// a regression because it is newer would be the loop making the app worse
    /// while looking like progress.
    ///
    /// Grouped by sender AND template, not sender alone. Grab needs two live
    /// patterns at once — one for rides, one for food orders — and grouping by
    /// sender would keep whichever scored higher and silently drop the other
    /// half of the receipts.
    func active() async throws -> [ExtractionPattern] {
        let records = try modelContext.fetch(
            FetchDescriptor<ExtractionPatternRecord>(predicate: #Predicate { $0.revokedAt == nil })
        )
        let best = Dictionary(grouping: records) { [$0.senderDomain, $0.template] }
            .compactMapValues { group in
                group.max {
                    ($0.accuracy, $0.promotedAt) < ($1.accuracy, $1.promotedAt)
                }
            }
        return try best.values
            .sorted { ($0.senderDomain, $0.template) < ($1.senderDomain, $1.template) }
            .map { try $0.pattern() }
    }

    func all() async throws -> [ExtractionPattern] {
        try modelContext.fetch(
            FetchDescriptor<ExtractionPatternRecord>(
                sortBy: [SortDescriptor(\.promotedAt, order: .reverse)]
            )
        ).map { try $0.pattern() }
    }

    func revoke(id: String) async throws {
        let records = try modelContext.fetch(
            FetchDescriptor<ExtractionPatternRecord>(predicate: #Predicate { $0.id == id })
        )
        for record in records { record.revokedAt = .now }
        try modelContext.save()
    }
}
