//
//  PatternMemory.swift
//  FTL — model/Contracts · Stage 4.5
//
//  What you did with the rows a learned pattern produced.
//
//  This is the answer to the circularity the audit put a number on. The loop's
//  verifier needs an oracle; the only two available are a hand-written parser —
//  which exists exactly where the learned pattern is redundant — and
//  `labels.json`, which does not exist and is human labour by definition. On a
//  mailbox nobody has written a parser for, `verify` never runs at all:
//  `attempted == 0` for every sender, so a pattern that is 100% correct over
//  116 emails still only reaches `.provisional`, forever.
//
//  The approval queue is the one oracle an unseen mailbox generates on its own.
//  You already look at every row — that is Invariant 1 — and what you do next
//  is evidence nobody had to go and label:
//
//      approve, untouched   → the pattern read this email correctly
//      approve, kind changed → it read the DIRECTION wrong, and you fixed it
//      drop                  → you did not want this row
//
//  Same mechanism as `TagMemory`, pointed at the other tool. It also gives a
//  pattern something it has never had: a number that keeps moving.
//  `ExtractionPattern.accuracy` is stamped once at synthesis and trusted
//  forever, so a sender that changes its template next month breaks its pattern
//  with nothing anywhere noticing. Live evidence notices.
//
//  Implementation: services/Persistence/SwiftDataPatternMemory
//

import Foundation

/// One settled row, attributed to the pattern that produced it.
nonisolated struct PatternObservation: Sendable, Hashable, Codable, Identifiable {
    /// The provisional entry, so a retried promotion cannot count twice.
    let id: ProvisionalEntry.ID
    /// `ExtractionPattern.id` — sender, layout and version. Version matters:
    /// evidence for v1 says nothing about v2, and merging them would let a
    /// regression inherit the credit of the pattern it replaced.
    let patternID: String
    let verdict: Verdict
    let settledAt: Date

    nonisolated enum Verdict: String, Sendable, Hashable, Codable {
        /// Approved with the reading intact.
        case accepted
        /// Approved, but you changed spend ↔ non-spend on the way through. The
        /// amount and merchant stood; the direction did not.
        case correctedKind
        /// Dropped.
        ///
        /// Deliberately NOT called "wrong". A dropped row may be a misread, or
        /// it may be a perfectly-read email you did not want in the ledger —
        /// and from here those are indistinguishable. Counted apart from
        /// acceptance for exactly that reason.
        case dropped
    }
}

/// What the queue has said about one pattern.
nonisolated struct PatternRecord: Sendable, Hashable {
    let patternID: String
    let accepted: Int
    let correctedKind: Int
    let dropped: Int

    var settled: Int { accepted + correctedKind + dropped }

    /// Share of settled rows you kept with the reading intact.
    ///
    /// **An acceptance rate, not an accuracy.** The queue cannot currently edit
    /// an amount or a merchant, so approving a row is a vote that it looked
    /// right — not a check that it was. Reading it as accuracy would overclaim
    /// in the one direction that matters, so it is named for what it measures.
    /// The moment the queue lets a person correct a figure, this becomes the
    /// real thing and `labels.json` stops being anything anyone needs.
    var acceptanceRate: Double {
        settled == 0 ? 0 : Double(accepted) / Double(settled)
    }
}

nonisolated struct PatternScoreboard: Sendable {
    let byPattern: [PatternRecord]
    var settled: Int { byPattern.reduce(0) { $0 + $1.settled } }
}

nonisolated protocol PatternMemory: Sendable {
    /// Idempotent on `PatternObservation.id`.
    func record(_ observations: [PatternObservation]) async throws
    func records(for patternIDs: [String]) async throws -> [String: PatternRecord]
    func scoreboard() async throws -> PatternScoreboard
}

/// When live evidence is enough to stop flagging a pattern's rows.
///
/// Deliberately the same shape as `PatternSynthesisPolicy`'s promotion gate —
/// a rate and a floor, because a rate on three rows is not a measurement. The
/// floor is what stops a pattern earning trust from the first handful of rows
/// somebody approved without looking closely.
nonisolated struct PatternTrustPolicy: Sendable {
    var acceptanceThreshold = 0.95
    var minimumSettled = 20
    static let `default` = PatternTrustPolicy()

    func isVouchedFor(_ record: PatternRecord?) -> Bool {
        guard let record else { return false }
        return record.settled >= minimumSettled && record.acceptanceRate >= acceptanceThreshold
    }

    /// Which of these pattern ids the queue has vouched for, right now.
    ///
    /// One shared answer to "is this pattern vouched", not two — `GmailRail`
    /// asks it at capture time (to decide whether a NEW row needs
    /// `unverifiedPattern`) and `ApprovalQueueViewModel` asks it on every
    /// queue load (to decide whether an ALREADY-QUEUED row's flag is stale —
    /// see its `reviseUnverifiedFlags`). Trust is a live, reversible number;
    /// a second definition of "vouched" living in each caller is exactly how
    /// those two would silently drift apart.
    static func vouched(among patternIDs: [String], using trust: (any PatternMemory)?) async -> Set<String> {
        guard let trust, !patternIDs.isEmpty,
              let records = try? await trust.records(for: patternIDs)
        else { return [] }
        let policy = PatternTrustPolicy.default
        return Set(records.filter { policy.isVouchedFor($0.value) }.keys)
    }
}
