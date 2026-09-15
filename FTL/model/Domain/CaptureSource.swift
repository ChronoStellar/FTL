//
//  CaptureSource.swift
//  FTL — model/Domain
//
//  The three rails, plus manual entry. Priority reflects data quality and effort,
//  not importance: email is rich but partial, statement is complete but sparse,
//  photo covers the cash residue neither sees.
//

import Foundation

nonisolated enum CaptureSource: String, Sendable, Hashable, Codable, CaseIterable {
    case email      // P1 — Gmail, itemized
    case statement  // P2 — card/bank/e-wallet, complete
    case photo      // P3 — cash residue
    case manual     // the user typed it

    /// Lower is higher priority. Manual outranks everything: the user is right.
    var priority: Int {
        switch self {
        case .manual: return 0
        case .email: return 1
        case .statement: return 2
        case .photo: return 3
        }
    }
}

