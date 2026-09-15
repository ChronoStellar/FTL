//
//  CapturedEmailSource.swift
//  FTL — model/Contracts
//
//  Where the rail gets its mail.
//
//  `GmailRail` used to name `GmailExporter` directly, which meant the only way
//  to run the pipeline was to run it against a live mailbox over the network,
//  once, unrepeatably. Every claim about the pipeline so far has therefore been
//  about a PIECE of it — this parser reads 112/112, that pattern covers 96% —
//  and never about the thing the pieces add up to.
//
//  One protocol fixes that. The same rail, with the same parsers, the same
//  precedence, the same dedup and the same provisional writes, can be pointed
//  at a recorded corpus and run a thousand emails through in a second, offline
//  and deterministically. What comes out the far end is the actual product:
//  rows in the approval queue.
//

import Foundation

nonisolated protocol CapturedEmailSource: Sendable {
    /// `query` is Gmail syntax. A recorded source honours what it can and says
    /// so — see `CorpusEmailSource`.
    func fetchCaptured(query: String, limit: Int) async throws -> [CapturedEmail]
}
