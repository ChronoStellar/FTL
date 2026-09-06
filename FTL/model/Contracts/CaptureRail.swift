//
//  CaptureRail.swift
//  FTL — model/Contracts · Phase 1
//
//  A source of raw documents. Rails are dumb on purpose: fetch, hand back, record
//  a resume point. No parsing, no judgment, no model.
//
//  Implementations: services/Capture/{GmailRail, StatementRail, PhotoRail}
//

import Foundation

nonisolated protocol CaptureRail: Sendable {
    var source: CaptureSource { get }

    /// Fetch everything new since `cursor`. Passing nil means "from the beginning
    /// of the configured window" — this is also the backfill path, which in v0.6 is
    /// just a capture over a larger window, not a separate role.
    ///
    /// Must be safe to re-run: `CapturedDocument.externalID` lets the caller drop
    /// what it has already seen, so a partial failure costs a refetch and nothing more.
    func capture(since cursor: CaptureCursor?) async throws -> CaptureBatch
}

nonisolated struct CaptureBatch: Sendable {
    let documents: [CapturedDocument]
    /// Persist only after the batch is durably staged. A cursor advanced ahead of
    /// storage silently loses transactions, which is the one failure the user
    /// cannot see.
    let cursor: CaptureCursor
}

/// Opaque resume point — a Gmail `historyId`, a statement's last posted date, a
/// photo library change token. The rail is the only thing that interprets it.
nonisolated struct CaptureCursor: Sendable, Hashable, Codable {
    let source: CaptureSource
    let value: String
    let recordedAt: Date
}
