import Foundation

let file = "FTL/services/Agent/Analyzer.swift"
var content = try String(contentsOfFile: file)

let searchTemp = """
    private let options = GenerationOptions(temperature: 0.7)
"""
let replaceTemp = """
    private let options = GenerationOptions(temperature: 0.1)
"""
content = content.replacingOccurrences(of: searchTemp, with: replaceTemp)

let searchPrompt = """
        let prompt = Prompt {
            "You are a fun, insightful financial assistant generating a Spotify Wrapped-style recap for \\(monthName)."
            "Analyze the following transactions. Find patterns in their spending (e.g. coffee every morning, big weekend spending, top merchants)."
            "Then, provide recommendations on how they should adjust their budget for next month."
            "Keep the tone engaging, upbeat, and a little playful."
            ""
            "Transactions:"
            txStrings
        }
"""
let replacePrompt = """
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
content = content.replacingOccurrences(of: searchPrompt, with: replacePrompt)

let searchInst = """
        let session = LanguageModelSession(instructions: "You are a financial analysis assistant that creates engaging summaries.")
"""
let replaceInst = """
        let session = LanguageModelSession(instructions: "You are a strict financial analysis assistant that only summarizes provided data without hallucinating.")
"""
content = content.replacingOccurrences(of: searchInst, with: replaceInst)

try content.write(toFile: file, atomically: true, encoding: .utf8)
