import Foundation

let file = "FTL/view/ContentView.swift"
var content = try String(contentsOfFile: file)

let badIdBlock = """
            case .scan: return "scan"
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

        case .months: return "months"
"""
let fixedIdBlock = """
            case .scan: return "scan"
            case .months: return "months"
"""
content = content.replacingOccurrences(of: badIdBlock, with: fixedIdBlock)

let sheetContentSearch = """
    @ViewBuilder
    private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
        case .months:
"""
let sheetContentReplace = """
    @ViewBuilder
    private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
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
