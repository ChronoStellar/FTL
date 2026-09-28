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
    @State private var scannedResult: ScannedBill?
    @State private var ocrResult: String?
    
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
                } else if let bill = scannedResult {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scanned Result").font(FTLTypography.rowTitle)
                        HStack { Text("Merchant:").fontWeight(.semibold); Text(bill.merchant) }
                        HStack { Text("Amount:").fontWeight(.semibold); Text("\(bill.amount)") }
                        HStack { Text("Notes:").fontWeight(.semibold); Text(bill.notes) }
                        
                        Button(action: { scannedResult = nil; ocrResult = nil }) {
                            Text("Scan Another")
                                .font(FTLTypography.body)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(FTLColor.controlFill, in: Capsule())
                        }
                    }
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

