import Foundation

let file = "FTL/view/ScanBillScreen.swift"
var content = try String(contentsOfFile: file)

let searchStr = """
                // Run both in parallel
                async let billTask = scanner.scan(cgImage)
                async let textTask = ocrScanner.scanText(from: cgImage)
                
                let (bill, text) = try await (billTask, textTask)
"""

let replaceStr = """
                let text = try await ocrScanner.scanText(from: cgImage)
                let bill = try await scanner.parse(ocrText: text)
"""

content = content.replacingOccurrences(of: searchStr, with: replaceStr)

try content.write(toFile: file, atomically: true, encoding: .utf8)
