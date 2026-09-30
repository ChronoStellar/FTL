import SwiftUI
import PhotosUI

@available(iOS 27.0, macOS 27.0, *)
struct ScanBillScreen: View {
    let environment: AppEnvironment
    let onCancel: () -> Void
    let onScanned: (ProvisionalEntry) -> Void
    
    @State private var isShowingCamera = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var scannedResult: ScannedBill?
        @State private var ocrResult: String?
    
    @State private var editMerchant: String = ""
    @State private var editAmount: String = ""
    @State private var editNotes: String = ""
    @State private var editDate: Date = .now
    @State private var editCategory: String = ""
    @State private var isSaving = false
    @State private var isShowingTransactionPicker = false
    @State private var recentTransactions: [LedgerTransaction] = []    
    var body: some View {
        NavigationStack {
            VStack(spacing: FTLSpacing.lg) {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: FTLRadius.card))
                } else {
                    ContentUnavailableView("No Image", systemImage: "photo", description: Text("Select a receipt to scan"))
                }
                
                HStack(spacing: FTLSpacing.md) {
                    Button(action: { isShowingCamera = true }) {
                        HStack {
                            Image(systemName: "camera")
                            Text("Take Photo")
                        }
                        .font(FTLTypography.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(FTLColor.controlFill, in: Capsule())
                        .overlay { Capsule().strokeBorder(FTLColor.controlBorder) }
                    }
                    .disabled(isScanning)
                    
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo")
                            Text("Library")
                        }
                        .font(FTLTypography.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(FTLColor.controlFill, in: Capsule())
                        .overlay { Capsule().strokeBorder(FTLColor.controlBorder) }
                    }
                    .disabled(isScanning)
                }
                
                if isScanning {
                    ProgressView("Scanning...")
                        .padding()
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
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Date").font(FTLTypography.caption)
                                    DatePicker("", selection: $editDate, displayedComponents: .date)
                                        .labelsHidden()
                                }
                                Spacer()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Category").font(FTLTypography.caption)
                                    TextField("Category", text: $editCategory)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 120)
                                }
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
                    Button(action: scan) {
                        Text("Scan Receipt")
                            .font(FTLTypography.body)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FTLColor.accent, in: Capsule())
                    }
                }
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(FTLTypography.caption)
                        .foregroundStyle(.red)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Scan Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                        scannedResult = nil
                        ocrResult = nil
                    }
                }
            }
        }
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
            CameraPicker(image: $selectedImage)
                .ignoresSafeArea()
        }
        .onChange(of: selectedImage) { _, _ in
            scannedResult = nil
            ocrResult = nil
        }
    }
    
    private func scan() {
        guard let cgImage = selectedImage?.cgImage else { return }
        isScanning = true
        errorMessage = nil
        
        Task {
            do {
                let scanner = FoundationModelScanner()
                let ocrScanner = OCRScanner()
                
                let text = try await ocrScanner.scanText(from: cgImage)
                let bill = try await scanner.parse(ocrText: text)
                
                if let bill = bill {
                    await MainActor.run {
                        isScanning = false
                        scannedResult = bill
                        ocrResult = text
                        editMerchant = bill.merchant
                        editAmount = "\(bill.amount)"
                        editNotes = bill.notes
                        
                        if let dateStr = bill.date {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd"
                            if let d = formatter.date(from: dateStr) {
                                editDate = d
                            }
                        }
                        if let cat = bill.category {
                            editCategory = cat
                        }
                    }
                } else {
                    await MainActor.run {
                        isScanning = false
                        errorMessage = "Vision model is not available."
                    }
                }
            } catch {
                await MainActor.run {
                    isScanning = false
                    errorMessage = "Failed to scan: \(error.localizedDescription)"
                }
            }
        }
    }

    private func showTransactionPicker() {
        Task {
            // Fetch transactions around the editDate (-30 days to +5 days) to ensure we find it
            let start = Calendar.current.date(byAdding: .day, value: -30, to: editDate) ?? editDate
            let end = Calendar.current.date(byAdding: .day, value: 5, to: editDate) ?? editDate
            let interval = DateInterval(start: start, end: end)
            
            // Try with category if provided
            let categoryFilter = editCategory.isEmpty ? nil : CategoryID(rawValue: editCategory.lowercased())
            var txs = (try? await environment.calc.transactions(in: interval, categoryID: categoryFilter, limit: 30)) ?? []
            
            // If empty, fallback to no category filter
            if txs.isEmpty {
                txs = (try? await environment.calc.transactions(in: interval, categoryID: nil, limit: 30)) ?? []
            }
            
            // Sort by proximity to editDate
            let sorted = txs.sorted { abs($0.date.timeIntervalSince(editDate)) < abs($1.date.timeIntervalSince(editDate)) }
            
            await MainActor.run {
                recentTransactions = sorted
                isShowingTransactionPicker = true
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
                    errorMessage = "Failed to link: \(error.localizedDescription)"
                }
            }
        }
    }

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
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
}
