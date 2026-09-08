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
            notes
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

    /// Flags, on their own line, at readable contrast, WITH their detail.
    ///
    /// They used to be joined onto the end of `provenanceLine`: quaternary
    /// grey, 12pt, third item in a run-on string, visually identical whether
    /// the app had noticed a new merchant or failed to read the amount. That
    /// made the one signal meaning "I made a judgement, check it" the least
    /// visible text on the card.
    ///
    /// Worse, `ReviewFlag.detail` was never rendered anywhere. "Read as a
    /// transfer, not a purchase" existed in the data, was written to the store,
    /// and reached nobody — the flag could only ever say "Spend unclear",
    /// which states the problem and withholds the reason.
    ///
    /// One hue only, so emphasis is weight and contrast: label at
    /// `textSecondary`, detail at `textTertiary`, both above the quaternary
    /// provenance line rather than buried in it.
    @ViewBuilder
    private var notes: some View {
        if !entry.flags.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(entry.flags) { flag in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FTLColor.textSecondary)
                        Text(flag.reason.label)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(FTLColor.textSecondary)
                        if let detail = flag.detail {
                            Text(detail)
                                .font(FTLTypography.caption)
                                .foregroundStyle(FTLColor.textTertiary)
                        }
                    }
                }
            }
            .padding(.top, 9)
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

    /// "Email · blu-receipt" — where it came from and what settled it. Never
    /// collapsed into one word: a rule-settled row and a model-tagged row are
    /// not the same claim.
    ///
    /// Flags used to be appended here and now render in `notes`. Provenance is
    /// background — true of every row, worth a glance. A flag is foreground —
    /// true of this row, and the reason it is in front of you.
    private var provenanceLine: String {
        var parts = [entry.transaction.source.rawValue.capitalized]
        switch entry.provenance {
        case .rule(let id): parts.append(id.rawValue)
        case .model: parts.append("model")
        case .manual: parts.append("you")
        }
        return parts.joined(separator: " · ")
    }
}
