//
//  RuleID.swift
//  FTL — model/Domain
//
//  Names the deterministic rule that settled a row. Outlives the rule engine
//  itself: `ProvisionalEntry.Provenance` records it so a rule-settled row and a
//  model-tagged row are never confused, in storage or on screen.
//

import Foundation

nonisolated struct RuleID: Sendable, Hashable, Codable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    /// The user typed it in.
    static let manualEntry = RuleID(rawValue: "manual-entry")
}
