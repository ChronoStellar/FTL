//
//  EditTransactionSheet.swift
//  FTL — view/Capture · Phase 1
//
//  Correcting a row that is already in the ledger. Reached by tapping any
//  spending row — on Home, and in a bucket.
//
//  NATIVE CONTROLS, deliberately, and the one screen in the app where that is
//  the right call. Everywhere else the design system earns its keep because the
//  thing being drawn is a number against a ceiling and nothing standard renders
//  that well. Here the job is a form: a keyboard, a segmented control, two
//  pickers. `Form` brings correct keyboard avoidance, correct picker
//  presentation, correct Dynamic Type, correct VoiceOver ordering and correct
//  focus handling — all of which a bespoke version would have to earn back one
//  bug at a time, and none of which is visible when it works.
//
//  What it does NOT inherit is the palette: `Form` rows are system-coloured, so
//  they are painted with FTL tokens row by row. The app forces
//  `.preferredColorScheme(.dark)` at the root, so the system chrome inside is
//  already dark.
//
//  `merchantRaw` is shown and not editable — Invariant 3, and the type enforces
//  it. A person correcting a figure needs to see the string it was read out of.
//

import SwiftUI

struct EditTransactionSheet: View {
    @Bindable var viewModel: EditTransactionViewModel
    let onCancel: () -> Void
    let onSave: (LedgerTransaction) -> Void
    let onDelete: () -> Void

    @FocusState private var isAmountFocused: Bool
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                typeSection
                bucketSection
                noteSection
                sourceSection
                deleteSection
            }
            .scrollContentBackground(.hidden)
            .background(FTLColor.sheetBackground)
            .tint(FTLColor.textPrimary)
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.sheetBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .tint(FTLColor.textTertiary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(viewModel.edited) }
                        .font(FTLTypography.navTitle)
                        .tint(viewModel.canSave ? FTLColor.textSecondary : FTLColor.textDisabled)
                        .disabled(!viewModel.canSave)
                }
                // The number pad has no return key. Same trap as the income
                // sheet: without this the keyboard covers the form forever.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isAmountFocused = false }
                }
            }
            .task { await viewModel.load() }
            .confirmationDialog(
                "Delete this transaction?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(viewModel.title) · \(MoneyFormatter.rp(viewModel.amount)) will be removed from your Google Sheet.")
            }
        }
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
    }

    // MARK: - Sections

    private var amountSection: some View {
        Section {
            HStack(spacing: 6) {
                Text("Rp")
                    .font(FTLTypography.amountEmphasis)
                    .foregroundStyle(FTLColor.textTertiary)
                TextField("0", text: $viewModel.amountDigits)
                    .keyboardType(.numberPad)
                    .focused($isAmountFocused)
                    .font(FTLTypography.displaySmall)
                    .foregroundStyle(FTLColor.textPrimary)
                    // Paste is the reason this exists: "Rp 34.500" arriving in
                    // the field would otherwise read back as zero.
                    .onChange(of: viewModel.amountDigits) { _, _ in viewModel.sanitizeAmount() }
            }
        } header: {
            Text("Amount")
        } footer: {
            Text("What was actually charged. Correcting this rewrites the row in your Sheet — the merchant it was parsed from is kept as-is.")
        }
        .listRowBackground(FTLColor.panel)
    }

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $viewModel.kind) {
                Text("Spend").tag(TransactionKind.spend)
                Text("Not a spend").tag(TransactionKind.nonSpend)
            }
            .pickerStyle(.segmented)

            // Invariant 5: non-spend is LABELLED, never deleted. This is the
            // label, so it appears the moment the row becomes one.
            if viewModel.kind == .nonSpend {
                Picker("Kind", selection: $viewModel.nonSpendType) {
                    ForEach(NonSpendType.allCases, id: \.self) { type in
                        Text(Self.label(for: type)).tag(type)
                    }
                }
            }
        } header: {
            Text("Type")
        } footer: {
            Text(viewModel.kind == .spend
                 ? "Counts against its bucket's ceiling."
                 : "Kept in the ledger and left out of every spend total. A refund does not cancel the purchase it reverses — both rows stay.")
        }
        .listRowBackground(FTLColor.panel)
    }

    private var bucketSection: some View {
        Section {
            Picker("Bucket", selection: $viewModel.categoryID) {
                Text("None").tag(CategoryID?.none)
                ForEach(viewModel.categories) { category in
                    Text(category.name).tag(CategoryID?.some(category.id))
                }
            }
        } header: {
            Text("Bucket")
        }
        .listRowBackground(FTLColor.panel)
    }

    private var noteSection: some View {
        Section {
            TextField("Note", text: $viewModel.note, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(FTLColor.textPrimary)
        } header: {
            Text("Note")
        }
        .listRowBackground(FTLColor.panel)
    }

    /// Read-only. How the row got here, which is the context for deciding
    /// whether the figure above it is wrong.
    private var sourceSection: some View {
        Section {
            LabeledContent("Captured from", value: viewModel.original.source.rawValue.capitalized)
            LabeledContent("As read") {
                Text(viewModel.original.merchantRaw)
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.textQuaternary)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Date", value: viewModel.original.date.formatted(date: .abbreviated, time: .omitted))
        } header: {
            Text("Origin")
        } footer: {
            Text("Kept exactly as captured. These are the record of where the row came from, not a judgement about it.")
        }
        .listRowBackground(FTLColor.panel)
    }

    private var deleteSection: some View {
        Section {
            Button("Delete transaction", role: .destructive) {
                isConfirmingDelete = true
            }
            .tint(FTLColor.destructive)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .listRowBackground(FTLColor.panel)
    }

    // MARK: - Copy

    private static func label(for type: NonSpendType) -> String {
        switch type {
        case .transfer: return "Transfer between my accounts"
        case .topup: return "Top-up"
        case .creditCardPayment: return "Credit card payment"
        case .cashback: return "Cashback"
        case .refund: return "Refund"
        case .incoming: return "Money in"
        }
    }
}
