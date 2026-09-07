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
    // Built by `live()` (the user's Google Sheet) or `sample()` (fixtures).
    // Everything downstream sees protocols, so which one is in use is invisible
    // outside this file — that is what the protocols bought.
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

    private init(
        auth: GoogleAuthManager,
        ledger: LedgerStore,
        budgets: BudgetStore,
        provisional: ProvisionalStore,
        goals: GoalStore
    ) {
        self.auth = auth
        self.ledger = ledger
        self.budgets = budgets
        self.provisional = provisional
        self.goals = goals
        self.calc = LedgerCalcTool(budgets: budgets, ledger: ledger)
        self.approvals = DefaultApprovalService(store: provisional, ledger: ledger)
    }

    /// The real app: the user's own Google Sheet is the ledger.
    ///
    /// The provisional cache is still in memory, so rows awaiting approval do not
    /// survive a relaunch. That is the next thing to fix (GRDB) and it is a real
    /// gap, not a stub — approve before you quit.
    static func live(auth: GoogleAuthManager = .shared) -> AppEnvironment {
        let ledger = SheetsLedgerStore(auth: auth)
        return AppEnvironment(
            auth: auth,
            ledger: ledger,
            budgets: SheetsBudgetStore(ledger: ledger),
            provisional: InMemoryProvisionalStore(),
            goals: InMemoryGoalStore()
        )
    }

    /// Fixtures. Used by the DEBUG skip-sign-in path so the UI can be worked on
    /// without an account, and by previews.
    static func sample(auth: GoogleAuthManager = .shared) -> AppEnvironment {
        let ledger = InMemoryLedgerStore()
        let budgets = InMemoryBudgetStore()
        return AppEnvironment(
            auth: auth,
            ledger: ledger,
            budgets: budgets,
            provisional: InMemoryProvisionalStore(),
            goals: InMemoryGoalStore()
        )
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
