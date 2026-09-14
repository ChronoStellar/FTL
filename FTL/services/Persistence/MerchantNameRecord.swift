//
//  MerchantNameRecord.swift
//  FTL — services/Persistence
//
//  One merchant, one name you chose.
//
//  No JSON blob and no history, unlike `TagDecisionRecord` next to it. That
//  table is an accuracy record and must never forget a decision that went badly;
//  this one is a preference, and the only question it answers is "what does this
//  person call this shop **now**". One row per merchant, overwritten.
//

import Foundation
import SwiftData

@Model
final class MerchantNameRecord {
    /// `MerchantID.rawValue` — already normalized (case, punctuation, trailing
    /// payment reference), which is what lets one correction match every future
    /// receipt from the same shop.
    @Attribute(.unique) var merchantKey: String
    var name: String
    var decidedAt: Date

    init(merchantKey: String, name: String, decidedAt: Date = .now) {
        self.merchantKey = merchantKey
        self.name = name
        self.decidedAt = decidedAt
    }
}
