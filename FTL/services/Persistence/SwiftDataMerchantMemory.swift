//
//  SwiftDataMerchantMemory.swift
//  FTL — services/Persistence
//
//  What you call each shop. Same container as the queue, the capture log, the
//  learned patterns and the tag history — one file, five tables, one writer.
//
//  Losing this table costs less than losing `SwiftDataTagMemory`: a forgotten
//  name is one rename away from being right again, where a forgotten decision
//  history is everything the tagger learned. It still has no upstream copy —
//  the Sheet stores the name that was written, not the rule that produced it —
//  so a restore would replay every correction by hand.
//

import Foundation
import SwiftData

@ModelActor
actor SwiftDataMerchantMemory: MerchantMemory {

    func remember(_ name: String, for merchant: MerchantID) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try await forget(merchant) }

        let key = merchant.rawValue
        let existing = try modelContext.fetch(
            FetchDescriptor<MerchantNameRecord>(predicate: #Predicate { $0.merchantKey == key })
        )
        if let record = existing.first {
            record.name = trimmed
            record.decidedAt = .now
        } else {
            modelContext.insert(MerchantNameRecord(merchantKey: key, name: trimmed))
        }
        try modelContext.save()
    }

    func forget(_ merchant: MerchantID) async throws {
        let key = merchant.rawValue
        let existing = try modelContext.fetch(
            FetchDescriptor<MerchantNameRecord>(predicate: #Predicate { $0.merchantKey == key })
        )
        for record in existing { modelContext.delete(record) }
        try modelContext.save()
    }

    func names(for merchants: [MerchantID]) async throws -> [MerchantID: String] {
        guard !merchants.isEmpty else { return [:] }
        let wanted = Set(merchants.map(\.rawValue))
        let rows = try modelContext.fetch(
            FetchDescriptor<MerchantNameRecord>(predicate: #Predicate { wanted.contains($0.merchantKey) })
        )
        return Dictionary(
            rows.map { (MerchantID(rawValue: $0.merchantKey), $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
