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

    func history(for merchants: [MerchantID]) async throws -> [MerchantID: MerchantTagHistory] {
        guard !merchants.isEmpty else { return [:] }
        let keys = Set(merchants.map(\.rawValue))
        let records = try modelContext.fetch(
            FetchDescriptor<TagDecisionRecord>(predicate: #Predicate { keys.contains($0.merchantKey) })
        )
        return Self.histories(from: records)
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

    /// Folds rows into one history per merchant.
    ///
    /// Counted off the mirrored columns rather than the blob: this runs over
    /// every decision ever made every time the scoreboard is opened, and
    /// decoding a JSON payload per row to read one field is the kind of cost
    /// that is invisible at fifty rows and a freeze at five thousand.
    private static func histories(from records: [TagDecisionRecord]) -> [MerchantID: MerchantTagHistory] {
        var byKey: [String: [TagDecisionRecord]] = [:]
        for record in records { byKey[record.merchantKey, default: []].append(record) }

        return byKey.reduce(into: [:]) { result, pair in
            let (key, rows) = pair
            var choices: [CategoryID: Int] = [:]
            var nonSpend = 0
            for row in rows {
                if row.chosenCategory.isEmpty {
                    nonSpend += 1
                } else {
                    choices[CategoryID(rawValue: row.chosenCategory), default: 0] += 1
                }
            }
            let merchant = MerchantID(rawValue: key)
            // The most recent spelling, so the scoreboard shows a name a person
            // recognises rather than the flattened key. One blob decoded per
            // merchant, not per decision.
            let latest = rows.max { $0.decidedAt < $1.decidedAt }
            result[merchant] = MerchantTagHistory(
                merchant: merchant,
                merchantRaw: (try? latest?.decision().merchantRaw) ?? key,
                choices: choices,
                nonSpendCount: nonSpend,
                suggested: rows.filter(\.hadSuggestion).count,
                agreed: rows.filter { $0.hadSuggestion && $0.wasCorrect }.count
            )
        }
    }
}
