//
//  BudgetNode.swift
//  FTL — model/Domain
//
//  The target-tree: a partition of a ceiling into buckets the user defines. Not an
//  opinion, not a recommendation — a number they set, and their position against it.
//
//    Food  ≤ 3.0M
//    ├── Groceries    ≤ 1.5M
//    ├── Restaurants  ≤ 1.0M
//    ├── Delivery     ≤ 0.5M
//    └── (unallocated ≤ 0.0M)   ← implicit, = parent − Σ named children
//

import Foundation

nonisolated struct BudgetNode: Sendable, Hashable, Identifiable, Codable {
    let id: CategoryID
    var name: String
    var ceiling: Money
    var children: [BudgetNode]

    /// The implicit child. Mystery and uncategorized spend lands here so it stays
    /// visible rather than quietly disappearing from the tree. Can go negative —
    /// that is a real, reportable fact about over-partitioning, not an error.
    var unallocatedCeiling: Money {
        children.reduce(ceiling) { $0 - $1.ceiling }
    }

    var isLeaf: Bool { children.isEmpty }
}

/// A node paired with what actually happened. Produced by CalcTool — never by a
/// view model, and never by the model (Invariant 2).
nonisolated struct BudgetPosition: Sendable, Hashable, Identifiable {
    var id: CategoryID { node.id }

    let node: BudgetNode
    let actual: Money
    let children: [BudgetPosition]

    var remaining: Money { node.ceiling - actual }

    /// Reported as a flat fact. The UI states "Delivery 0.6M of 0.5M" — it does not
    /// add a verb, a warning glyph, or an alarm colour. See Invariant 8.
    var standing: Standing {
        if actual.minorUnits > node.ceiling.minorUnits { return .overCeiling }
        if actual.minorUnits == node.ceiling.minorUnits { return .atCeiling }
        return .underCeiling
    }

    nonisolated enum Standing: Sendable, Hashable {
        case underCeiling
        case atCeiling
        case overCeiling
    }
}
