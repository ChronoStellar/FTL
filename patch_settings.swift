import Foundation

let file = "FTL/view/Settings/SettingsView.swift"
var content = try String(contentsOfFile: file)

content = content.replacingOccurrences(of: "            debugRow(\"Scan Receipt (Vision Model)\", .scan, showsDivider: true)\n", with: "")
content = content.replacingOccurrences(of: "case .harness, .evaluation, .scan", with: "case .harness, .evaluation")
content = content.replacingOccurrences(of: "case harness, evaluation, scan", with: "case harness, evaluation")

let scanSwitchRegex = try NSRegularExpression(pattern: "                case \\.scan:\n                    if #available.*?\n                    \\} else \\{\n                        Text\\(\"Scan feature requires iOS 27.0 or newer\\.\"\\)\n                    \\}\n", options: [.dotMatchesLineSeparators])
content = scanSwitchRegex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: "")

try content.write(toFile: file, atomically: true, encoding: .utf8)
