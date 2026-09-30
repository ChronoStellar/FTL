import Foundation

let file = "FTL/view/Analyze/AnalyzeView.swift"
var content = try String(contentsOfFile: file)

let search = """
struct AnalyzeView: View {
    let environment: AppEnvironment
    
    @State private var isGenerating = false
    @State private var report: String? = nil
"""
let replace = """
@available(iOS 27.0, macOS 27.0, *)
struct AnalyzeView: View {
    let environment: AppEnvironment
    let interval: DateInterval
    
    @State private var isGenerating = false
    @State private var report: SpendingRecap? = nil
"""
content = content.replacingOccurrences(of: search, with: replace)

let searchBody = """
                if let report {
                    Text("AI Analysis Report")
                        .font(FTLTypography.rowTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(report)
                        .font(FTLTypography.body)
                        .foregroundStyle(FTLColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
"""
let replaceBody = """
                if let report {
                    VStack(alignment: .leading, spacing: FTLSpacing.xl) {
                        Text(report.title)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(FTLColor.textPrimary)
                            .padding(.bottom, 8)
                        
                        VStack(alignment: .leading, spacing: FTLSpacing.md) {
                            Label("Patterns & Habits", systemImage: "chart.pie.fill")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.accent)
                            Text(report.patterns)
                                .font(FTLTypography.body)
                                .foregroundStyle(FTLColor.textSecondary)
                        }
                        
                        VStack(alignment: .leading, spacing: FTLSpacing.md) {
                            Label("Fun Fact", systemImage: "party.popper.fill")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(.orange)
                            Text(report.funFact)
                                .font(FTLTypography.body)
                                .foregroundStyle(FTLColor.textSecondary)
                        }
                        
                        VStack(alignment: .leading, spacing: FTLSpacing.md) {
                            Label("Next Month's Playbook", systemImage: "target")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(.green)
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
content = content.replacingOccurrences(of: searchBody, with: replaceBody)

let searchFunc = """
    private func generateReport() {
        isGenerating = true
        // Scaffold: In the future, this will collect transactions and prompt the FoundationModel.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                report = "Here is a placeholder report for your recent spendings. In the final version, the AI will break down your spending across different categories, highlight any unusual purchases, and recommend budget adjustments."
                isGenerating = false
            }
        }
    }
"""
let replaceFunc = """
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
                
                await MainActor.run {
                    self.report = result
                    isGenerating = false
                }
            } catch {
                print("Error generating recap: \\(error)")
                await MainActor.run { isGenerating = false }
            }
        }
    }
"""
content = content.replacingOccurrences(of: searchFunc, with: replaceFunc)

let searchOnChange = """
        .background(FTLColor.ground)
    }
"""
let replaceOnChange = """
        .background(FTLColor.ground)
        .onChange(of: interval) { _, _ in
            report = nil
        }
    }
"""
content = content.replacingOccurrences(of: searchOnChange, with: replaceOnChange)

try content.write(toFile: file, atomically: true, encoding: .utf8)
