import Foundation

let file = "FTL/view/ScanBillScreen.swift"
var content = try String(contentsOfFile: file)

let stateSearch = """
    @State private var editNotes: String = ""
    @State private var isSaving = false
"""
let stateReplace = """
    @State private var editNotes: String = ""
    @State private var editDate: Date = .now
    @State private var editCategory: String = ""
    @State private var isSaving = false
"""
content = content.replacingOccurrences(of: stateSearch, with: stateReplace)

let scanSearch = """
                        editMerchant = bill.merchant
                        editAmount = "\\(bill.amount)"
                        editNotes = bill.notes
                    }
"""
let scanReplace = """
                        editMerchant = bill.merchant
                        editAmount = "\\(bill.amount)"
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
"""
content = content.replacingOccurrences(of: scanSearch, with: scanReplace)

let uiSearchRegex = try NSRegularExpression(pattern: "                            VStack\\(alignment: \\.leading, spacing: 4\\) \\{\n                                Text\\(\"Notes\"\\)\\.font\\(FTLTypography\\.caption\\)\n                                TextField\\(\"Notes\", text: \\$editNotes\\)\n                                    \\.textFieldStyle\\(\\.roundedBorder\\)\n                            \\}", options: [.dotMatchesLineSeparators])
let uiReplace = """
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
"""
content = uiSearchRegex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: uiReplace)

let pickerSearch = """
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
"""
let pickerReplace = """
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
"""
content = content.replacingOccurrences(of: pickerSearch, with: pickerReplace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
