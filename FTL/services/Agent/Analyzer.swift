import Foundation
import FoundationModels

public struct SpendingRecap: Sendable, Codable {
    public var title: String
    public var patterns: String
    public var keyInsight: String
    public var recommendations: String
}

@available(iOS 27.0, macOS 27.0, *)
@Generable
struct GenerableSpendingRecap: Sendable {
    @Guide(description: "A formal title for the report (e.g. 'Financial Summary for October 2026').")
    var title: String

    @Guide(description: "Objective data-driven insights into spending patterns (e.g. concentration of transactions by time/merchant, standard deviation of spending).")
    var patterns: String
    
    @Guide(description: "A strictly factual and objective key insight or statistical anomaly found in the data.")
    var keyInsight: String

    @Guide(description: "Clinical, actionable recommendations on budget allocation based strictly on the numerical data.")
    var recommendations: String
}

nonisolated struct FoundationModelAnalyzer: Sendable {
    private let options = GenerationOptions(temperature: 0.1)

    static var isAvailable: Bool {
        if #available(iOS 27.0, macOS 27.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    func analyze(transactions: [LedgerTransaction], monthName: String, budgets: [BudgetPosition]) async throws -> SpendingRecap? {
        guard Self.isAvailable else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        
        let budgetStrings = budgets.map { pos in
            let name = pos.node.name
            let allocated = pos.node.ceiling.minorUnits
            let spent = pos.actual.minorUnits
            return "\(name) - Allocated: \(allocated) | Spent: \(spent)"
        }.joined(separator: "\n")

        let txStrings = transactions.prefix(300).map { tx in
            let dateStr = formatter.string(from: tx.date)
            let catStr = tx.categoryID?.rawValue ?? "Uncategorized"
            let amtStr = "\(tx.amount.minorUnits)"
            let merchant = tx.merchant ?? tx.merchantRaw
            return "[\(dateStr)] \(merchant) - \(catStr): \(amtStr)"
        }.joined(separator: "\n")

        if #available(iOS 27.0, macOS 27.0, *) {
            let prompt = Prompt {
                "You are a strictly professional financial auditor generating an objective monthly report for \(monthName)."
                "Analyze the following ledger transactions. Identify statistical patterns (e.g., high-frequency merchants, category concentration, volume timing)."
                "Provide dry, clinical recommendations on capital allocation for the subsequent month based solely on the observed ledger."
                "Maintain a highly objective, professional, and purely analytical tone. Avoid any conversational filler, enthusiasm, or playfulness."
                ""
                "Budget Context:"
                budgetStrings
                ""
                "CRITICAL RULES:"
                "- ONLY use the transactions provided below. Treat them as ground truth."
                "- DO NOT invent, hallucinate, or extrapolate any purchases, entities, or figures not strictly present."
                "- If the ledger volume is insufficient to establish statistical patterns, explicitly state 'Insufficient data for statistical analysis'."
                ""
                "Transactions:"
                txStrings.isEmpty ? "(No transactions this month)" : txStrings
            }

            let session = LanguageModelSession(instructions: "You are a professional financial auditor. You output dry, clinical, and purely objective analyses based strictly on provided numerical ledgers. You never invent data.")
            let response = try await session.respond(
                to: prompt,
                generating: GenerableSpendingRecap.self,
                options: options
            )
            let gen = response.content
            return SpendingRecap(title: gen.title, patterns: gen.patterns, keyInsight: gen.keyInsight, recommendations: gen.recommendations)
        } else {
            return nil
        }
    }
}
