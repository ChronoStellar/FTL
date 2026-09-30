import Foundation

let file = "FTL/view/ScanBillScreen.swift"
var content = try String(contentsOfFile: file)

// Add edit states
let stateSearch = "@State private var ocrResult: String?\n"
let stateReplace = """
    @State private var ocrResult: String?
    
    @State private var editMerchant: String = ""
    @State private var editAmount: String = ""
    @State private var editNotes: String = ""
    @State private var isSaving = false
"""
content = content.replacingOccurrences(of: stateSearch, with: stateReplace)

// Replace the UI block for scannedResult
let uiSearchRegex = try NSRegularExpression(pattern: "                \\} else if let bill = scannedResult \\{.*?\\} else if selectedImage != nil \\{", options: [.dotMatchesLineSeparators])
let uiReplace = """
                } else if scannedResult != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Edit & Save").font(FTLTypography.rowTitle)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Merchant").font(FTLTypography.caption)
                                TextField("Merchant", text: $editMerchant)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Amount").font(FTLTypography.caption)
                                TextField("Amount", text: $editAmount)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes").font(FTLTypography.caption)
                                TextField("Notes", text: $editNotes)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            HStack(spacing: 12) {
                                Button(action: { scannedResult = nil; ocrResult = nil }) {
                                    Text("Discard")
                                        .font(FTLTypography.body)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(FTLColor.controlFill, in: Capsule())
                                }
                                
                                Button(action: saveToLedger) {
                                    if isSaving {
                                        ProgressView().controlSize(.small)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(FTLColor.accent, in: Capsule())
                                    } else {
                                        Text("Save to Ledger")
                                            .font(FTLTypography.body)
                                            .foregroundStyle(.black)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(FTLColor.accent, in: Capsule())
                                    }
                                }
                                .disabled(isSaving)
                            }
                        }
                        .padding()
                        .background(FTLColor.glassFill, in: RoundedRectangle(cornerRadius: FTLRadius.card))
                        
                        if let ocrText = ocrResult {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Raw OCR").font(FTLTypography.rowTitle)
                                Text(ocrText)
                                    .font(FTLTypography.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(FTLColor.controlFill, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(.horizontal)
                        }
                    }
                } else if selectedImage != nil {
"""
content = uiSearchRegex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: uiReplace)

// Update scan() to initialize the edit variables
let scanSearch = """
                    await MainActor.run {
                        isScanning = false
                        scannedResult = bill
                        ocrResult = text
                    }
"""
let scanReplace = """
                    await MainActor.run {
                        isScanning = false
                        scannedResult = bill
                        ocrResult = text
                        editMerchant = bill.merchant
                        editAmount = "\\(bill.amount)"
                        editNotes = bill.notes
                    }
"""
content = content.replacingOccurrences(of: scanSearch, with: scanReplace)

// Add saveToLedger function
let saveToLedgerFunc = """
    private func saveToLedger() {
        guard let amountInt = Int(editAmount) else { return }
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                let amount = Money.idr(amountInt)
                // We combine merchant and notes for the ManualEntry note since it uses the note as the merchantRaw if appropriate,
                // or we can format it nicely. ManualEntry's 'note' param maps to `merchantRaw` and `merchantID`.
                // Actually, let's just pass editMerchant if it exists, otherwise editNotes. 
                // ManualEntry parses the note parameter as merchantRaw.
                let noteParam = editMerchant.isEmpty ? editNotes : editMerchant
                // Wait, if both exist, maybe we can combine them, e.g. "Merchant - Notes"
                let combinedNote = [editMerchant, editNotes].filter { !$0.isEmpty }.joined(separator: " - ")
                
                let manual = ManualEntry(provisional: environment.provisional, approvals: environment.approvals)
                let entry = try await manual.record(
                    amount: amount,
                    categoryID: nil, // unallocated by default
                    note: combinedNote
                )
                
                await MainActor.run {
                    isSaving = false
                    onScanned(entry)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save: \\(error.localizedDescription)"
                }
            }
        }
    }
}
"""
content = content.replacingOccurrences(of: "        }\n    }\n}\n", with: "        }\n    }\n\n" + saveToLedgerFunc)

try content.write(toFile: file, atomically: true, encoding: .utf8)
