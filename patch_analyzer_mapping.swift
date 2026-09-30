import Foundation

let file = "FTL/services/Agent/Analyzer.swift"
var content = try String(contentsOfFile: file)

let searchGen = """
        let session = LanguageModelSession(instructions: "You are a professional financial auditor. You output dry, clinical, and purely objective analyses based strictly on provided numerical ledgers. You never invent data.")
        let response = try await session.respond(
            to: prompt,
            generating: SpendingRecap.self,
            options: options
        )
        return response.content
"""
let replaceGen = """
        if #available(iOS 27.0, macOS 27.0, *) {
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
"""
content = content.replacingOccurrences(of: searchGen, with: replaceGen)

try content.write(toFile: file, atomically: true, encoding: .utf8)
