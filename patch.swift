import Foundation

let file = "FTL/services/Agent/FoundationModelScanner.swift"
var content = try String(contentsOfFile: file)
content = content.replacingOccurrences(of: "@Generable", with: "@available(iOS 27.0, macOS 27.0, *)\n@Generable")
try content.write(toFile: file, atomically: true, encoding: .utf8)
