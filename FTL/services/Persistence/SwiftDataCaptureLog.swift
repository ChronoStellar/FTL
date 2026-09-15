//
//  SwiftDataCaptureLog.swift
//  FTL — services/Persistence
//
//  What the rail has already seen. Backed by CapturedEmailRecord.
//

import Foundation
import SwiftData

/// The seam the rail depends on, so it can be driven with an in-memory fake.
nonisolated protocol CaptureLog: Sendable {
    /// Of these message ids, which have never been handled.
    func unseen(from messageIDs: [String]) async throws -> Set<String>
    func record(_ entries: [CaptureLogEntry]) async throws
    func recentlySeenCount() async throws -> Int
}

nonisolated struct CaptureLogEntry: Sendable {
    let messageID: String
    let verdict: CapturedEmailRecord.Verdict
    let entryID: UUID?
    let parserID: String?
}

@ModelActor
actor SwiftDataCaptureLog: CaptureLog {

    func unseen(from messageIDs: [String]) async throws -> Set<String> {
        guard !messageIDs.isEmpty else { return [] }
        let wanted = Set(messageIDs)
        // Fetch only the ids in play rather than the whole log — this grows by
        // one row per email, forever.
        let descriptor = FetchDescriptor<CapturedEmailRecord>(
            predicate: #Predicate { wanted.contains($0.messageID) }
        )
        let seen = Set(try modelContext.fetch(descriptor).map(\.messageID))
        return wanted.subtracting(seen)
    }

    func record(_ entries: [CaptureLogEntry]) async throws {
        guard !entries.isEmpty else { return }
        for entry in entries {
            modelContext.insert(
                CapturedEmailRecord(
                    messageID: entry.messageID,
                    verdict: entry.verdict,
                    entryID: entry.entryID,
                    parserID: entry.parserID
                )
            )
        }
        try modelContext.save()
    }

    func recentlySeenCount() async throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<CapturedEmailRecord>())
    }
}
