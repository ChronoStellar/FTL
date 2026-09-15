//
//  Screens.swift
//  FTL — view
//
//  Thin wrappers that OWN their view model in `@State` and carry the screen's
//  toolbar.
//
//  Constructing a view model inside a `navigationDestination` or `sheet` closure
//  looks fine and is a bug: those closures re-run on every re-render, so the
//  screen gets a fresh view model — and loses whatever the user was part-way
//  through — on any unrelated state change. `@State` created once in `init` keeps
//  one instance for the life of the screen.
//

import SwiftUI

// MARK: - Bucket

struct BucketScreen: View {
    @State private var viewModel: BucketDetailViewModel
    private let name: String
    private let environment: AppEnvironment

    /// The row being corrected, or nil. `.sheet(item:)` rather than
    /// `isPresented` so the editor is rebuilt per row — see
    /// `EditTransactionScreen`.
    @State private var editing: LedgerTransaction?

    init(environment: AppEnvironment, categoryID: CategoryID, name: String, interval: DateInterval) {
        self.name = name
        self.environment = environment
        _viewModel = State(
            wrappedValue: environment.makeBucketDetailViewModel(
                categoryID: categoryID,
                name: name,
                interval: interval
            )
        )
    }

    var body: some View {
        // No Undo in this toolbar any more: the only thing it could undo was a
        // ceiling edit, and this screen no longer makes one.
        BucketDetailView(viewModel: viewModel, onEditTransaction: { editing = $0 })
            .background(GlowBackground())
            .sheet(item: $editing) { transaction in
                EditTransactionScreen(
                    environment: environment,
                    transaction: transaction,
                    onCancel: { editing = nil },
                    onSave: { edited in
                        editing = nil
                        Task { await viewModel.updateTransaction(edited) }
                    },
                    onDelete: {
                        editing = nil
                        Task { await viewModel.deleteTransaction(transaction) }
                    }
                )
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
    }
}

// MARK: - Sheets

struct ApprovalQueueScreen: View {
    @State private var viewModel: ApprovalQueueViewModel
    let onDone: () -> Void
    /// Fires each time a row leaves the queue, so Home behind this sheet keeps
    /// up. Assigned in `body` rather than `init` because the view model is
    /// owned by `@State` and must not be mutated while it is being constructed.
    let onSettled: () -> Void

    init(
        environment: AppEnvironment,
        onDone: @escaping () -> Void,
        onSettled: @escaping () -> Void = {}
    ) {
        self.onDone = onDone
        self.onSettled = onSettled
        _viewModel = State(wrappedValue: environment.makeApprovalQueueViewModel())
    }

    var body: some View {
        ApprovalQueueSheet(viewModel: viewModel, onDone: onDone)
            .onAppear { viewModel.onSettled = onSettled }
    }
}

struct IncomeSplitScreen: View {
    @State private var viewModel: IncomeSplitViewModel
    let onSkip: () -> Void
    let onSaved: () -> Void

    init(
        environment: AppEnvironment,
        interval: DateInterval,
        onSkip: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.onSkip = onSkip
        self.onSaved = onSaved
        _viewModel = State(wrappedValue: environment.makeIncomeSplitViewModel(interval: interval))
    }

    var body: some View {
        IncomeSplitView(viewModel: viewModel, onSkip: onSkip, onSaved: onSaved)
    }
}

/// Owns the editor's view model, keyed by the row being edited.
///
/// Presented with `.sheet(item:)` so a NEW view model is built for each row —
/// the `@State` warning at the top of this file cuts the other way here: the
/// draft must not survive from one transaction to the next.
struct EditTransactionScreen: View {
    @State private var viewModel: EditTransactionViewModel
    let onCancel: () -> Void
    let onSave: (LedgerTransaction) -> Void
    let onDelete: () -> Void

    init(
        environment: AppEnvironment,
        transaction: LedgerTransaction,
        onCancel: @escaping () -> Void,
        onSave: @escaping (LedgerTransaction) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _viewModel = State(wrappedValue: environment.makeEditTransactionViewModel(for: transaction))
    }

    var body: some View {
        EditTransactionSheet(
            viewModel: viewModel,
            onCancel: onCancel,
            onSave: onSave,
            onDelete: onDelete
        )
    }
}

struct AddSpendScreen: View {
    @State private var viewModel: AddSpendViewModel
    let onCancel: () -> Void
    let onCommit: () -> Void

    init(
        environment: AppEnvironment,
        interval: DateInterval,
        initialAmount: Int? = nil,
        onCancel: @escaping () -> Void,
        onCommit: @escaping () -> Void
    ) {
        self.onCancel = onCancel
        self.onCommit = onCommit
        _viewModel = State(wrappedValue: environment.makeAddSpendViewModel(interval: interval, initialAmount: initialAmount))
    }

    var body: some View {
        AddSpendSheet(viewModel: viewModel, onCancel: onCancel, onCommit: onCommit)
    }
}
