import Foundation

let file = "FTL/services/Agent/Analyzer.swift"
var content = try String(contentsOfFile: file)

let searchIsAvail = """
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }
"""
let replaceIsAvail = """
    static var isAvailable: Bool {
        if #available(iOS 27.0, macOS 27.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }
"""
content = content.replacingOccurrences(of: searchIsAvail, with: replaceIsAvail)

try content.write(toFile: file, atomically: true, encoding: .utf8)
