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

// MARK: - Calc

/// Invariant 2 in miniature: this is where the arithmetic lives, and it is plain
/// Swift. When the Sheets-backed version replaces it, the sums move to formulas —
/// they never move to the model.
actor InMemoryCalcTool: CalcTool {
    private let budgets: BudgetStore
    private let store: InMemoryLedgerStore
    private let calendar = Calendar.current

    init(budgets: BudgetStore, store: InMemoryLedgerStore) {
        self.budgets = budgets
        self.store = store
    }

    private var transactions: [LedgerTransaction] {
        get async { await store.all() }
    }

    func monthSummaries(limit: Int) async throws -> [MonthSummary] {
        let rows = await transactions
        let now = Date.now
        let months: [DateInterval] = (0..<limit).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: date)
        }
        let tree = try await budgets.tree(for: calendar.dateInterval(of: .month, for: now) ?? .init(start: now, duration: 0))
        let ceiling = tree.first?.ceiling ?? .zero

        return months.map { interval in
            let spend = rows.filter { interval.containsLedgerDate($0.date) && $0.countsTowardBudget }
            let isCurrent = interval.containsLedgerDate(now)
            return MonthSummary(
                interval: interval,
                spent: Money.sum(spend.map(\.amount)),
                ceiling: ceiling,
                isCurrent: isCurrent,
                daysRemaining: isCurrent
                    ? max(0, calendar.dateComponents([.day], from: now, to: interval.end).day ?? 0)
                    : 0
            )
        }
    }

    func transactions(
        in interval: DateInterval,
        categoryID: CategoryID?,
        limit: Int
    ) async throws -> [LedgerTransaction] {
        await transactions
            .filter { interval.containsLedgerDate($0.date) }
            .filter { categoryID == nil || $0.categoryID == categoryID }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    func evaluate(_ query: LedgerQuery) async throws -> LedgerAggregate {
        let matching = await transactions.filter { tx in
            guard query.interval.containsLedgerDate(tx.date) else { return false }
            if !query.includeNonSpend && !tx.countsTowardBudget { return false }
            if let ids = query.categoryIDs, let category = tx.categoryID, !ids.contains(category) { return false }
            return true
        }
        return LedgerAggregate(
            total: Money.sum(matching.map(\.amount)),
            count: matching.count,
            groups: [:],
            interval: query.interval
        )
    }

    func budgetPositions(for interval: DateInterval) async throws -> [BudgetPosition] {
        let tree = try await budgets.tree(for: interval)
        // Invariant 5: only spend counts toward a ceiling.
        let spend = await transactions.filter { interval.containsLedgerDate($0.date) && $0.countsTowardBudget }
        return tree.map { position(for: $0, spend: spend) }
    }

    private func position(for node: BudgetNode, spend: [LedgerTransaction]) -> BudgetPosition {
        let children = node.children.map { position(for: $0, spend: spend) }

        let namedIDs = Set(node.children.map(\.id))
        let isRoot = !node.children.isEmpty
        let ownSpend = spend.filter { tx in
            guard let category = tx.categoryID else {
                // Uncategorized spend belongs to the root's total and to nothing
                // below it — that is exactly what "unallocated" means.
                return isRoot
            }
            return category == node.id || namedIDs.contains(category)
        }

        // The implicit child: anything landing on the parent rather than a named
        // bucket. Kept visible instead of folded away — mystery spend that hides
        // is the failure mode the target tree exists to prevent.
        var allChildren = children
        if !node.children.isEmpty {
            let unnamedSpend = spend.filter { $0.categoryID == nil || $0.categoryID == node.id }
            let unallocatedNode = BudgetNode(
                id: .unallocated,
                name: "Unallocated",
                ceiling: node.unallocatedCeiling,
                children: []
            )
            allChildren.append(
                BudgetPosition(
                    node: unallocatedNode,
                    actual: Money.sum(unnamedSpend.map(\.amount)),
                    children: []
                )
            )
        }

        return BudgetPosition(
            node: node,
            actual: Money.sum(ownSpend.map(\.amount)),
            children: allChildren
        )
    }
}

