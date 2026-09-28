import Foundation

let file = "FTL/view/ScanBillScreen.swift"
var content = try String(contentsOfFile: file)

// Add state var
let stateVarSearch = "@State private var scannedResult: ScannedBill?\n"
content = content.replacingOccurrences(of: stateVarSearch, with: stateVarSearch + "    @State private var ocrResult: String?\n")

// Add UI for OCR
let uiSearch = """
                    .padding()
                    .background(FTLColor.glassFill, in: RoundedRectangle(cornerRadius: FTLRadius.card))
"""
let newUI = """
                    .padding()
                    .background(FTLColor.glassFill, in: RoundedRectangle(cornerRadius: FTLRadius.card))
                    
                    if let ocrText = ocrResult {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Raw OCR (Vision Framework)").font(FTLTypography.rowTitle)
                            ScrollView {
                                Text(ocrText)
                                    .font(FTLTypography.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 150)
                            .padding(8)
                            .background(FTLColor.controlFill, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
"""
content = content.replacingOccurrences(of: uiSearch, with: newUI)

// Clear OCR state on image selection
content = content.replacingOccurrences(of: "scannedResult = nil\n                    }", with: "scannedResult = nil\n                        ocrResult = nil\n                    }")

// Clear OCR state in scan another
content = content.replacingOccurrences(of: "scannedResult = nil }", with: "scannedResult = nil; ocrResult = nil }")

// Add OCR logic in scan()
let scanLogicSearch = """
        Task {
            do {
                let scanner = FoundationModelScanner()
                if let bill = try await scanner.scan(cgImage) {
                    await MainActor.run {
                        isScanning = false
                        scannedResult = bill
                    }
                } else {
"""
let newScanLogic = """
        Task {
            do {
                let scanner = FoundationModelScanner()
                let ocrScanner = OCRScanner()
                
                // Run both in parallel
                async let billTask = scanner.scan(cgImage)
                async let textTask = ocrScanner.scanText(from: cgImage)
                
                let (bill, text) = try await (billTask, textTask)
                
                if let bill = bill {
                    await MainActor.run {
                        isScanning = false
                        scannedResult = bill
                        ocrResult = text
                    }
                } else {
"""
content = content.replacingOccurrences(of: scanLogicSearch, with: newScanLogic)

try content.write(toFile: file, atomically: true, encoding: .utf8)
