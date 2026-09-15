//
//  BucketDetailView.swift
//  FTL — view/Bucket · Phase 1
//
//  One bucket's spend, its ceiling, and the month's rows for it.
//
//  The ceiling is a readout. See `BucketDetailViewModel` for why the editor that
//  used to live here was removed.
//

import SwiftUI

struct BucketDetailView: View {
    @Bindable var viewModel: BucketDetailViewModel
    /// Presented by `BucketScreen`, which owns the environment the editor's
    /// view model is built from.
    let onEditTransaction: (LedgerTransaction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let message = viewModel.phase.errorMessage {
                    loadFailure(message)
                }
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
        .actionFailureAlert($viewModel.actionError)
        .task { await viewModel.load() }
    }

    /// A bucket that could not load shows zeros, which read as a real position
    /// rather than as a missing one. This says which it is.
    private func loadFailure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: FTLSpacing.xs) {
            Text("Couldn't load this bucket")
                .font(FTLTypography.rowTitle)
                .foregroundStyle(FTLColor.textPrimary)
            Text(message)
                .font(FTLTypography.caption)
                .foregroundStyle(FTLColor.error)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, FTLSpacing.lg)
    }

    private var hero: some View {
        Group {
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
                )
                .padding(.top, FTLSpacing.lg)
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
                        .foregroundStyle(FTLColor.textSecondary)
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
                        showsDivider: index < viewModel.transactions.count - 1,
                        onEdit: { onEditTransaction(transaction) },
                        onDelete: {
                            Task { await viewModel.deleteTransaction(transaction) }
                        }
                    )
                }
            }
        }
    }
}
