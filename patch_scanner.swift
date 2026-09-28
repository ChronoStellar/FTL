import Foundation

let file = "FTL/services/Agent/FoundationModelScanner.swift"
var content = try String(contentsOfFile: file)

content = content.replacingOccurrences(of: "    func scan(_ cgImage: CGImage) async throws -> ScannedBill? {", with: "    func parse(ocrText: String) async throws -> ScannedBill? {")
content = content.replacingOccurrences(of: "            \"Extract the merchant name, total amount, and a short description of the purchase from this receipt.\"\n            Attachment(cgImage)", with: "            \"Extract the merchant name, total amount, and a short description of the purchase from this raw OCR text of a receipt:\"\n            ocrText")
content = content.replacingOccurrences(of: "    Given an image of a receipt, extract the exact merchant name and the total final amount.", with: "    Given raw OCR text from a receipt, extract the exact merchant name and the total final amount.")

try content.write(toFile: file, atomically: true, encoding: .utf8)
