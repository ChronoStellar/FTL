import Foundation

let file = "FTL/view/ContentView.swift"
var content = try String(contentsOfFile: file)

// Restore ToolbarItemGroup and scan button
let toolbarSearch = """
        ToolbarItem(placement: .topBarTrailing) {
            Button { sheet = .add() } label: {
"""
let toolbarReplace = """
        ToolbarItemGroup(placement: .topBarTrailing) {
            if #available(iOS 27.0, macOS 27.0, *) {
                Button { sheet = .scan } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(FTLColor.textPrimary)
                        .frame(width: FTLSpacing.minTapTarget, height: FTLSpacing.minTapTarget)
                        .background(FTLColor.controlFill, in: Circle())
                        .overlay { Circle().strokeBorder(FTLColor.controlBorder, lineWidth: 0.5) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan Bill")
            }
            
            Button { sheet = .add() } label: {
"""
content = content.replacingOccurrences(of: toolbarSearch, with: toolbarReplace)

// Restore case settings, incomeSplit, scan
content = content.replacingOccurrences(of: "case settings, incomeSplit\n", with: "case settings, incomeSplit, scan\n")
content = content.replacingOccurrences(of: "            case .months: return \"months\"\n", with: "            case .scan: return \"scan\"\n            case .months: return \"months\"\n")

// Restore sheetContent
let sheetContentSearch = """
        case .months:
"""
let sheetContentReplace = """
        case .scan:
            if #available(iOS 27.0, macOS 27.0, *) {
                ScanBillScreen(
                    environment: environment,
                    onCancel: { sheet = nil },
                    onScanned: { _ in
                        sheet = nil
                        Task { await home.load(forceReload: true) }
                    }
                )
            } else {
                Text("Scan feature requires iOS 27.0 or newer.")
            }

        case .months:
"""
content = content.replacingOccurrences(of: sheetContentSearch, with: sheetContentReplace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
