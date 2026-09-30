import Foundation

let file = "FTL/services/Agent/FoundationModelScanner.swift"
var content = try String(contentsOfFile: file)

let search = """
    @Guide(description: "A short sentence describing what this bill was for, if apparent.")
    var notes: String
}
"""
let replace = """
    @Guide(description: "A short sentence describing what this bill was for, if apparent.")
    var notes: String
    
    @Guide(description: "The date on the receipt in yyyy-MM-dd format, if present.")
    var date: String?
}
"""
content = content.replacingOccurrences(of: search, with: replace)

let searchInst = """
    Given raw OCR text from a receipt, extract the exact merchant name and the total final amount.
"""
let replaceInst = """
    Given raw OCR text from a receipt, extract the exact merchant name, the total final amount, and the date.
"""
content = content.replacingOccurrences(of: searchInst, with: replaceInst)

try content.write(toFile: file, atomically: true, encoding: .utf8)
