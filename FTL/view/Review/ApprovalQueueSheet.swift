//
//  ApprovalQueueSheet.swift
//  FTL — view/Review · Phase 1
//
//  The human gate. Approving here is the only route into the canonical ledger
//  (Invariant 1), and the header says so in as many words — a person about to
//  rubber-stamp a list needs to know what the list is.
//
//  One card at a time, not a scrolling wall of them. A queue that arrives 30
//  deep on a first sync used to read as "everything at once" the moment the
//  sheet opened — the whole pile visible, all of it equally demanding. Only
//  the TOP of `viewModel.sorted` is ever on screen; settle it with its own
//  Drop/Approve buttons and the next one is what "a lot to do" becomes — one
//  thing, repeatedly, rather than one screenful. (A swipe-to-decide gesture
//  was tried here and pulled back out — it didn't sit right, and the buttons
//  underneath already did the job.)
//
//  A batch approve would stamp the model's guess onto rows nobody actually
//  read — which is why "Approve all" only ever reaches
//  `viewModel.bulkApprovable`, never the full stack. Tapping it clears the
//  easy pile in one write and leaves only what still needs an actual look —
//  the rest of what "smoother" means here.
//

import SwiftUI

struct ApprovalQueueSheet: View {
    @Bindable var viewModel: ApprovalQueueViewModel
    let onDone: () -> Void

    @State private var isConfirmingApproveAll = false

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
                        if !viewModel.bulkApprovable.isEmpty {
                            approveAllRow
                        }
                        progressLine
                        stack
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
                ToolbarItem(placement: .topBarLeading) { sortMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .tint(FTLColor.textTertiary)
                }
            }
            .task { await viewModel.load() }
            .alert(
                "Approve \(viewModel.bulkApprovable.count) transactions?",
                isPresented: $isConfirmingApproveAll
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Approve") { Task { await viewModel.approveAll() } }
            } message: {
                Text("\(MoneyFormatter.rp(viewModel.bulkApprovableTotal)) total. Flagged rows and merchants the model guessed at for the first time are left for you to review one at a time.")
            }
        }
        .presentationDetents([.large])
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
    }

    /// A count, not a scrollbar. The stack shows one card; without this,
    /// nothing on screen says whether that card is the last one or the first
    /// of forty — which is its own kind of "too much", just hidden instead of
    /// visible.
    private var progressLine: some View {
        Text(viewModel.sorted.count == 1 ? "1 to review" : "\(viewModel.sorted.count) to review")
            .font(FTLTypography.captionSmall)
            .foregroundStyle(FTLColor.textQuaternary)
    }

    /// Only the top card is interactive. Behind it, two bare rounded-rect
    /// EDGES peek out from the bottom — no text, no chips, nothing from
    /// `QueueEntryCard` at all.
    ///
    /// The first version rendered actual `QueueEntryCard`s back there at
    /// reduced opacity and scale, which reads fine as a design sketch and
    /// falls apart the moment real content fills it in: two more cards' worth
    /// of merchant names, dates, flags and tag chips all show through at once,
    /// each a different height, none aligned with the others — a wall of
    /// ghosted, overlapping text sitting directly behind the one card this
    /// screen exists to make you NOT see all at once. Bare edges give the
    /// same "there is a queue here" cue without carrying any content that can
    /// collide.
    @ViewBuilder
    private var stack: some View {
        let queue = viewModel.sorted
        ZStack(alignment: .bottom) {
            ForEach(0..<min(2, max(0, queue.count - 1)), id: \.self) { position in
                RoundedRectangle(cornerRadius: FTLRadius.card, style: .continuous)
                    .fill(FTLColor.glassFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: FTLRadius.card, style: .continuous)
                            .strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
                    }
                    .frame(height: 30)
                    .padding(.horizontal, CGFloat(2 - position) * 10)
                    .offset(y: CGFloat(2 - position) * 12)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
            if let top = queue.first {
                QueueEntryCard(entry: top, viewModel: viewModel)
                    .id(top.id)
            }
        }
    }

    /// Only shown when `bulkApprovable` isn't empty — an action with nothing
    /// safe to act on is clutter, not a shortcut.
    private var approveAllRow: some View {
        Button {
            isConfirmingApproveAll = true
        } label: {
            HStack {
                Text("Approve all ready · \(viewModel.bulkApprovable.count)")
                    .font(FTLTypography.body)
                    .foregroundStyle(FTLColor.textPrimary)
                Spacer()
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(FTLColor.textSecondary)
            }
            .padding(.horizontal, 15)
            .frame(height: 46)
            .background(FTLColor.glassFill, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous)
                    .strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, FTLSpacing.xs)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ApprovalQueueViewModel.SortOption.allCases) { option in
                Button {
                    viewModel.sortOption = option
                } label: {
                    if viewModel.sortOption == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(FTLColor.textTertiary)
        }
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
            suggestion
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

    /// Where the pre-selected chip came from, stated as an observation.
    ///
    /// No hue and no icon: a suggestion is not a signal, and the app has exactly
    /// one signal colour reserved for over-ceiling, flagged and destructive. It
    /// reads at tertiary contrast, one line, above the chips it is talking about
    /// — visible enough that approving is still a decision, quiet enough that it
    /// never competes with a flag.
    @ViewBuilder
    private var suggestion: some View {
        if let note = viewModel.suggestionNote(for: entry) {
            Text(note)
                .font(FTLTypography.caption)
                .foregroundStyle(FTLColor.textTertiary)
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
            let isSettling = viewModel.isSettling(entry.id)

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
            .disabled(isSettling)

            Button {
                Task { await viewModel.approve(entry) }
            } label: {
                if isSettling {
                    ProgressView()
                        .tint(FTLColor.onLight)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(FTLColor.textPrimary, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
                } else {
                    Text(viewModel.approveLabel(for: entry))
                        .font(FTLTypography.body)
                        .foregroundStyle(FTLColor.onLight)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(FTLColor.textPrimary, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .disabled(isSettling)
        }
    }

    /// "12 Sep · Email · blu-receipt" — when it happened, where it came from,
    /// and what settled it. Never collapsed into one word: a rule-settled row
    /// and a model-tagged row are not the same claim.
    ///
    /// The date leads. The queue sorts oldest-first by this same date (see
    /// `ApprovalQueueViewModel.sorted`) precisely so a big batch reads in the
    /// order a person recognises their own spending rather than the order
    /// Gmail happened to return it — the date on the card is what makes that
    /// order legible instead of just a different, equally invisible one.
    ///
    /// Flags used to be appended here and now render in `notes`. Provenance is
    /// background — true of every row, worth a glance. A flag is foreground —
    /// true of this row, and the reason it is in front of you.
    private var provenanceLine: String {
        var parts = [entry.transaction.date.formatted(.dateTime.day().month(.abbreviated))]
        parts.append(entry.transaction.source.rawValue.capitalized)
        switch entry.provenance {
        case .rule(let id): parts.append(id.origin.badgeText)
        case .model: parts.append("🤖 model")
        case .manual: parts.append("✍️ you")
        }
        return parts.joined(separator: " · ")
    }
}
