//
//  BudgetStore.swift
//  FTL — model/Contracts · Phase 1
//
//  The target tree the user sets. Ceilings are user input, never suggested,
//  never adjusted by the app — Invariant 8 starts here.
//
//  Implementation: services/Ledger/SheetsBudgetStore
//

import Foundation

nonisolated protocol BudgetStore: Sendable {
    /// Root nodes for a period. Ceilings can differ month to month.
    func tree(for interval: DateInterval) async throws -> [BudgetNode]

    func setCeiling(_ amount: Money, for categoryID: CategoryID, in interval: DateInterval) async throws

    func addCategory(_ category: SpendCategory, under parentID: CategoryID?) async throws
}
