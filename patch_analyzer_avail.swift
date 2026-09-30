import Foundation

let file = "FTL/services/Agent/Analyzer.swift"
var content = try String(contentsOfFile: file)

content = content.replacingOccurrences(of: "@available(iOS 27.0, macOS 27.0, *)\nnonisolated struct FoundationModelAnalyzer", with: "nonisolated struct FoundationModelAnalyzer")
content = content.replacingOccurrences(of: "@Generable\nstruct SpendingRecap", with: "public struct SpendingRecap: Sendable, Codable {\n    public var title: String\n    public var patterns: String\n    public var keyInsight: String\n    public var recommendations: String\n}\n\n@available(iOS 27.0, macOS 27.0, *)\n@Generable\nstruct GenerableSpendingRecap: Sendable {\n    @Guide(description: \"A formal title for the report (e.g. 'Financial Summary for October 2026').\")\n    var title: String\n\n    @Guide(description: \"Objective data-driven insights into spending patterns (e.g. concentration of transactions by time/merchant, standard deviation of spending).\")\n    var patterns: String\n    \n    @Guide(description: \"A strictly factual and objective key insight or statistical anomaly found in the data.\")\n    var keyInsight: String\n\n    @Guide(description: \"Clinical, actionable recommendations on budget allocation based strictly on the numerical data.\")\n    var recommendations: String\n}")

try content.write(toFile: file, atomically: true, encoding: .utf8)
