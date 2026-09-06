//
//  ReviewFlag.swift
//  FTL — model/Domain
//
//  Invariant 6: escalate by flagging, never by asking and never by blocking.
//  A flag is how any layer — rule, model, or importer — says "a human should look"
//  without stopping the batch or opening a dialog.
//

import Foundation

nonisolated struct ReviewFlag: Sendable, Hashable, Codable, Identifiable {
    var id: String { "\(reason.rawValue):\(detail ?? "")" }

    let reason: Reason
    /// Short, factual, and never a question — Invariant 6. "Two charges 2 days
    /// apart, same amount", not "Is this a duplicate?".
    let detail: String?

    nonisolated enum Reason: String, Sendable, Hashable, Codable, CaseIterable {
        case possibleDuplicate
        case unknownMerchant
        case ambiguousKind        // spend vs non-spend unclear
        case needsSplit           // mixed receipt spanning buckets
        case orphan               // statement line with no matching receipt
        case unparseable
        case languageUnsupported  // LanguageGate refused — see feasibility report
        case largeAmount          // statement lines can't split; flag if material

        /// What the user reads. Stated as an observation, never as a question and
        /// never as an instruction — the flag says what was noticed, the person
        /// decides what it means.
        var label: String {
            switch self {
            case .possibleDuplicate: return "Possible duplicate"
            case .unknownMerchant: return "New merchant"
            case .ambiguousKind: return "Spend unclear"
            case .needsSplit: return "Spans buckets"
            case .orphan: return "No receipt"
            case .unparseable: return "Couldn't read"
            case .languageUnsupported: return "Not readable on-device"
            case .largeAmount: return "Large amount"
            }
        }
    }
}
