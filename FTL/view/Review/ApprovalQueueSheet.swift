//
//  ApprovalQueueSheet.swift
//  FTL — view/Review · Phase 1
//
//  The human gate. Approving here is the only route into the canonical ledger
//  (Invariant 1), and the header says so in as many words — a person about to
//  rubber-stamp a list needs to know what the list is.
//
//  One card per row, each with its own tag chips and its own Approve. Retagging
//  is the common case, and a batch approve would stamp the model's guess onto
//  rows nobody actually read.
//

import SwiftUI

struct ApprovalQueueSheet: View {
    @Bindable var viewModel: ApprovalQueueViewModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FTLSpacing.md) {
                    Text("Nothing here counts against a bucket until you approve it. Tap a tag to change where it lands.")
                        .font(FTLTypography.caption)
                        .foregroundStyle(FTLColor.textQuaternary)
                        .padding(.bottom, FTLSpacing.xs)

                    if viewModel.isEmpty {
                        allClear
                    } else {
                        ForEach(viewModel.sorted) { entry in
                            QueueEntryCard(entry: entry, viewModel: viewModel)
                        }
                    }
                }
                .padding(.horizontal, FTLSpacing.screenMargin)
                .padding(.bottom, FTLSpacing.xxl)
            }
            .scrollContentBackground(.hidden)
            .background(FTLColor.sheetBackground)
            .navigationTitle("To approve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.sheetBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .tint(FTLColor.textTertiary)
                }
            }
            .task { await viewModel.load() }
        }
        .presentationDetents([.large])
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
    }

    private var allClear: some View {
        VStack(spacing: FTLSpacing.xs) {
            Text("All clear")
                .font(FTLTypography.rowTitle)
                .foregroundStyle(FTLColor.textPrimary)
            Text("The ledger is current.")
                .font(FTLTypography.caption)
                .foregroundStyle(FTLColor.textQuaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .overlay {
            RoundedRectangle(cornerRadius: FTLRadius.card, style: .continuous)
                .strokeBorder(FTLColor.controlBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }
}

private struct QueueEntryCard: View {
    let entry: ProvisionalEntry
    @Bindable var viewModel: ApprovalQueueViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tags.padding(.top, FTLSpacing.md)
            actions.padding(.top, 13)
        }
        .padding(15)
        .background(FTLColor.glassFill, in: RoundedRectangle(cornerRadius: FTLRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FTLRadius.card, style: .continuous)
                .strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: FTLSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.transaction.merchantRaw)
                    .font(FTLTypography.amountEmphasis)
                    .foregroundStyle(FTLColor.textPrimary)
                Text(provenanceLine)
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.textQuaternary)
            }
            Spacer(minLength: FTLSpacing.sm)
            Text(MoneyFormatter.rp(entry.transaction.amount))
                .font(FTLTypography.amountEmphasis)
                .foregroundStyle(FTLColor.textPrimary)
        }
    }

    private var tags: some View {
        FlowLayout(spacing: 7) {
            ForEach(viewModel.tagOptions()) { option in
                SelectableChip(
                    title: option.name,
                    isSelected: viewModel.selectedTag(for: entry) == option,
                    isCompact: true
                ) {
                    Task { await viewModel.retag(entry, to: option) }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 9) {
            Button {
                Task { await viewModel.drop(entry) }
            } label: {
                Text("Drop")
                    .font(FTLTypography.body)
                    .foregroundStyle(FTLColor.destructive)
                    .frame(width: 96, height: 46)
                    .overlay {
                        RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous)
                            .strokeBorder(FTLColor.destructive.opacity(0.5), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)

            Button {
                Task { await viewModel.approve(entry) }
            } label: {
                Text(viewModel.approveLabel(for: entry))
                    .font(FTLTypography.body)
                    .foregroundStyle(FTLColor.onLight)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(FTLColor.textPrimary, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// "Email receipt · model · New merchant" — where it came from, whether a rule
    /// or the model settled it, and anything flagged. Never collapsed into one
    /// word: a rule-settled row and a model-tagged row are not the same claim.
    private var provenanceLine: String {
        var parts = [entry.transaction.source.rawValue.capitalized]
        switch entry.provenance {
        case .rule(let id): parts.append(id.rawValue)
        case .model: parts.append("model")
        case .manual: parts.append("you")
        }
        parts.append(contentsOf: entry.flags.map(\.reason.label))
        return parts.joined(separator: " · ")
    }
}
