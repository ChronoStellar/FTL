import Foundation

let file = "FTL/services/Agent/FoundationModelScanner.swift"
var content = try String(contentsOfFile: file)

let search = """
    @Guide(description: "The date on the receipt in yyyy-MM-dd format, if present.")
    var date: String?
}
"""
let replace = """
    @Guide(description: "The date on the receipt in yyyy-MM-dd format, if present.")
    var date: String?
    
    @Guide(description: "The most likely spending category (e.g., food, transport, shopping, utilities) in lowercase.")
    var category: String?
}
"""
content = content.replacingOccurrences(of: search, with: replace)

let searchInst = """
    Given raw OCR text from a receipt, extract the exact merchant name, the total final amount, and the date.
"""
let replaceInst = """
    Given raw OCR text from a receipt, extract the exact merchant name, the total final amount, the date, and infer the most likely category.
"""
content = content.replacingOccurrences(of: searchInst, with: replaceInst)

try content.write(toFile: file, atomically: true, encoding: .utf8)
