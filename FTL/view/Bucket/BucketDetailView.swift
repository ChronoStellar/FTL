//
//  BucketDetailView.swift
//  FTL — view/Bucket · Phase 1
//
//  One bucket's spend, its editable ceiling, and the month's rows for it.
//

import SwiftUI

struct BucketDetailView: View {
    @Bindable var viewModel: BucketDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                SectionLabel(text: "Ceiling")
                    .padding(.top, FTLSpacing.xl)
                    .padding(.bottom, FTLSpacing.labelGap)
                ceilingPanel

                SectionLabel(text: "\(viewModel.name) this month")
                    .padding(.top, FTLSpacing.xl)
                    .padding(.bottom, FTLSpacing.labelGap)
                transactionsPanel
            }
            .padding(.horizontal, FTLSpacing.screenMargin)
            .padding(.bottom, FTLSpacing.xxl)
        }
        .scrollContentBackground(.hidden)
        .task { await viewModel.load() }
    }

    private var hero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "Spent this month")
                Text(MoneyFormatter.grouped(viewModel.spent))
                    .font(FTLTypography.displaySmall)
                    .tracking(FTLTypography.displayTracking)
                    .foregroundStyle(FTLColor.textPrimary)
                    .padding(.top, FTLSpacing.sm)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: viewModel.spent)

                MeterBar(
                    fraction: viewModel.fraction,
                    height: FTLMeter.heroHeight,
                    fill: viewModel.isOverCeiling ? FTLColor.budgetOverCeiling : FTLColor.textPrimary,
                    showsBorder: true
                )
                .padding(.top, 18)
                .padding(.bottom, FTLSpacing.md)

                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.statusLabel)
                        .font(FTLTypography.caption)
                        .foregroundStyle(FTLColor.textSecondary)
                    Spacer(minLength: FTLSpacing.sm)
                    Text(viewModel.perDayLabel)
                        .font(FTLTypography.amountEmphasis)
                        .foregroundStyle(FTLColor.textPrimary)
                }
            }
        }
    }

    private var ceilingPanel: some View {
        PanelCard {
            PanelRow(showsDivider: false) {
                HStack(spacing: FTLSpacing.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(viewModel.name) ceiling")
                            .font(FTLTypography.rowTitle)
                            .foregroundStyle(FTLColor.textPrimary)
                        Text(viewModel.ceilingHint)
                            .font(FTLTypography.captionSmall)
                            .foregroundStyle(FTLColor.textQuaternary)
                    }
                    Spacer(minLength: FTLSpacing.sm)
                    Text(MoneyFormatter.grouped(viewModel.ceiling))
                        .font(FTLTypography.amountEmphasis)
                        .foregroundStyle(viewModel.isEditingCeiling ? FTLColor.textPrimary : FTLColor.textSecondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: viewModel.ceiling)

                    if viewModel.isEditingCeiling {
                        StepperPair(
                            label: "\(viewModel.name) ceiling",
                            onDecrement: { Task { await viewModel.step(by: -BucketDetailViewModel.ceilingStep) } },
                            onIncrement: { Task { await viewModel.step(by: BucketDetailViewModel.ceilingStep) } }
                        )
                    } else {
                        Button("Tap to change") { viewModel.beginEditing() }
                            .font(FTLTypography.caption)
                            .foregroundStyle(FTLColor.textTertiary)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var transactionsPanel: some View {
        PanelCard {
            if viewModel.transactions.isEmpty {
                Text("Nothing in this bucket yet.")
                    .font(FTLTypography.caption)
                    .foregroundStyle(FTLColor.textQuaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(FTLSpacing.rowPadding)
            } else {
                ForEach(Array(viewModel.transactions.enumerated()), id: \.element.id) { index, transaction in
                    LedgerRow(
                        transaction: transaction,
                        showsDivider: index < viewModel.transactions.count - 1
                    )
                }
            }
        }
    }
}
