//
//  GoalDetailView.swift
//  FTL — view/Goal · Phase 1
//
//  ⚠️ Not in the v0.6 spec — see model/Domain/SavingsGoal.
//
//  Reports the daily rate implied by a target and deadline the user set. The copy
//  stays on that side of the line: it says what the rate is, never what to cut.
//

import SwiftUI

struct GoalDetailView: View {
    @Bindable var viewModel: GoalViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                SectionLabel(text: "Target")
                    .padding(.top, FTLSpacing.xl)
                    .padding(.bottom, FTLSpacing.labelGap)
                targetPanel

                Text(viewModel.note)
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.textQuaternary)
                    .padding(.top, FTLSpacing.md)
            }
            .padding(.horizontal, FTLSpacing.screenMargin)
            .padding(.bottom, FTLSpacing.xxl)
        }
        .scrollContentBackground(.hidden)
        .task { await viewModel.load() }
    }

    private var hero: some View {
        Group {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "Save per day to make it")
                Text(MoneyFormatter.grouped(viewModel.dailyRate))
                    .font(FTLTypography.display)
                    .tracking(FTLTypography.displayTracking)
                    .foregroundStyle(FTLColor.textPrimary)
                    .padding(.top, FTLSpacing.sm)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: viewModel.dailyRate)

                MeterBar(
                    fraction: viewModel.fraction,
                    height: FTLMeter.heroHeight,
                    fill: FTLColor.accent,
                )
                .padding(.top, FTLSpacing.lg)
                .padding(.bottom, FTLSpacing.md)

                HStack {
                    Text("\(MoneyFormatter.grouped(viewModel.saved)) saved")
                    Spacer(minLength: FTLSpacing.sm)
                    Text("\(MoneyFormatter.grouped(viewModel.remaining)) to go")
                }
                .font(FTLTypography.amountSmall)
                .foregroundStyle(FTLColor.textSecondary)
            }
        }
    }

    private var targetPanel: some View {
        PanelCard {
            editableRow(
                title: "Amount",
                value: MoneyFormatter.grouped(viewModel.goal?.target ?? .zero),
                field: .amount,
                showsDivider: true,
                onDecrement: { Task { await viewModel.stepAmount(by: -GoalViewModel.amountStep) } },
                onIncrement: { Task { await viewModel.stepAmount(by: GoalViewModel.amountStep) } }
            )
            editableRow(
                title: "Deadline",
                value: viewModel.deadlineLabel,
                field: .deadline,
                showsDivider: false,
                onDecrement: { Task { await viewModel.stepDeadline(by: -GoalViewModel.deadlineStepMonths) } },
                onIncrement: { Task { await viewModel.stepDeadline(by: GoalViewModel.deadlineStepMonths) } }
            )
        }
    }

    private func editableRow(
        title: String,
        value: String,
        field: GoalViewModel.Field,
        showsDivider: Bool,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        let isEditing = viewModel.editingField == field
        return PanelRow(showsDivider: showsDivider) {
            HStack(spacing: FTLSpacing.md) {
                Text(title)
                    .font(FTLTypography.rowTitle)
                    .foregroundStyle(FTLColor.textPrimary)
                Spacer(minLength: FTLSpacing.sm)
                Text(value)
                    .font(FTLTypography.amountEmphasis)
                    .foregroundStyle(isEditing ? FTLColor.textPrimary : FTLColor.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)

                if isEditing {
                    StepperPair(label: title, onDecrement: onDecrement, onIncrement: onIncrement)
                } else {
                    Button { viewModel.editingField = field } label: { Chevron() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(title)")
                }
            }
        }
    }
}
