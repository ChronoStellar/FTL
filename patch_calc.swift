import Foundation

let file = "FTL/services/Ledger/LedgerCalcTool.swift"
var content = try String(contentsOfFile: file)

let searchPositions = """
    func budgetPositions(for interval: DateInterval) async throws -> [BudgetPosition] {
        let tree = try await budgets.tree(for: interval)
        // Invariant 5: only spend counts toward a ceiling.
        let spend = try await ledger.all().filter { interval.containsLedgerDate($0.date) && $0.countsTowardBudget }
        return tree.map { position(for: $0, spend: spend) }
    }
"""
let replacePositions = """
    func budgetPositions(for interval: DateInterval) async throws -> [BudgetPosition] {
        let tree = try await budgets.tree(for: interval)
        // Include emergency here so it can tally its own bucket, but we'll exclude it from parents in position()
        let spend = try await ledger.all().filter { interval.containsLedgerDate($0.date) && $0.kind == .spend }
        return tree.map { position(for: $0, spend: spend) }
    }
"""
content = content.replacingOccurrences(of: searchPositions, with: replacePositions)

let searchPosition = """
        let ownSpend = spend.filter { tx in
            guard let category = tx.categoryID else {
                // Uncategorized spend belongs to the root's total and to nothing
                // below it — that is exactly what "unallocated" means.
                return isRoot
            }
            return category == node.id || namedIDs.contains(category)
        }
"""
let replacePosition = """
        let ownSpend = spend.filter { tx in
            guard let category = tx.categoryID else {
                return isRoot
            }
            if category == .emergency && node.id != .emergency { return false }
            return category == node.id || namedIDs.contains(category)
        }
"""
content = content.replacingOccurrences(of: searchPosition, with: replacePosition)

try content.write(toFile: file, atomically: true, encoding: .utf8)
