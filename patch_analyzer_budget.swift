import Foundation

let file = "FTL/services/Agent/Analyzer.swift"
var content = try String(contentsOfFile: file)

let searchFunc = """
    func analyze(transactions: [LedgerTransaction], monthName: String) async throws -> SpendingRecap? {
"""
let replaceFunc = """
    func analyze(transactions: [LedgerTransaction], monthName: String, budgets: [BudgetPosition]) async throws -> SpendingRecap? {
"""
content = content.replacingOccurrences(of: searchFunc, with: replaceFunc)

let searchStrings = """
        let txStrings = transactions.prefix(300).map { tx in
"""
let replaceStrings = """
        let budgetStrings = budgets.map { pos in
            let name = pos.node.name
            let allocated = pos.node.ceiling.minorUnits
            let spent = pos.actual.minorUnits
            return "\\(name) - Allocated: \\(allocated) | Spent: \\(spent)"
        }.joined(separator: "\\n")

        let txStrings = transactions.prefix(300).map { tx in
"""
content = content.replacingOccurrences(of: searchStrings, with: replaceStrings)

let searchPrompt = """
            "CRITICAL RULES:"
"""
let replacePrompt = """
            "Budget Context:"
            budgetStrings
            ""
            "CRITICAL RULES:"
"""
content = content.replacingOccurrences(of: searchPrompt, with: replacePrompt)

try content.write(toFile: file, atomically: true, encoding: .utf8)
