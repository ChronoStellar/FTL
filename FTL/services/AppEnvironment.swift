//
//  AppEnvironment.swift
//  FTL — services
//
//  The composition root, and the ONLY file allowed to name a concrete service
//  type. Everything else — every view model, every pipeline stage — receives a
//  protocol from model/Contracts.
//
//  If a `SheetsLedgerStore()` or `GRDBProvisionalStore()` appears anywhere else,
//  that layer just became untestable. Move it here.
//

import Foundation

@MainActor
final class AppEnvironment {
    let auth: GoogleAuthManager

    // MARK: - Phase 1
    //
    // ⚠️ Currently the InMemory placeholders from services/Preview. Swapping in
    // the real stores is a change to `init` and nothing else — that is what the
    // protocols bought.
    let ledger: LedgerStore
    let budgets: BudgetStore
    let calc: CalcTool
    let provisional: ProvisionalStore
    let approvals: ApprovalService
    let goals: GoalStore

    // MARK: - Phase 2
    //
    // The two model jobs. Contracts exist so the spine is built against the right
    // seams; do not construct these early.
    //
    // let languageGate: LanguageGate
    // let classifier: PurchaseClassifier
    // let reasoner: ResultReasoner

    /// Pinned. `.auto` does not ship until accuracy is re-measured — the last run
    /// put unattended writes at 67% correct.
    let trustLevel: TrustLevel = .assist

    init(auth: GoogleAuthManager = .shared) {
        self.auth = auth

        let ledger = InMemoryLedgerStore()
        let budgets = InMemoryBudgetStore()
        let provisional = InMemoryProvisionalStore()

        self.ledger = ledger
        self.budgets = budgets
        self.provisional = provisional
        self.calc = InMemoryCalcTool(budgets: budgets, store: ledger)
        self.approvals = InMemoryApprovalService(store: provisional, ledger: ledger)
        self.goals = InMemoryGoalStore()
    }

    // MARK: - View model factories
    //
    // Views ask the environment for a view model rather than building one, so the
    // dependency graph stays in this file.

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(calc: calc, provisional: provisional, goals: goals)
    }

    func makeBucketDetailViewModel(
        categoryID: CategoryID,
        name: String,
        interval: DateInterval
    ) -> BucketDetailViewModel {
        BucketDetailViewModel(
            categoryID: categoryID,
            name: name,
            interval: interval,
            calc: calc,
            budgets: budgets
        )
    }

    func makeApprovalQueueViewModel() -> ApprovalQueueViewModel {
        ApprovalQueueViewModel(store: provisional, approvals: approvals, ledger: ledger)
    }

    func makeAddSpendViewModel(interval: DateInterval) -> AddSpendViewModel {
        AddSpendViewModel(provisional: provisional, ledger: ledger, calc: calc, interval: interval)
    }

    func makeGoalViewModel() -> GoalViewModel {
        GoalViewModel(goals: goals)
    }
}
