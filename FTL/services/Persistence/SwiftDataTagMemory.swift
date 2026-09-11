//
//  SwiftDataTagMemory.swift
//  FTL — services/Persistence
//
//  What you decided about each merchant, and how often the tagger agreed.
//
//  It lives in the same container as the provisional queue, the capture log and
//  the learned patterns — one file, four tables. Two containers over one store
//  file is two writers on one SQLite database, which is the trap
//  `AppEnvironment.shared` already exists to avoid.
//
//  Invariant 7 does not cover this table the way it covers the queue. A lost
//  provisional row costs you one re-approval and the ledger is still the Sheet;
//  a lost decision history costs the tagger everything it learned about your
//  buckets, and there is no Sheet to recover it from. It is not canonical — the
//  ledger is — but it is the one on-device table with no upstream copy, and
//  worth remembering before anything reaches for a destructive migration.
//

import Foundation
import SwiftData

@ModelActor
actor SwiftDataTagMemory: TagMemory {

    func record(_ decisions: [TagDecision]) async throws {
        guard !decisions.isEmpty else { return }
        for decision in decisions {
            let id = decision.id
            let existing = try modelContext.fetch(
                FetchDescriptor<TagDecisionRecord>(predicate: #Predicate { $0.id == id })
            )
            // Idempotent on the entry id. `ApprovalService.approve` can be
            // retried after an ambiguous Sheets write, and a retry that counted
            // as a second agreement would inflate the hit rate on exactly the
            // rows that went least smoothly.
            if let record = existing.first {
                try record.apply(decision)
            } else {
                modelContext.insert(try TagDecisionRecord(decision: decision))
            }
        }
        try modelContext.save()
    }

    func history(for keys: [TagKey]) async throws -> [TagKey: MerchantTagHistory] {
        guard !keys.isEmpty else { return [:] }
        // Fetched by MERCHANT alone — SwiftData predicates filter one column
        // at a time, not a compound (merchant, layout) pair — then narrowed
        // to the exact keys asked about below. A merchant fetch can return
        // OTHER layouts of the same merchant too (Grab's food history when
        // only its ride history was requested); returning those as an answer
        // to a question that wasn't asked would be exactly the kind of wrong
        // merge `TagKey` exists to prevent.
        let merchantKeys = Set(keys.map(\.merchant.rawValue))
        let records = try modelContext.fetch(
            FetchDescriptor<TagDecisionRecord>(predicate: #Predicate { merchantKeys.contains($0.merchantKey) })
        )
        let wanted = Set(keys)
        return Self.histories(from: records).filter { wanted.contains($0.key) }
    }

    func scoreboard() async throws -> TagScoreboard {
        let records = try modelContext.fetch(
            FetchDescriptor<TagDecisionRecord>(
                sortBy: [SortDescriptor(\.decidedAt, order: .reverse)]
            )
        )
        let byMerchant = Self.histories(from: records)
            .values
            .sorted { ($0.total, $0.merchantRaw) > ($1.total, $1.merchantRaw) }

        return TagScoreboard(
            decisions: records.count,
            suggested: records.filter(\.hadSuggestion).count,
            agreed: records.filter { $0.hadSuggestion && $0.wasCorrect }.count,
            byMerchant: byMerchant
        )
    }

    /// Folds rows into one history per merchant/layout key (`TagKey`).
    ///
    /// Counted off the mirrored columns rather than the blob: this runs over
    /// every decision ever made every time the scoreboard is opened, and
    /// decoding a JSON payload per row to read one field is the kind of cost
    /// that is invisible at fifty rows and a freeze at five thousand.
    private static func histories(from records: [TagDecisionRecord]) -> [TagKey: MerchantTagHistory] {
        var byComposite: [String: [TagDecisionRecord]] = [:]
        for record in records { byComposite[record.compositeKey, default: []].append(record) }

        return byComposite.reduce(into: [:]) { result, pair in
            let (_, rows) = pair
            var choices: [CategoryID: Int] = [:]
            var nonSpend = 0
            for row in rows {
                if row.chosenCategory.isEmpty {
                    nonSpend += 1
                } else {
                    choices[CategoryID(rawValue: row.chosenCategory), default: 0] += 1
                }
            }
            // All rows in this group share one composite key, so any of them
            // names it — `first` rather than re-deriving it from the string.
            let key = TagKey(merchant: MerchantID(rawValue: rows[0].merchantKey), layout: rows[0].layoutKey)
            // The most recent spelling, so the scoreboard shows a name a person
            // recognises rather than the flattened key. One blob decoded per
            // key, not per decision.
            let latest = rows.max { $0.decidedAt < $1.decidedAt }
            result[key] = MerchantTagHistory(
                key: key,
                merchantRaw: (try? latest?.decision().merchantRaw) ?? rows[0].merchantKey,
                choices: choices,
                nonSpendCount: nonSpend,
                suggested: rows.filter(\.hadSuggestion).count,
                agreed: rows.filter { $0.hadSuggestion && $0.wasCorrect }.count
            )
        }
    }
}
