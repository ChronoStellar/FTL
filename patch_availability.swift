import Foundation

let file = "FTL/services/Agent/Analyzer.swift"
var content = try String(contentsOfFile: file)

content = content.replacingOccurrences(of: "@available(iOS 27.0, macOS 27.0, *)\n@Generable\nstruct SpendingRecap", with: "@Generable\nstruct SpendingRecap")

try content.write(toFile: file, atomically: true, encoding: .utf8)
