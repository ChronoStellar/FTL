//
//  IncomeSplitView.swift
//  FTL — view/Onboarding · Phase 1
//
//  Set every ceiling at once: type a monthly income, split it across buckets
//  by percentage, watch the bar and the Rp figures update, save. Reached as a
//  one-time prompt the first time the Total ceiling is still zero, and again
//  any time from Settings → Budget Ceilings — it's a faster way to set
//  ceilings, not a gate the app makes you pass.
//

import SwiftUI

struct IncomeSplitView: View {
    @Bindable var viewModel: IncomeSplitViewModel
    let onSkip: () -> Void
    let onSaved: () -> Void

    /// The number pad has no return key, so without somewhere to send focus it
    /// stays up forever and covers the split it's meant to be feeding.
    @FocusState private var isIncomeFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .idle, .loading:
                    BeamActivity()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    failure(message)
                case .loaded:
                    content
                }
            }
            .background(FTLColor.sheetBackground)
            .navigationTitle("Set up by income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.sheetBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                        .foregroundStyle(FTLColor.textTertiary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await viewModel.save() { onSaved() } }
                    }
                    .font(FTLTypography.navTitle)
                    .tint(viewModel.canSave ? FTLColor.textSecondary : FTLColor.textDisabled)
                    .disabled(!viewModel.canSave)
                }
            }
            .task { await viewModel.load() }
        }
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FTLSpacing.xl) {
                incomeSection
                if !viewModel.rows.isEmpty {
                    splitSection
                }
            }
            .padding(.horizontal, FTLSpacing.screenMargin)
            .padding(.top, FTLSpacing.lg)
            .padding(.bottom, FTLSpacing.xxl)
        }
        .scrollContentBackground(.hidden)
        // Dragging the page down dismisses it.
        .scrollDismissesKeyboard(.interactively)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        )
    }

    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            SectionLabel(text: "Monthly income")
            PanelCard {
                PanelRow(showsDivider: false) {
                    HStack(spacing: 6) {
                        Text("Rp")
                            .font(FTLTypography.amountEmphasis)
                            .foregroundStyle(FTLColor.textTertiary)
                        TextField("0", text: $viewModel.incomeDigits)
                            .keyboardType(.numberPad)
                            .focused($isIncomeFocused)
                            .font(FTLTypography.amountEmphasis)
                            .foregroundStyle(FTLColor.textPrimary)
                    }
                }
            }
            Text("Every bucket below is a percentage of this. Raising one draws from Unallocated and lowering one puts it back — no other bucket moves. Saving writes each ceiling straight to your Sheet.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            HStack {
                SectionLabel(text: "Split")
                Spacer()
                // Only offered when there is something to match. On a mailbox
                // with no history the starting split is even, and a button
                // that would re-derive it from nothing is a dead control.
                if viewModel.hasSpendHistory {
                    Button("Match my spending") { viewModel.matchSpending() }
                        .font(FTLTypography.captionSmall)
                        .foregroundStyle(FTLColor.textTertiary)
                        .buttonStyle(.plain)
                }
            }

            SplitBar(segments: viewModel.rows.map {
                SplitBar.Segment(id: $0.categoryID, fraction: Double($0.percent) / 100)
            })
            .padding(.vertical, FTLSpacing.xs)

            PanelCard {
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    PanelRow(showsDivider: index < viewModel.rows.count - 1) {
                        splitRow(row)
                    }
                }
            }

            // No over-allocated warning: the total is pinned at 100% and that
            // state is unreachable. What IS reachable, and needs saying, is a
            // drag that stops moving — which happens for exactly one reason.
            Text(viewModel.unallocatedPercent == 0
                 ? "Unallocated is empty, so no bucket can grow until another one comes down."
                 : "Unallocated is money you haven't apportioned — it stays in the total and stays visible.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }

    /// Name and figures on one line, the slider under it full width.
    ///
    /// The steppers this replaced were a pair of 44pt buttons competing with
    /// the name and two numbers for one row's width, and each tap moved five
    /// points of one bucket — six rows meant a lot of tapping to land a split.
    /// Deliberately no animation on `percent`: the number and the knob have to
    /// track the thumb, and easing either one puts them behind the finger.
    private func splitRow(_ row: IncomeSplitViewModel.SplitRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: FTLSpacing.sm) {
                Text(row.name)
                    .font(FTLTypography.rowTitle)
                    .foregroundStyle(row.isUnallocated ? FTLColor.textSecondary : FTLColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: FTLSpacing.sm)
                Text(MoneyFormatter.rp(viewModel.amount(for: row)))
                    .font(FTLTypography.amountSmall)
                    .foregroundStyle(FTLColor.textQuaternary)
                    .lineLimit(1)
                Text("\(row.percent)%")
                    .font(FTLTypography.amountEmphasis)
                    .foregroundStyle(row.isUnallocated ? FTLColor.textTertiary : FTLColor.textPrimary)
                    // Fixed width so a row doesn't reflow as the figure crosses
                    // 9 → 10 → 100 under the thumb.
                    .frame(minWidth: 44, alignment: .trailing)
            }
            // Unallocated gets a bar and no thumb. It is `100 − Σ named` by
            // definition, so a thumb on it would be a second, contradictory way
            // to set the same number — and the missing thumb is itself the
            // clearest statement of which rows you drive and which one reports.
            if row.isUnallocated {
                MeterBar(
                    fraction: Double(row.percent) / 100,
                    height: FTLMeter.heroHeight,
                    fill: FTLColor.unallocated
                )
                .frame(height: FTLSpacing.minTapTarget)
            } else {
                RatioSlider(
                    value: row.percent,
                    label: "\(row.name) share",
                    onChange: { viewModel.setPercent(row, to: $0) }
                )
            }
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FTLSpacing.screenMargin)
        .padding(.top, FTLSpacing.xxl)
    }
}
