import Foundation

let file = "FTL/view/Analyze/AnalyzeView.swift"
var content = try String(contentsOfFile: file)

let searchGenerate = """
    private func generateReport() {
        isGenerating = true
        Task {
            do {
                let txs = try await environment.calc.transactions(in: interval, categoryID: nil, limit: 1000)
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                let monthName = formatter.string(from: interval.start)
                
                let analyzer = FoundationModelAnalyzer()
                let result = try await analyzer.analyze(transactions: txs, monthName: monthName)
"""
let replaceGenerate = """
    private func generateReport() {
        isGenerating = true
        Task {
            do {
                let txs = try await environment.calc.transactions(in: interval, categoryID: nil, limit: 1000)
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                let monthName = formatter.string(from: interval.start)
                let monthKey = SheetsSchema.monthKey(for: interval)
                
                // Get budget context
                let budgets = (try? await environment.calc.budgetPositions(for: interval)) ?? []
                let rootBudgets = budgets.first?.children ?? budgets
                
                let analyzer = FoundationModelAnalyzer()
                let result = try await analyzer.analyze(transactions: txs, monthName: monthName, budgets: rootBudgets)
                
                if let result {
                    try? await environment.analysisStore.saveReport(result, for: monthKey)
                }
"""
content = content.replacingOccurrences(of: searchGenerate, with: replaceGenerate)

let searchOnChange = """
        .onChange(of: interval) { _, _ in
            report = nil
        }
"""
let replaceOnChange = """
        .task(id: interval) {
            let monthKey = SheetsSchema.monthKey(for: interval)
            report = try? await environment.analysisStore.fetchReport(for: monthKey)
        }
        .onChange(of: interval) { _, _ in
            report = nil
        }
"""
content = content.replacingOccurrences(of: searchOnChange, with: replaceOnChange)

let searchUI = """
                        VStack(alignment: .leading, spacing: FTLSpacing.md) {
                            Label("Allocation Recommendations", systemImage: "arrow.triangle.branch")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Text(report.recommendations)
                                .font(FTLTypography.body)
                                .foregroundStyle(FTLColor.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: FTLRadius.panel).fill(FTLColor.controlFill))
                    .overlay(RoundedRectangle(cornerRadius: FTLRadius.panel).strokeBorder(FTLColor.controlBorder))
                } else {
"""
let replaceUI = """
                        VStack(alignment: .leading, spacing: FTLSpacing.md) {
                            Label("Allocation Recommendations", systemImage: "arrow.triangle.branch")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Text(report.recommendations)
                                .font(FTLTypography.body)
                                .foregroundStyle(FTLColor.textSecondary)
                        }
                        
                        Divider()
                        
                        Button(action: generateReport) {
                            if isGenerating {
                                ProgressView().controlSize(.small)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            } else {
                                Text("Regenerate Analysis")
                                    .font(FTLTypography.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                        .disabled(isGenerating)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: FTLRadius.panel).fill(FTLColor.controlFill))
                    .overlay(RoundedRectangle(cornerRadius: FTLRadius.panel).strokeBorder(FTLColor.controlBorder))
                } else {
"""
content = content.replacingOccurrences(of: searchUI, with: replaceUI)

try content.write(toFile: file, atomically: true, encoding: .utf8)
