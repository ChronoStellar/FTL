import Foundation

let file = "FTL/view/Analyze/AnalyzeView.swift"
var content = try String(contentsOfFile: file)

let searchUI = """
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
"""
let replaceUI = """
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
"""
content = content.replacingOccurrences(of: searchUI, with: replaceUI)

let searchHeader = """
                        Text(report.title)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(FTLColor.textPrimary)
                            .padding(.bottom, 8)
"""
let replaceHeader = """
                        Text(report.title)
                            .font(FTLTypography.sectionTitle)
                            .foregroundStyle(FTLColor.textPrimary)
                            .padding(.bottom, 8)
"""
content = content.replacingOccurrences(of: searchHeader, with: replaceHeader)

try content.write(toFile: file, atomically: true, encoding: .utf8)
