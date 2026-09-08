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
import SwiftData

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

    /// What the Gmail rail has already handled. Nil in `sample()` — fixtures
    /// have no mailbox to sync.
    let captureLog: CaptureLog?

    /// Patterns the synthesis loop has promoted. Nil in `sample()`.
    let patterns: PatternStore?

    /// False when the on-disk store couldn't be opened and the queue is running
    /// in memory for this session. Surfaced in Settings: a cache that silently
    /// stopped persisting looks identical to one that works, right up until a
    /// relaunch eats the queue.
    let isProvisionalStorePersistent: Bool

    /// True for `live()`, false for `sample()`. Gates `reconcileTagStore()` —
    /// syncing the on-device tag store from `.sample()`'s fixture categories
    /// would overwrite the real, persisted taxonomy with demo data — and gates
    /// the one-time income-split onboarding prompt for the same reason: fixture
    /// data isn't the user's real income to ask about.
    let isLive: Bool

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
        goals: GoalStore,
        isLive: Bool,
        captureLog: CaptureLog? = nil,
        patterns: PatternStore? = nil,
        isProvisionalStorePersistent: Bool = true
    ) {
        self.auth = auth
        self.ledger = ledger
        self.budgets = budgets
        self.provisional = provisional
        self.goals = goals
        self.isLive = isLive
        self.captureLog = captureLog
        self.patterns = patterns
        self.isProvisionalStorePersistent = isProvisionalStorePersistent
        self.calc = LedgerCalcTool(budgets: budgets, ledger: ledger)
        self.approvals = DefaultApprovalService(store: provisional, ledger: ledger)
    }

    /// The one live environment for this process.
    ///
    /// App Intents run inside the app, so an intent that built its own
    /// `live()` would open a SECOND SwiftData container on the same store
    /// file — two writers, one SQLite file. Both the UI and the intents go
    /// through this instead. `sample()` is unaffected: fixtures have no shared
    /// file to contend over.
    static let shared = live()

    /// The real app: the user's own Google Sheet is the ledger, and the
    /// provisional cache now survives a relaunch (SwiftData — Stage 0 #1).
    /// Approve before you quit is no longer load-bearing; it stays good practice.
    static func live(auth: GoogleAuthManager = .shared) -> AppEnvironment {
        let ledger = SheetsLedgerStore(auth: auth)
        // One container, both stores. The provisional queue and the capture log
        // are two tables in the same file, so they must not open it twice.
        let store = Self.makeProvisionalContainer()
        return AppEnvironment(
            auth: auth,
            ledger: ledger,
            budgets: SheetsBudgetStore(ledger: ledger),
            provisional: SwiftDataProvisionalStore(modelContainer: store.container),
            goals: InMemoryGoalStore(empty: true),
            isLive: true,
            captureLog: SwiftDataCaptureLog(modelContainer: store.container),
            patterns: SwiftDataPatternStore(modelContainer: store.container),
            isProvisionalStorePersistent: store.isPersistent
        )
    }

    /// On-disk if it can be, so the cache survives a relaunch — that is the
    /// entire point of Stage 0 #1. Falls back to an in-memory container only if
    /// the on-disk store can't be opened (disk full, an unreadable file left by
    /// a future breaking schema change): a cache that stops persisting for one
    /// session is recoverable — the ledger is still the Sheet — a launch-time
    /// crash on a finance app is not the trade to make for the same guarantee.
    /// Returns whether the store is actually on disk, because the fallback is
    /// otherwise INVISIBLE. A `print` doesn't exist in a release build: the app
    /// would run in memory, dedupe and the queue would look normal all session,
    /// and everything would evaporate on relaunch — the exact failure Stage 0 #1
    /// exists to prevent, arriving silently. Whoever holds this must be able to
    /// say so on screen.
    private static func makeProvisionalContainer() -> (container: ModelContainer, isPersistent: Bool) {
        let schema = Schema([ProvisionalEntryRecord.self, CapturedEmailRecord.self, ExtractionPatternRecord.self])
        do {
            return (try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)]), true)
        } catch {
            print("⚠️ on-disk container failed to open (\(error)) — falling back to in-memory.")
            // swiftlint:disable:next force_try — an in-memory container has no disk
            // I/O to fail on; if this throws the SwiftData runtime itself is broken.
            let memory = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            return (memory, false)
        }
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
            goals: InMemoryGoalStore(),
            isLive: false
        )
    }

    // MARK: - Tag store reconciliation

    /// Syncs TagStore's spend-category taxonomy from this ledger's actual
    /// budget categories, so the model classifier's vocabulary tracks whatever
    /// the user really set up in Sheets rather than a placeholder name they
    /// never chose — see TagStore.reconcile(spendCategories:). No-op in
    /// `.sample()`, and best-effort in `.live()`: a failed read here (offline,
    /// rate-limited) leaves TagStore exactly as it was, which still works.
    func reconcileTagStore() async {
        guard isLive else { return }
        guard let categories = try? await ledger.categories() else { return }
        try? await TagStore.shared.reconcile(spendCategories: categories)
    }

    // MARK: - View model factories
    //
    // Views ask the environment for a view model rather than building one, so the
    // dependency graph stays in this file.

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(calc: calc, ledger: ledger, provisional: provisional, goals: goals)
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
            budgets: budgets,
            ledger: ledger
        )
    }

    func makeApprovalQueueViewModel() -> ApprovalQueueViewModel {
        ApprovalQueueViewModel(store: provisional, approvals: approvals, ledger: ledger)
    }

    func makeAddSpendViewModel(interval: DateInterval) -> AddSpendViewModel {
        AddSpendViewModel(
            provisional: provisional,
            approvals: approvals,
            ledger: ledger,
            calc: calc,
            interval: interval
        )
    }

    func makeGoalViewModel() -> GoalViewModel {
        GoalViewModel(goals: goals)
    }

    /// The Gmail rail, when there is a mailbox and a place to log what it has
    /// seen. Nil in `sample()`.
    func makeGmailRail() -> GmailRail? {
        guard isLive, let captureLog else { return nil }
        return GmailRail(
            exporter: GmailExporter(auth: auth),
            parsers: [BluReceiptParser()],
            provisional: provisional,
            log: captureLog,
            patterns: patterns
        )
    }

    func makeIncomeSplitViewModel(interval: DateInterval) -> IncomeSplitViewModel {
        IncomeSplitViewModel(budgets: budgets, ledger: ledger, interval: interval)
    }

    // MARK: - Migration

    func makeLegacyMigration() -> LegacyMigration {
        LegacyMigration(auth: auth, ledger: ledger)
    }
}
