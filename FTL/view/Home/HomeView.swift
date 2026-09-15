//
//  HomeView.swift
//  FTL — view/Home · Phase 1
//
//  Spend against the month's ceiling, the approval queue, the buckets, the goal,
//  and recent rows. Reads state off HomeViewModel and renders it — no arithmetic.
//

import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let onOpenBucket: (BudgetPosition) -> Void
    let onOpenGoal: () -> Void
    let onOpenQueue: () -> Void
    /// Presented by `ContentView`, which owns the environment the editor's view
    /// model is built from.
    let onEditTransaction: (LedgerTransaction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch viewModel.phase {
                case .idle, .loading:
                    BeamActivity()
                        .frame(maxWidth: .infinity)
                        .padding(.top, FTLSpacing.xxl)
                case .failed(let message):
                    failure(message)
                case .loaded:
                    loaded
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FTLSpacing.screenMargin)
            .padding(.bottom, FTLSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load(forceReload: true) }
    }

    // MARK: - Loaded

    @ViewBuilder
    private var loaded: some View {
        SpendHeroCard(
            spent: viewModel.month?.spent ?? .zero,
            ceiling: viewModel.month?.ceiling ?? .zero,
            fraction: viewModel.month?.fraction ?? 0,
            isOverCeiling: viewModel.month?.isOverCeiling ?? false,
            percentLabel: viewModel.percentLabel,
            remainingLabel: viewModel.remainingLabel,
            perDayLabel: viewModel.perDayLabel
        )

        if viewModel.hasPending {
            QueueCard(
                count: viewModel.pendingCount,
                title: viewModel.queueTitle,
                total: viewModel.pendingTotal,
                action: onOpenQueue
            )
            .padding(.top, FTLSpacing.md)
        }

        SectionLabel(text: "Buckets")
            .padding(.top, FTLSpacing.sectionGap)
            .padding(.bottom, FTLSpacing.labelGap)

        PanelCard {
            ForEach(Array(bucketRows.enumerated()), id: \.element.id) { index, bucket in
                BucketRow(
                    position: bucket,
                    showsDivider: index < bucketRows.count - 1,
                    action: { onOpenBucket(bucket) }
                )
            }
        }

        SectionLabel(text: "Recent")
            .padding(.top, FTLSpacing.sectionGap)
            .padding(.bottom, FTLSpacing.labelGap)

        PanelCard {
            if viewModel.recent.isEmpty {
                emptyRecent
            } else {
                ForEach(Array(viewModel.recent.enumerated()), id: \.element.id) { index, transaction in
                    LedgerRow(
                        transaction: transaction,
                        showsDivider: index < viewModel.recent.count - 1,
                        onEdit: { onEditTransaction(transaction) },
                        onDelete: {
                            Task { await viewModel.deleteTransaction(transaction) }
                        }
                    )
                }
            }
        }
    }

    /// The named buckets, plus the implicit unallocated child when it holds spend.
    ///
    /// The canvas leaves Unallocated out of this list, but v0.5 §10 is explicit
    /// that every parent carries a visible unallocated child so mystery spend
    /// stays visible. Hidden, it would still land in the hero total with nothing
    /// on screen explaining the gap.
    private var bucketRows: [BudgetPosition] {
        guard let root = viewModel.buckets.first else { return [] }
        return root.children.filter { $0.id != .unallocated || $0.actual.minorUnits > 0 }
    }

    private var emptyRecent: some View {
        Text("Nothing recorded this month.")
            .font(FTLTypography.caption)
            .foregroundStyle(FTLColor.textQuaternary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FTLSpacing.rowPadding)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            Text("Couldn't load")
                .font(FTLTypography.rowTitle)
                .foregroundStyle(FTLColor.textPrimary)
            Text(message)
                .font(FTLTypography.caption)
                .foregroundStyle(FTLColor.error)
        }
        .padding(.top, FTLSpacing.xxl)
    }
}
