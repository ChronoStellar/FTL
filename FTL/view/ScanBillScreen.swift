import SwiftUI
import PhotosUI

@available(iOS 27.0, macOS 27.0, *)
struct ScanBillScreen: View {
    let environment: AppEnvironment
    let onCancel: () -> Void
    let onScanned: (ProvisionalEntry) -> Void
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isScanning = false
    @State private var errorMessage: String?
    
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
                
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("Select Photo")
                        .font(FTLTypography.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(FTLColor.controlFill, in: Capsule())
                        .overlay { Capsule().strokeBorder(FTLColor.controlBorder) }
                }
                .disabled(isScanning)
                
                if isScanning {
                    ProgressView("Scanning...")
                        .padding()
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
                    }
                }
            }
        }
    }
    
    private func scan() {
        guard let cgImage = selectedImage?.cgImage else { return }
        isScanning = true
        errorMessage = nil
        
        Task {
            do {
                let scanner = FoundationModelScanner()
                if let bill = try await scanner.scan(cgImage) {
                    let amount = Money.idr(bill.amount)
                    let date = Date()
                    let tx = NormalizedTransaction(
                        id: UUID(),
                        documentID: UUID(),
                        source: .photo,
                        date: date,
                        amount: amount,
                        merchantRaw: bill.merchant,
                        merchant: nil,
                        lineItems: [],
                        fingerprint: Fingerprint(amount: amount, date: date)
                    )
                    let entry = ProvisionalEntry(
                        id: UUID(),
                        transaction: tx,
                        resolution: ProvisionalEntry.Resolution(
                            kind: .spend,
                            nonSpendType: nil,
                            categoryID: .unallocated,
                            merchantID: nil,
                            merchantName: nil,
                            splits: [],
                            mergedFrom: [],
                            suggestedTag: nil
                        ),
                        provenance: .manual,
                        flags: [],
                        status: .pending,
                        createdAt: Date(),
                        readBy: RuleID(rawValue: "FoundationModelScanner"),
                        readAs: .spend,
                        readAmount: amount,
                        notes: bill.notes
                    )
                    
                    try await environment.provisional.insert([entry])
                    
                    await MainActor.run {
                        isScanning = false
                        onScanned(entry)
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
}

