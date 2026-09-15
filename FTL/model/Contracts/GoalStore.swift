//
//  GoalStore.swift
//  FTL — model/Contracts · Phase 1
//
//  ⚠️ Not in the v0.6 spec — see SavingsGoal for the scope note.
//
//  Implementation: services/Ledger/SheetsGoalStore (a `goals` tab), or dropped
//  entirely if the feature doesn't survive review.
//

import Foundation

nonisolated protocol GoalStore: Sendable {
    func goal() async throws -> SavingsGoal?
    func save(_ goal: SavingsGoal) async throws
}
