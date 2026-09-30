import Foundation

let file = "FTL/view/ScanBillScreen.swift"
var content = try String(contentsOfFile: file)

let search = """
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("Select Photo")
                        .font(FTLTypography.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(FTLColor.controlFill, in: Capsule())
                        .overlay { Capsule().strokeBorder(FTLColor.controlBorder) }
                }
                .disabled(isScanning)
"""

let replace = """
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
"""

content = content.replacingOccurrences(of: search, with: replace)

let stateSearch = """
    @State private var selectedItem: PhotosPickerItem?
"""
let stateReplace = """
    @State private var isShowingCamera = false
    @State private var selectedItem: PhotosPickerItem?
"""
content = content.replacingOccurrences(of: stateSearch, with: stateReplace)

let sheetSearch = """
        }
    }
    
    private func scan() {
"""
let sheetReplace = """
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
"""
content = content.replacingOccurrences(of: sheetSearch, with: sheetReplace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
