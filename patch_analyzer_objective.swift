import Foundation

let file = "FTL/services/Agent/Analyzer.swift"
var content = try String(contentsOfFile: file)

let searchStruct = """
@Generable
struct SpendingRecap: Sendable {
    @Guide(description: "A fun, catchy title for this month's recap (like 'Your October Wrapped').")
    var title: String

    @Guide(description: "Insights into spending patterns, like what time of day they spend most, or their favorite merchant.")
    var patterns: String
    
    @Guide(description: "A fun, somewhat sassy, or celebratory fact about their spending this month.")
    var funFact: String

    @Guide(description: "Actionable recommendations on how to allocate next month's budget based on this month's behavior.")
    var recommendations: String
}
"""
let replaceStruct = """
@Generable
struct SpendingRecap: Sendable {
    @Guide(description: "A formal title for the report (e.g. 'Financial Summary for October 2026').")
    var title: String

    @Guide(description: "Objective data-driven insights into spending patterns (e.g. concentration of transactions by time/merchant, standard deviation of spending).")
    var patterns: String
    
    @Guide(description: "A strictly factual and objective key insight or statistical anomaly found in the data.")
    var keyInsight: String

    @Guide(description: "Clinical, actionable recommendations on budget allocation based strictly on the numerical data.")
    var recommendations: String
}
"""
content = content.replacingOccurrences(of: searchStruct, with: replaceStruct)

let searchPrompt = """
        let prompt = Prompt {
            "You are a fun, insightful financial assistant generating a Spotify Wrapped-style recap for \\(monthName)."
            "Analyze the following transactions. Find patterns in their spending (e.g. coffee every morning, big weekend spending, top merchants)."
            "Then, provide recommendations on how they should adjust their budget for next month."
            "Keep the tone engaging, upbeat, and a little playful."
            ""
            "CRITICAL RULES:"
            "- ONLY use the transactions provided below."
            "- DO NOT invent, hallucinate, or assume any purchases, merchants, or amounts."
            "- If there are not enough transactions to form a pattern or fun fact, simply state that there isn't enough data yet, rather than making something up."
            ""
            "Transactions:"
            txStrings.isEmpty ? "(No transactions this month)" : txStrings
        }
"""
let replacePrompt = """
        let prompt = Prompt {
            "You are a strictly professional financial auditor generating an objective monthly report for \\(monthName)."
            "Analyze the following ledger transactions. Identify statistical patterns (e.g., high-frequency merchants, category concentration, volume timing)."
            "Provide dry, clinical recommendations on capital allocation for the subsequent month based solely on the observed ledger."
            "Maintain a highly objective, professional, and purely analytical tone. Avoid any conversational filler, enthusiasm, or playfulness."
            ""
            "CRITICAL RULES:"
            "- ONLY use the transactions provided below. Treat them as ground truth."
            "- DO NOT invent, hallucinate, or extrapolate any purchases, entities, or figures not strictly present."
            "- If the ledger volume is insufficient to establish statistical patterns, explicitly state 'Insufficient data for statistical analysis'."
            ""
            "Transactions:"
            txStrings.isEmpty ? "(No transactions this month)" : txStrings
        }
"""
content = content.replacingOccurrences(of: searchPrompt, with: replacePrompt)

let searchSession = """
        let session = LanguageModelSession(instructions: "You are a strict financial analysis assistant that only summarizes provided data without hallucinating.")
"""
let replaceSession = """
        let session = LanguageModelSession(instructions: "You are a professional financial auditor. You output dry, clinical, and purely objective analyses based strictly on provided numerical ledgers. You never invent data.")
"""
content = content.replacingOccurrences(of: searchSession, with: replaceSession)

try content.write(toFile: file, atomically: true, encoding: .utf8)
