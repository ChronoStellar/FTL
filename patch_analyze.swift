import Foundation

let file = "FTL/view/Analyze/AnalyzeView.swift"
var content = try String(contentsOfFile: file)

content = content.replacingOccurrences(of: ".sectionTitle", with: ".rowTitle")

try content.write(toFile: file, atomically: true, encoding: .utf8)
