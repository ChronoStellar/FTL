import SwiftUI

@available(iOS 27.0, macOS 27.0, *)
struct AnalyzeView: View {
    let environment: AppEnvironment
    let interval: DateInterval
    
    @State private var isGenerating = false
    @State private var report: SpendingRecap? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: FTLSpacing.lg) {
                if let report {
                    VStack(alignment: .leading, spacing: FTLSpacing.xl) {
                        Text(report.title)
                            .font(FTLTypography.navTitle)
                            .foregroundStyle(FTLColor.textPrimary)
                            .padding(.bottom, 8)
                        
                        VStack(alignment: .leading, spacing: FTLSpacing.md) {
                            Label("Statistical Patterns", systemImage: "chart.bar.xaxis")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Text(report.patterns)
                                .font(FTLTypography.body)
                                .foregroundStyle(FTLColor.textSecondary)
                        }
                        
                        VStack(alignment: .leading, spacing: FTLSpacing.md) {
                            Label("Key Insight", systemImage: "magnifyingglass")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Text(report.keyInsight)
                                .font(FTLTypography.body)
                                .foregroundStyle(FTLColor.textSecondary)
                        }
                        
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
                    ContentUnavailableView(
                        "No Analysis",
                        systemImage: "sparkles",
                        description: Text("Generate an AI-powered summary of your recent spending habits.")
                    )
                    
                    Button(action: generateReport) {
                        if isGenerating {
                            ProgressView().controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(FTLColor.accent, in: Capsule())
                        } else {
                            Text("Generate Report")
                                .font(FTLTypography.body)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(FTLColor.accent, in: Capsule())
                        }
                    }
                    .disabled(isGenerating)
                    .padding(.horizontal, FTLSpacing.screenMargin)
                }
            }
            .padding(FTLSpacing.screenMargin)
        }
        .background(FTLColor.ground)
        .task(id: interval) {
            let monthKey = SheetsSchema.monthKey(for: interval)
            report = try? await environment.analysisStore.fetchReport(for: monthKey)
        }
        .onChange(of: interval) { _, _ in
            report = nil
        }
    }
    
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
                
                await MainActor.run {
                    self.report = result
                    isGenerating = false
                }
            } catch {
                print("Error generating recap: \(error)")
                await MainActor.run { isGenerating = false }
            }
        }
    }
}
