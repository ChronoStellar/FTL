//
//  InMemoryStores.swift
//  FTL — services/Preview
//
//  ⚠️ PLACEHOLDER IMPLEMENTATIONS — not the real thing.
//
//  These satisfy the Phase-1 contracts with hardcoded data so the UI can be built
//  and looked at before SheetsLedgerStore / GRDBProvisionalStore exist. They are
//  wired in AppEnvironment and must be swapped out there — nowhere else changes,
//  which is the point of the protocols.
//
//  Deliberately NOT gated behind #if DEBUG: they are currently the only
//  implementations, so gating them would break a Release build silently. Delete
//  this file once the real stores land.
//

import Foundation

// MARK: - Budgets

actor InMemoryBudgetStore: BudgetStore {
    private var nodes: [BudgetNode] = SampleLedger.budgetTree

    func tree(for interval: DateInterval) async throws -> [BudgetNode] { nodes }

    func setCeiling(_ amount: Money, for categoryID: CategoryID, in interval: DateInterval) async throws {
        nodes = nodes.map { setCeiling(amount, for: categoryID, in: $0) }
    }

    func addCategory(_ category: SpendCategory, under parentID: CategoryID?) async throws {
        let node = BudgetNode(id: category.id, name: category.name, ceiling: .zero, children: [])
        guard let parentID else { nodes.append(node); return }
        nodes = nodes.map { parent in
            guard parent.id == parentID else { return parent }
            var copy = parent
            copy.children.append(node)
            return copy
        }
    }

    private func setCeiling(_ amount: Money, for id: CategoryID, in node: BudgetNode) -> BudgetNode {
        var copy = node
        if copy.id == id { copy.ceiling = amount }
        copy.children = copy.children.map { setCeiling(amount, for: id, in: $0) }
        return copy
    }
}

// MARK: - Provisional cache

actor InMemoryProvisionalStore: ProvisionalStore {
    private var entries: [ProvisionalEntry] = SampleLedger.provisionalEntries

    func insert(_ newEntries: [ProvisionalEntry]) async throws { entries.append(contentsOf: newEntries) }

    func pending() async throws -> [ProvisionalEntry] { entries.filter { $0.status == .pending } }

    func entries(withStatus status: ProvisionalEntry.Status) async throws -> [ProvisionalEntry] {
        entries.filter { $0.status == status }
    }

    func candidates(matching fingerprint: Fingerprint) async throws -> [ProvisionalEntry] {
        let buckets = Set([fingerprint] + fingerprint.adjacent)
        return entries.filter { buckets.contains($0.transaction.fingerprint) }
    }


    func update(_ entry: ProvisionalEntry) async throws {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    func markPromoted(_ ids: [ProvisionalEntry.ID]) async throws {
        for id in ids {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { continue }
            entries[index].status = .promoted
        }
    }

}

// MARK: - Ledger

actor InMemoryLedgerStore: LedgerStore {
    private var rows: [LedgerTransaction] = SampleLedger.transactions

    func all() async throws -> [LedgerTransaction] { rows }

    func append(_ transactions: [LedgerTransaction]) async throws {
        // Idempotent on `id`, the same guarantee the Sheets store must give.
        let existing = Set(rows.map(\.id))
        rows.append(contentsOf: transactions.filter { !existing.contains($0.id) })
    }

    func transactions(in interval: DateInterval) async throws -> [LedgerTransaction] {
        rows.filter { interval.containsLedgerDate($0.date) }
    }

    func transaction(id: LedgerTransaction.ID) async throws -> LedgerTransaction? {
        rows.first { $0.id == id }
    }

    func categories() async throws -> [SpendCategory] { SampleLedger.categories }
}

// MARK: - Goal

actor InMemoryGoalStore: GoalStore {
    private var stored: SavingsGoal? = SampleLedger.goal

    func goal() async throws -> SavingsGoal? { stored }
    func save(_ goal: SavingsGoal) async throws { stored = goal }
}
