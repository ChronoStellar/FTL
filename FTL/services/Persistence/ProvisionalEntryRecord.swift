//
//  ProvisionalEntryRecord.swift
//  FTL — services/Persistence
//
//  The SwiftData row. `ProvisionalEntry` itself stays the domain type everywhere
//  else in the app — this is only the storage shape, the same split SheetsSchema
//  draws for the ledger: a handful of columns need to be queried or sorted
//  (status, createdAt, the fingerprint buckets `candidates(matching:)` filters
//  on), everything else round-trips through one JSON blob so a field added to
//  `ProvisionalEntry` doesn't need a matching SwiftData migration to keep
//  compiling.
//
//  Invariant 7: nothing in this store is canonical. A migration that lost this
//  table would be a bad afternoon (re-approve what's in the queue), not a
//  corrupted ledger — the Sheet is still the source of truth. That is what makes
//  "denormalize into a blob" an acceptable trade here and not on SheetsSchema.
//

import Foundation
import SwiftData

@Model
final class ProvisionalEntryRecord {
    @Attribute(.unique) var id: UUID

    // Queried directly: ApprovalQueueViewModel filters/sorts on these, and
    // candidates(matching:) blocks on the fingerprint buckets.
    var statusRaw: String
    var createdAt: Date
    var amountBucket: Int
    var dateBucket: Int
    var currencyRaw: String

    // Everything else — transaction, resolution, provenance, flags — round-trips
    // through this. Decoded back into ProvisionalEntry by the store, never read
    // as JSON by anything else.
    var payload: Data

    init(entry: ProvisionalEntry) throws {
        self.id = entry.id
        self.statusRaw = entry.status.rawValue
        self.createdAt = entry.createdAt
        self.amountBucket = entry.transaction.fingerprint.amountBucket
        self.dateBucket = entry.transaction.fingerprint.dateBucket
        self.currencyRaw = entry.transaction.fingerprint.currency.rawValue
        self.payload = try JSONEncoder().encode(entry)
    }

    /// Re-derives the domain value. Failure here means the payload predates a
    /// breaking schema change — surfaced to the caller rather than silently
    /// dropping a row the user is waiting to approve (Invariant 7's whole point
    /// is that these rows are recoverable; losing one silently defeats that).
    func entry() throws -> ProvisionalEntry {
        try JSONDecoder().decode(ProvisionalEntry.self, from: payload)
    }

    /// Re-syncs every mirrored column from a changed domain value. `update(_:)`
    /// can in principle change anything on `ProvisionalEntry` — status most
    /// often, but nothing stops a caller correcting the resolved transaction too
    /// — so every column is re-derived, not just the one the caller meant to
    /// touch.
    func apply(_ entry: ProvisionalEntry) throws {
        self.statusRaw = entry.status.rawValue
        self.createdAt = entry.createdAt
        self.amountBucket = entry.transaction.fingerprint.amountBucket
        self.dateBucket = entry.transaction.fingerprint.dateBucket
        self.currencyRaw = entry.transaction.fingerprint.currency.rawValue
        self.payload = try JSONEncoder().encode(entry)
    }
}
