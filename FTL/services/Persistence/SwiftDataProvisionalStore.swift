//
//  SwiftDataProvisionalStore.swift
//  FTL — services/Persistence
//
//  The on-device cache, durable across relaunches. Stage 0 #1 from ROADMAP.md —
//  replaces InMemoryProvisionalStore in `AppEnvironment.live()`. Storage shape:
//  ProvisionalEntryRecord.
//
//  @ModelActor gives this its own serial executor over one ModelContext, so
//  every method below already runs off the main actor without an extra actor
//  hop — the same "services do I/O, off the main actor" rule SheetsLedgerStore
//  follows.
//
//  Deliberately NOT `@Query` anywhere: per CLAUDE.md's MVVM rules a view never
//  imports anything from services/, and `@Query` is a live SwiftData read wired
//  straight into a View. This store is reached the same way SheetsLedgerStore
//  is — through the `ProvisionalStore` protocol, injected into a view model.
//

import Foundation
import SwiftData

@ModelActor
actor SwiftDataProvisionalStore: ProvisionalStore {

    func insert(_ entries: [ProvisionalEntry]) async throws {
        for entry in entries {
            modelContext.insert(try ProvisionalEntryRecord(entry: entry))
        }
        try modelContext.save()
    }

    /// Newest first, per the protocol's documented contract.
    func pending() async throws -> [ProvisionalEntry] {
        try await entries(withStatus: .pending)
    }

    func entries(withStatus status: ProvisionalEntry.Status) async throws -> [ProvisionalEntry] {
        let raw = status.rawValue
        let descriptor = FetchDescriptor<ProvisionalEntryRecord>(
            predicate: #Predicate { $0.statusRaw == raw },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { try $0.entry() }
    }

    /// Narrows to the same currency in the fetch (indexed, cheap), then filters
    /// on the bucket pair in Swift. `#Predicate` can express `array.contains` on
    /// a single scalar field but not "this AND that together, for any pair in a
    /// list" — and the cache is small enough that filtering the currency-matched
    /// slice in memory is simpler than fighting the macro for a query plan that
    /// wouldn't meaningfully outperform it here.
    func candidates(matching fingerprint: Fingerprint) async throws -> [ProvisionalEntry] {
        let currency = fingerprint.currency.rawValue
        let descriptor = FetchDescriptor<ProvisionalEntryRecord>(
            predicate: #Predicate { $0.currencyRaw == currency }
        )
        let buckets = Set([fingerprint] + fingerprint.adjacent).map { BucketKey(amount: $0.amountBucket, date: $0.dateBucket) }
        let bucketSet = Set(buckets)
        return try modelContext.fetch(descriptor)
            .filter { bucketSet.contains(BucketKey(amount: $0.amountBucket, date: $0.dateBucket)) }
            .map { try $0.entry() }
    }

    /// No-op if `entry.id` isn't in the store — same parity as
    /// InMemoryProvisionalStore. Every caller (ApprovalQueueViewModel,
    /// DefaultApprovalService) only ever updates an entry it just read back from
    /// `pending()`, so a miss here would mean the row vanished between the read
    /// and the write, which is worth investigating rather than silently upserting
    /// a row nobody asked to create.
    func update(_ entry: ProvisionalEntry) async throws {
        let id = entry.id
        let descriptor = FetchDescriptor<ProvisionalEntryRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try modelContext.fetch(descriptor).first else { return }
        try record.apply(entry)
        try modelContext.save()
    }

    /// Called by ApprovalService only, after the ledger write succeeds — see the
    /// protocol doc on ordering. `#Predicate`'s `array.contains($0.field)` form
    /// is the well-supported case (unlike the pair-matching above), so this one
    /// stays a single query.
    func markPromoted(_ ids: [ProvisionalEntry.ID]) async throws {
        let descriptor = FetchDescriptor<ProvisionalEntryRecord>(predicate: #Predicate { ids.contains($0.id) })
        for record in try modelContext.fetch(descriptor) {
            record.statusRaw = ProvisionalEntry.Status.promoted.rawValue
        }
        try modelContext.save()
    }
}

/// `nonisolated` because the target defaults every type to `@MainActor`, and a
/// main-actor-isolated Hashable conformance can't be used from inside this
/// actor — a warning today, an error in Swift 6 mode.
private nonisolated struct BucketKey: Hashable {
    let amount: Int
    let date: Int
}
