//
//  MonthPickerSheet.swift
//  FTL — view/Months · Phase 1
//
//  Spend against each month's ceiling. A native sheet with a medium detent, so
//  the month list behaves the way every other iOS picker does.
//

import SwiftUI

struct MonthPickerSheet: View {
    let months: [MonthSummary]
    let selectedID: Date?
    let onPick: (MonthSummary) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FTLSpacing.sm) {
                    ForEach(months.reversed()) { month in
                        row(month)
                    }
                }
                .padding(.horizontal, FTLSpacing.screenMargin)
                .padding(.bottom, FTLSpacing.xl)
            }
            .scrollContentBackground(.hidden)
            .background(FTLColor.sheetBackground)
            .navigationTitle("Months")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.sheetBackground, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
    }

    private func row(_ month: MonthSummary) -> some View {
        let isSelected = month.id == selectedID
        return Button { onPick(month) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(month.interval.start.formatted(.dateTime.month(.wide).year()))
                        .font(FTLTypography.rowTitle)
                        .foregroundStyle(FTLColor.textPrimary)
                    Spacer(minLength: FTLSpacing.sm)
                    Text(MoneyFormatter.grouped(month.spent))
                        .font(FTLTypography.amountSmall)
                        .foregroundStyle(month.isOverCeiling ? FTLColor.budgetOverCeiling : FTLColor.textPrimary)
                }
                MeterBar(
                    fraction: month.fraction,
                    height: FTLMeter.monthHeight,
                    fill: fill(for: month, isSelected: isSelected)
                )
            }
            .padding(FTLSpacing.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? FTLColor.panelRaised : FTLColor.panel,
                in: RoundedRectangle(cornerRadius: FTLRadius.panel, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FTLRadius.panel, style: .continuous)
                    .strokeBorder(isSelected ? FTLColor.controlBorder : FTLColor.hairline, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Past months that stayed under their ceiling recede; the selected one and
    /// any month that went over stay legible.
    private func fill(for month: MonthSummary, isSelected: Bool) -> Color {
        if month.isOverCeiling { return FTLColor.budgetOverCeiling }
        return isSelected ? FTLColor.textPrimary : FTLColor.unallocated
    }
}