// MARK: - Provisional cache

actor InMemoryProvisionalStore: ProvisionalStore {
    private var entries: [ProvisionalEntry] = SampleLedger.provisionalEntries
    private var cursors: [CaptureSource: CaptureCursor] = [:]

    func insert(_ newEntries: [ProvisionalEntry]) async throws { entries.append(contentsOf: newEntries) }

    func pending() async throws -> [ProvisionalEntry] { entries.filter { $0.status == .pending } }

    func entries(withStatus status: ProvisionalEntry.Status) async throws -> [ProvisionalEntry] {
        entries.filter { $0.status == status }
    }

    func candidates(matching fingerprint: Fingerprint) async throws -> [ProvisionalEntry] {
        let buckets = Set([fingerprint] + fingerprint.adjacent)
        return entries.filter { buckets.contains($0.transaction.fingerprint) }
    }

    func hasDocument(externalID: String, source: CaptureSource) async throws -> Bool { false }

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

    func loadCursor(for source: CaptureSource) async throws -> CaptureCursor? { cursors[source] }
    func saveCursor(_ cursor: CaptureCursor) async throws { cursors[cursor.source] = cursor }
}

// MARK: - Ledger

actor InMemoryLedgerStore: LedgerStore {
    private var rows: [LedgerTransaction] = SampleLedger.transactions

    func all() -> [LedgerTransaction] { rows }

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

    func merchants() async throws -> [Merchant] { [] }
    func upsertMerchant(_ merchant: Merchant) async throws {}
    func categories() async throws -> [SpendCategory] { SampleLedger.categories }
}

// MARK: - Goal

actor InMemoryGoalStore: GoalStore {
    private var stored: SavingsGoal? = SampleLedger.goal

    func goal() async throws -> SavingsGoal? { stored }
    func save(_ goal: SavingsGoal) async throws { stored = goal }
}

// MARK: - Approvals

/// The single write path (Invariant 1). Note the ordering: append to the ledger
/// first, mark promoted only once that succeeded. A crash between the two costs a
/// retry the ledger dedups by `id`; the reverse order would lose the row.
actor InMemoryApprovalService: ApprovalService {
    private let store: ProvisionalStore
    private let ledger: LedgerStore

    init(store: ProvisionalStore, ledger: LedgerStore) {
        self.store = store
        self.ledger = ledger
    }

    func approve(_ ids: [ProvisionalEntry.ID]) async throws -> ApprovalResult {
        let pending = try await store.pending().filter { ids.contains($0.id) }
        let written = pending.map { entry in
            LedgerTransaction(
                id: entry.id,
                date: entry.transaction.date,
                amount: entry.transaction.amount,
                merchantRaw: entry.transaction.merchantRaw,
                merchant: entry.transaction.merchantRaw.capitalized,
                categoryID: entry.resolution.categoryID,
                kind: entry.resolution.kind,
                nonSpendType: entry.resolution.nonSpendType,
                source: entry.transaction.source,
                sourcesMerged: entry.resolution.mergedFrom,
                splits: entry.resolution.splits,
                lineItems: entry.transaction.lineItems,
                provenance: entry.provenance,
                flags: entry.flags,
                capturedAt: entry.createdAt,
                approvedAt: .now,
                notes: nil
            )
        }
        try await ledger.append(written)
        try await store.markPromoted(written.map(\.id))
        return ApprovalResult(written: written, failed: [])
    }

    func reject(_ ids: [ProvisionalEntry.ID]) async throws {
        for id in ids {
            guard var entry = try await store.entries(withStatus: .pending).first(where: { $0.id == id }) else { continue }
            entry.status = .rejected  // kept, never deleted — this is the accuracy record
            try await store.update(entry)
        }
    }

    func amend(_ id: ProvisionalEntry.ID, to resolution: ProvisionalEntry.Resolution) async throws {
        guard var entry = try await store.entries(withStatus: .pending).first(where: { $0.id == id }) else { return }
        entry.resolution = resolution
        entry.provenance = .manual  // a corrected row is no longer the model's verdict
        try await store.update(entry)
    }
}
