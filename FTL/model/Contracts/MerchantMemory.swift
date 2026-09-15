//
//  MerchantMemory.swift
//  FTL — model/Contracts
//
//  The name YOU call a shop, kept, so you only have to say it once.
//
//  Sibling of `TagMemory`, pointed at the other half of a queue row. That one
//  remembers which bucket you put a merchant in; this one remembers what you
//  call it. Before this existed a correction lasted exactly one row: renaming
//  `GRAB* A-9MVBRDUGW7GDAV` to `Grab` fixed that receipt and taught the app
//  nothing, so the next Grab receipt — with a different booking reference glued
//  on, as every one of them has — arrived just as unreadable.
//
//  KEYED ON `MerchantID` ALONE, and that is the difference from `TagKey`.
//  Tagging needs the layout in its key because one merchant name can mean
//  several kinds of purchase — Grab's ride, food and grocery arms share a name
//  and want three different buckets, so `grab` alone could never settle. A NAME
//  has no such split: `grab.com/food` and `grab.com/ride` are both called
//  "Grab" by the person reading them. Adding layout here would fragment one
//  answer across every template a merchant sends and make a settled name
//  un-settle itself.
//
//  `MerchantID(normalizing:)` is what makes one correction reach future rows at
//  all — it already folds case, punctuation and the trailing payment reference
//  that is different on every single receipt. This table is that function's
//  payoff.
//
//  Implementation: services/Persistence/SwiftDataMerchantMemory
//

import Foundation

nonisolated protocol MerchantMemory: Sendable {
    /// Remember what this merchant should be called. Replaces any earlier name
    /// — the most recent correction is the standing answer, because a person
    /// changing their mind is not evidence to be averaged.
    func remember(_ name: String, for merchant: MerchantID) async throws

    /// Drop a remembered name. Called when a correction puts a row back to what
    /// the parser produced: that is a person saying "actually, the raw was
    /// fine", and leaving the old override in place would keep overriding it.
    func forget(_ merchant: MerchantID) async throws

    /// Bulk lookup. The queue asks once per load for every merchant on screen
    /// rather than once per row — same reason `TagMemory` is read in bulk.
    func names(for merchants: [MerchantID]) async throws -> [MerchantID: String]
}
