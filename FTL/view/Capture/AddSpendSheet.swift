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

    /// The note is edited in its own sheet, never inline. A TextField on this
    /// screen raises the system keyboard ON TOP of the custom keypad — two
    /// keyboards at once, the amount label clipped behind the nav bar, and the
    /// keyboard's own toolbar landing over the backspace key. No amount of
    /// dismiss-handling fixes that; the two inputs just can't share a screen.
    @State private var isEditingNote = false
    @State private var noteDraft = ""
    @FocusState private var isNoteFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                amount
                tagPicker
                noteRow
                Spacer(minLength: FTLSpacing.sm)
                keypad
            }
            .padding(.horizontal, FTLSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlowBackground())
            .navigationTitle("Add spend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
            .sheet(isPresented: $isEditingNote) { noteSheet }
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

    /// A menu rather than a row of chips: with seven-plus buckets the chips wrap
    /// to three lines and shove the keypad down the screen, which is the part
    /// you actually came here to use. One line, same information.
    private var tagPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 13))
                .foregroundStyle(FTLColor.textTertiary)
            Text("Tag")
                .font(FTLTypography.caption)
                .foregroundStyle(FTLColor.textTertiary)
            Spacer(minLength: FTLSpacing.sm)
            Picker("Tag", selection: selectedCategory) {
                ForEach(viewModel.categories) { category in
                    Text(category.name).tag(CategoryID?.some(category.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(viewModel.hasCategory ? FTLColor.textPrimary : FTLColor.textDisabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(FTLColor.controlFill, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous)
                .strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
        }
        .padding(.bottom, FTLSpacing.sm)
    }

    /// Routes through `select(_:)` rather than writing the property directly —
    /// picking a bucket has to recompute the consequence line under the amount.
    private var selectedCategory: Binding<CategoryID?> {
        Binding(
            get: { viewModel.selectedCategoryID },
            set: { newValue in
                guard let newValue else { return }
                Task { await viewModel.select(newValue) }
            }
        )
    }

    /// Shows the note if there is one, invites one if there isn't. Tapping opens
    /// the editor rather than focusing anything here, so this screen never has a
    /// system keyboard on it.
    private var noteRow: some View {
        Button {
            noteDraft = viewModel.merchantText
            isEditingNote = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.merchantText.isEmpty ? "square.and.pencil" : "text.alignleft")
                    .font(.system(size: 13))
                    .foregroundStyle(FTLColor.textTertiary)
                Text(viewModel.merchantText.isEmpty ? "Add a note · optional" : viewModel.merchantText)
                    .font(FTLTypography.caption)
                    .foregroundStyle(viewModel.merchantText.isEmpty ? FTLColor.textTertiary : FTLColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: FTLSpacing.sm)
                Chevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(FTLColor.controlFill, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous)
                    .strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, FTLSpacing.xs)
    }

    /// Its own sheet, sized to the keyboard it summons. Edits a draft so
    /// backing out leaves the note as it was.
    private var noteSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("e.g. Coffee, groceries", text: $noteDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(FTLTypography.body)
                    .foregroundStyle(FTLColor.textPrimary)
                    .autocorrectionDisabled()
                    .focused($isNoteFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(FTLColor.controlFill, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous)
                            .strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
                    }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, FTLSpacing.screenMargin)
            .padding(.top, FTLSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FTLColor.sheetBackground)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.sheetBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditingNote = false }
                        .tint(FTLColor.textTertiary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.merchantText = noteDraft
                        isEditingNote = false
                    }
                    .font(FTLTypography.navTitle)
                    .tint(FTLColor.textSecondary)
                }
            }
            .task { isNoteFocused = true }
        }
        .presentationDetents([.height(200)])
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
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
