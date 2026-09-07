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
                    ProgressView()
                        .tint(FTLColor.textTertiary)
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
                // The number pad's only way out.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isIncomeFocused = false }
                }
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
        // Dragging the page down dismisses it, and the keyboard toolbar has a
        // Done. Deliberately NOT an .onTapGesture on the ScrollView: that
        // competes with the stepper buttons inside it, and trading "keyboard
        // won't dismiss" for "steppers don't respond" is not a fix.
        .scrollDismissesKeyboard(.interactively)
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
            Text("Every bucket below is a percentage of this. Saving writes each ceiling straight to your Sheet — same as setting one by hand, just all at once.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            HStack {
                SectionLabel(text: "Split")
                Spacer()
                Text("\(viewModel.totalPercent)%")
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(viewModel.isOverAllocated ? FTLColor.budgetOverCeiling : FTLColor.textQuaternary)
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

            if viewModel.isOverAllocated {
                Text("\(-viewModel.remainingPercent)% more than the income — take some back before saving.")
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.budgetOverCeiling)
            } else if viewModel.remainingPercent > 0 {
                // Not an error: the budget tree already carries an implicit
                // unallocated child, and this is exactly what it's for.
                Text("\(viewModel.remainingPercent)% unallocated · \(MoneyFormatter.rp(viewModel.unallocatedAmount))")
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.textQuaternary)
            }
        }
    }

    private func splitRow(_ row: IncomeSplitViewModel.SplitRow) -> some View {
        HStack(spacing: FTLSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(FTLTypography.rowTitle)
                    .foregroundStyle(FTLColor.textPrimary)
                Text(MoneyFormatter.rp(viewModel.amount(for: row)))
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.textQuaternary)
            }
            Spacer(minLength: FTLSpacing.sm)
            Text("\(row.percent)%")
                .font(FTLTypography.amountEmphasis)
                .foregroundStyle(FTLColor.textSecondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: row.percent)
            StepperPair(
                label: "\(row.name) share",
                onDecrement: { viewModel.adjust(row, by: -IncomeSplitViewModel.step) },
                onIncrement: { viewModel.adjust(row, by: IncomeSplitViewModel.step) }
            )
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
