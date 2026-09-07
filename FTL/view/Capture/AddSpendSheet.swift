//
//  AddSpendSheet.swift
//  FTL — view/Capture · Phase 1
//
//  Manual entry — the only rail that catches cash.
//
//  A custom keypad rather than a TextField: the amount is the whole screen, IDR
//  carries no decimals, and "000" earns a key in a currency where every figure
//  ends in at least three zeros.
//
//  What is added lands in the provisional cache, not the ledger. Invariant 1 has
//  no exception for the user's own typing.
//

import SwiftUI

struct AddSpendSheet: View {
    @Bindable var viewModel: AddSpendViewModel
    let onCancel: () -> Void
    let onCommit: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                amount
                tags
                descriptionField
                Spacer(minLength: FTLSpacing.sm)
                keypad
            }
            .padding(.horizontal, FTLSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlowBackground())
            .navigationTitle("Add spend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel).tint(FTLColor.textTertiary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.phase.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") {
                            Task { if await viewModel.commit() { onCommit() } }
                        }
                        .font(FTLTypography.navTitle)
                        .tint(viewModel.canCommit ? FTLColor.textSecondary : FTLColor.textDisabled)
                        .disabled(!viewModel.canCommit)
                    }
                }
            }
            .task { await viewModel.load() }
        }
    }

    private var amount: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "Amount · IDR")
                .multilineTextAlignment(.center)
            Text(viewModel.amountDisplay)
                .font(FTLTypography.displayLarge)
                .tracking(FTLTypography.displayTracking)
                .foregroundStyle(viewModel.hasAmount ? FTLColor.textPrimary : FTLColor.textDisabled)
                .contentTransition(.numericText())
                .animation(.snappy, value: viewModel.digits)
                .padding(.top, 10)
            // The consequence of this entry, before it is committed. A fact about
            // the ceiling the user set — not a warning, and not a suggestion.
            Text(viewModel.consequence)
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
                .padding(.top, 6)

            if let errorMsg = viewModel.phase.errorMessage {
                Text(errorMsg)
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.destructive)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.labelGap) {
            SectionLabel(text: viewModel.hasCategory ? "Tag" : "Tag · required")
            FlowLayout(spacing: FTLSpacing.sm) {
                ForEach(viewModel.categories) { category in
                    SelectableChip(
                        title: category.name,
                        isSelected: viewModel.selectedCategoryID == category.id
                    ) {
                        Task { await viewModel.select(category.id) }
                    }
                }
            }
        }
        .padding(.bottom, FTLSpacing.xs)
    }

    private var descriptionField: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 13))
                .foregroundStyle(FTLColor.textTertiary)
            TextField("Description · optional", text: $viewModel.merchantText)
                .font(FTLTypography.caption)
                .foregroundStyle(FTLColor.textPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FTLColor.controlFill, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous)
                .strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
        }
        .padding(.bottom, FTLSpacing.xs)
    }

    private var keypad: some View {
        Grid(horizontalSpacing: FTLSpacing.sm, verticalSpacing: FTLSpacing.sm) {
            ForEach(Array(stride(from: 0, to: viewModel.keys.count, by: 3)), id: \.self) { start in
                GridRow {
                    ForEach(viewModel.keys[start..<min(start + 3, viewModel.keys.count)]) { key in
                        keyButton(key)
                    }
                }
            }
        }
        .padding(.bottom, 26)
    }

    private func keyButton(_ key: AddSpendViewModel.KeypadKey) -> some View {
        Button {
            Task { await viewModel.press(key) }
        } label: {
            Group {
                if key.isBackspace {
                    Image(systemName: key.label).font(.system(size: 19, weight: .medium))
                } else {
                    Text(key.label)
                        .font(key.label == "000"
                              ? .system(size: 18, weight: .medium, design: .monospaced)
                              : FTLTypography.keypad)
                }
            }
            .foregroundStyle(FTLColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                key.isBackspace ? Color.clear : FTLColor.controlFill,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                if !key.isBackspace {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.isBackspace ? "Delete" : key.label)
    }
}
