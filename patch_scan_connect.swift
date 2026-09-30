import Foundation

let file = "FTL/view/ScanBillScreen.swift"
var content = try String(contentsOfFile: file)

let searchStates = """
    @State private var isSaving = false
"""
let replaceStates = """
    @State private var isSaving = false
    @State private var isShowingTransactionPicker = false
    @State private var recentTransactions: [LedgerTransaction] = []
"""
content = content.replacingOccurrences(of: searchStates, with: replaceStates)

let searchButtons = """
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
"""
let replaceButtons = """
                                Button(action: saveToLedger) {
                                    if isSaving {
                                        ProgressView().controlSize(.small)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(FTLColor.accent, in: Capsule())
                                    } else {
                                        Text("Save as New")
                                            .font(FTLTypography.body)
                                            .foregroundStyle(.black)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(FTLColor.accent, in: Capsule())
                                    }
                                }
                                .disabled(isSaving)
                            }
                            
                            Button(action: showTransactionPicker) {
                                Text("Link to Existing Spend")
                                    .font(FTLTypography.body)
                                    .foregroundStyle(FTLColor.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(FTLColor.controlFill, in: Capsule())
                                    .overlay { Capsule().strokeBorder(FTLColor.controlBorder) }
                            }
                            .disabled(isSaving)
"""
content = content.replacingOccurrences(of: searchButtons, with: replaceButtons)

let searchFunc = """
    private func saveToLedger() {
"""
let replaceFunc = """
    private func showTransactionPicker() {
        Task {
            // Fetch recent transactions (last 30 days) to link to
            let interval = DateInterval(start: Date().addingTimeInterval(-30 * 24 * 3600), end: Date())
            if let txs = try? await environment.calc.transactions(in: interval, categoryID: nil, limit: 20) {
                await MainActor.run {
                    recentTransactions = txs
                    isShowingTransactionPicker = true
                }
            }
        }
    }
    
    private func linkTo(transaction: LedgerTransaction) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                var updated = transaction
                // Append the scanned note to the existing note, or replace it if empty.
                let combinedNote = [editMerchant, editNotes].filter { !$0.isEmpty }.joined(separator: " - ")
                
                if let existing = updated.notes, !existing.isEmpty {
                    updated.notes = existing + " | " + combinedNote
                } else {
                    updated.notes = combinedNote
                }
                
                try await environment.ledger.update(updated)
                
                await MainActor.run {
                    isSaving = false
                    // Instead of a provisional entry, we'll just return an empty one or a placeholder to dismiss
                    // Actually, onScanned dismisses the sheet and reloads. We can just call onCancel to dismiss.
                    onCancel()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to link: \\(error.localizedDescription)"
                }
            }
        }
    }

    private func saveToLedger() {
"""
content = content.replacingOccurrences(of: searchFunc, with: replaceFunc)

let searchCover = """
        .fullScreenCover(isPresented: $isShowingCamera) {
"""
let replaceCover = """
        .sheet(isPresented: $isShowingTransactionPicker) {
            NavigationStack {
                List(recentTransactions) { tx in
                    Button(action: {
                        isShowingTransactionPicker = false
                        linkTo(transaction: tx)
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tx.merchant ?? tx.merchantRaw)
                                    .font(FTLTypography.body)
                                    .foregroundStyle(FTLColor.textPrimary)
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(FTLTypography.captionSmall)
                                    .foregroundStyle(FTLColor.textSecondary)
                            }
                            Spacer()
                            Text(MoneyFormatter.rp(tx.amount))
                                .font(FTLTypography.body)
                                .foregroundStyle(FTLColor.textPrimary)
                        }
                    }
                }
                .navigationTitle("Select Spending")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isShowingTransactionPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
"""
content = content.replacingOccurrences(of: searchCover, with: replaceCover)

try content.write(toFile: file, atomically: true, encoding: .utf8)
