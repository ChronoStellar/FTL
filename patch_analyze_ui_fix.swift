import Foundation

let file = "FTL/view/Analyze/AnalyzeView.swift"
var content = try String(contentsOfFile: file)

content = content.replacingOccurrences(of: ".font(FTLTypography.sectionTitle)", with: ".font(FTLTypography.navTitle)")

try content.write(toFile: file, atomically: true, encoding: .utf8)
