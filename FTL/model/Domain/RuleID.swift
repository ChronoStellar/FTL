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

    /// Money mail from a sender the app already reads SOMETHING from, but no
    /// active pattern or parser claimed THIS particular layout — a refund or
    /// a minority template too rare to have cleared the evidence floor yet.
    /// See `GmailRail.sync()`. Distinct from `.manualEntry`: nobody typed
    /// this in, a person still has to.
    static let unclaimed = RuleID(rawValue: "unclaimed")

    /// Classifies the origin of this rule (Pre-made Preset vs Agent Learned vs Hardcoded Swift vs Manual).
    var origin: ParserOrigin {
        PipelineDebugStub.classify(ruleID: self)
    }

    var debugBadge: String {
        origin.badgeText
    }
}
