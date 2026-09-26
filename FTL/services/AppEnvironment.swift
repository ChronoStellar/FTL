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

    /// What the Gmail rail has already handled. Nil in `sample()` — fixtures
    /// have no mailbox to sync.
    let captureLog: CaptureLog?

    /// Patterns the synthesis loop has promoted. Nil in `sample()`.
    let patterns: PatternStore?

    /// What you decided about each merchant — the second tool's only source of
    /// truth, and the evidence the trust ladder's third rung is earned against
    /// (Invariant 10). Nil in `sample()`: fixture approvals are not decisions
    /// about anyone's real budget and must not accrue as if they were.
    let tagMemory: TagMemory?

    /// What the queue has said about the rows each learned pattern produced —
    /// and on a mailbox with no hand-written parser, the only oracle tool 1
    /// has. See `PatternMemory`.
    let patternMemory: PatternMemory?
    /// What you call each shop. See `MerchantMemory`.
    let merchantMemory: MerchantMemory?

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
    ///
    /// Also true for `liveWithoutSheet()` — a real mailbox is being synced and
    /// the loop is really learning, so everything gated on "is this a real
    /// session" should still run. What differs there is only `ledger` and
    /// `budgets`; see `LedgerBackend`.
    let isLive: Bool

    /// What backs `ledger` and `budgets`. Purely descriptive — nothing branches
    /// on it except the Debug screen, and that is exactly where a stress-test
    /// session and a real one must never look alike by accident.
    nonisolated enum LedgerBackend: String {
        case sheets = "Google Sheet"
        case local = "Local (no spreadsheet)"
        case sample = "Fixtures"
    }

    let ledgerBackend: LedgerBackend

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

    /// True when the loop should learn EVERY sender itself — no preset
    /// patterns, no hand-authored oracle. Toggling this on drops blu's
    /// preset (`presets: []` in `makeGmailRail`) and swaps `BluReceiptParser`
    /// out of the synthesis oracle for `NoOracle`, so even a sender this app
    /// already has a known-good answer for has to be discovered, learned and
    /// promoted the same coverage-only way a genuinely unseen sender would
    /// (`PatternVerifier`'s `attempted == 0` path, always `.provisional`
    /// until the queue itself vouches for it — `PatternTrustPolicy`).
    ///
    /// This is "the mailbox nobody has looked at" (see `CLAUDE.md`), made
    /// testable on a mailbox this app has actually been tuned against — the
    /// one honest way to check "the agent recognises the pattern on its own"
    /// rather than assume it because a preset is quietly doing the work.
    ///
    /// UserDefaults-backed rather than a stored property: read fresh by
    /// `makeGmailRail()`/`makeDiscoveryContext()` on every call, so flipping
    /// it takes effect on the NEXT sync with no environment rebuild needed.
    /// DEBUG-only surface (Settings → Developer).
    ///
    /// Defaults OFF (a preset exists precisely to keep spend flowing while the
    /// loop is proven elsewhere). The `object(forKey:) == nil` check is what makes
    /// this only a fallback: the Debug toggle's explicit `set` below always
    /// wins over it, on either value, and persists across relaunches like any
    /// other UserDefaults write.
    var pureAgentMode: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.pureAgentModeKey) != nil else { return false }
            return UserDefaults.standard.bool(forKey: Self.pureAgentModeKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.pureAgentModeKey) }
    }
    private static let pureAgentModeKey = "ftl_pure_agent_mode"

    /// Fetches mail when the app becomes active, without anybody asking.
    ///
    /// Lives here rather than in a view because the throttle has to survive
    /// every screen rebuild — a per-view timer would re-fetch on each
    /// navigation. Held lazily so `sample()` and a signed-out session build one
    /// that simply never has a rail to run.
    private(set) lazy var autoSync = AutoSync { [weak self] in self?.makeGmailRail() }

    /// The agent extending its own reach: discovery → synthesis → promote,
    /// unattended. See `DiscoverySync` for why it is a separate trigger from
    /// `autoSync` rather than folded into it.
    private(set) lazy var discoverySync = DiscoverySync { [weak self] in self?.makeDiscoveryContext() }

    private init(
        auth: GoogleAuthManager,
        ledger: LedgerStore,
        budgets: BudgetStore,
        provisional: ProvisionalStore,
        isLive: Bool,
        captureLog: CaptureLog? = nil,
        patterns: PatternStore? = nil,
        tagMemory: TagMemory? = nil,
        patternMemory: PatternMemory? = nil,
        merchantMemory: MerchantMemory? = nil,
        isProvisionalStorePersistent: Bool = true,
        ledgerBackend: LedgerBackend = .sheets
    ) {
        self.auth = auth
        self.ledger = ledger
        self.budgets = budgets
        self.provisional = provisional
        self.isLive = isLive
        self.captureLog = captureLog
        self.patterns = patterns
        self.tagMemory = tagMemory
        self.patternMemory = patternMemory
        self.merchantMemory = merchantMemory
        self.isProvisionalStorePersistent = isProvisionalStorePersistent
        self.ledgerBackend = ledgerBackend
        self.calc = LedgerCalcTool(budgets: budgets, ledger: ledger)
        self.approvals = DefaultApprovalService(
            store: provisional,
            ledger: ledger,
            tags: tagMemory,
            patterns: patternMemory,
            merchants: merchantMemory
        )
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
            isLive: true,
            captureLog: SwiftDataCaptureLog(modelContainer: store.container),
            patterns: SwiftDataPatternStore(modelContainer: store.container),
            tagMemory: SwiftDataTagMemory(modelContainer: store.container),
            patternMemory: SwiftDataPatternMemory(modelContainer: store.container),
            merchantMemory: SwiftDataMerchantMemory(modelContainer: store.container),
            isProvisionalStorePersistent: store.isPersistent,
            ledgerBackend: .sheets
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
        let schema = Schema([
            ProvisionalEntryRecord.self,
            CapturedEmailRecord.self,
            ExtractionPatternRecord.self,
            // The one table here with no upstream copy — the ledger can be
            // re-read from the Sheet and the queue re-approved, but a lost
            // decision history is everything the tagger learned about your
            // buckets, gone. See SwiftDataTagMemory.
            TagDecisionRecord.self,
            MerchantNameRecord.self,
            PatternObservationRecord.self,
        ])
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
            isLive: false,
            merchantMemory: InMemoryMerchantMemory(),
            ledgerBackend: .sample
        )
    }

    /// A real mailbox, with no spreadsheet needed at all.
    ///
    /// Reuses `.shared`'s already-open SwiftData container — `provisional`,
    /// `captureLog`, `patterns`, `tagMemory` are the SAME instances `.shared`
    /// uses — and swaps only `ledger` and `budgets` for in-memory ones. Only
    /// `ledger`, `budgets`, and what's built from them (`calc`, `approvals`)
    /// are new.
    ///
    /// Deliberately NOT a second `live()` call: that would open a SECOND
    /// SwiftData container on the same on-disk file, which is exactly the
    /// hazard `.shared`'s own doc comment exists to prevent. `.shared` is
    /// already constructed by the time anything can call this (FTLApp builds
    /// it unconditionally at launch), so reusing it costs nothing extra and
    /// keeps the app to the one container it has ever opened.
    ///
    /// What this buys, and why it exists: the app should work for someone who
    /// has never set up a spreadsheet, and stress-testing the capture →
    /// discovery → tag loop against a real mailbox at volume has no business
    /// writing hundreds of test rows into anyone's real ledger. `ledger`
    /// starts empty and lives only for this process — nothing here is
    /// durable, and nothing here is canonical (Invariant 7 still holds; there
    /// is just no Sheet backing it).
    ///
    /// DEBUG-only entry point — see `SignInView`.
    static func liveWithoutSheet() -> AppEnvironment {
        let base = Self.shared
        return AppEnvironment(
            auth: base.auth,
            ledger: InMemoryLedgerStore(empty: true),
            budgets: InMemoryBudgetStore(),
            provisional: base.provisional,
            isLive: true,
            captureLog: base.captureLog,
            patterns: base.patterns,
            tagMemory: base.tagMemory,
            patternMemory: base.patternMemory,
            merchantMemory: base.merchantMemory,
            isProvisionalStorePersistent: base.isProvisionalStorePersistent,
            ledgerBackend: .local
        )
    }

    // MARK: - View model factories
    //
    // Views ask the environment for a view model rather than building one, so the
    // dependency graph stays in this file.

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(calc: calc, ledger: ledger, provisional: provisional)
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
            ledger: ledger
        )
    }

    func makeApprovalQueueViewModel() -> ApprovalQueueViewModel {
        ApprovalQueueViewModel(
            store: provisional,
            approvals: approvals,
            ledger: ledger,
            budgets: budgets,
            // The queue is where the tagger earns its keep: every load
            // re-derives what you have settled, so a decision made on one row
            // is visible on the next one down. See `PurchaseTagger`.
            tagger: makePurchaseTagger(),
            // Same reasoning, applied to `unverifiedPattern` instead of a tag
            // suggestion — see `ApprovalQueueViewModel.reviseUnverifiedFlags`.
            trust: patternMemory,
            merchants: merchantMemory
        )
    }

    func makeAddSpendViewModel(interval: DateInterval, initialAmount: Int? = nil) -> AddSpendViewModel {
        AddSpendViewModel(
            provisional: provisional,
            approvals: approvals,
            ledger: ledger,
            calc: calc,
            interval: interval,
            initialAmount: initialAmount
        )
    }

    /// Handed `ledger` as a `CategorySource`, not a `LedgerStore`. The editor
    /// needs to know what the buckets are and has no business being able to
    /// write a transaction — the screen that owns the list does that.
    func makeEditTransactionViewModel(for transaction: LedgerTransaction) -> EditTransactionViewModel {
        EditTransactionViewModel(transaction: transaction, categories: ledger)
    }

    /// The Gmail rail, when there is a mailbox and a place to log what it has
    /// seen. Nil in `sample()`.
    /// `tagged: false` drops the tagger from the rail.
    ///
    /// For a background run, which gets roughly 30 seconds before iOS kills it.
    /// `FoundationModelTagger` is bounded at 8 model calls and the measured p95
    /// is 3.82s each — up to 30 seconds on its own, spent before a single row is
    /// written. Nothing is lost by skipping it: the tagger's memory half runs on
    /// every queue load (`PurchaseTagger.refresh`), so rows captured in the
    /// background arrive tagged the moment the queue is opened.
    func makeGmailRail(tagged: Bool = true) -> GmailRail? {
        guard isLive, let captureLog else { return nil }
        return GmailRail(
            exporter: GmailExporter(auth: auth),
            // Empty, deliberately. `BluReceiptParser` is the ORACLE the
            // verifier scores proposals against, not a reader that sits in
            // front of the loop — see `GmailRail.activeParsers`. blu is covered
            // by a preset pattern instead, which the audit measured as an exact
            // reproduction (116/116) — unless `pureAgentMode` says to take even
            // that away.
            parsers: [],
            provisional: provisional,
            log: captureLog,
            ledger: ledger,
            patterns: patterns,
            presets: pureAgentMode ? [] : PresetPatterns.load(),
            tagger: tagged ? makePurchaseTagger() : nil,
            trust: patternMemory
        )
    }

    /// What `discoverySync` needs to run one bounded sweep, or nil under the
    /// same conditions as `makeGmailRail()` — discovery needs the same
    /// mailbox and the same place to store what it learns, and it reuses the
    /// rail's own `activeParsers()` so "unread" means the same thing in both
    /// places (see `DiscoverySync.Context.activeParsers`).
    func makeDiscoveryContext() -> DiscoverySync.Context? {
        guard isLive, let patterns, let rail = makeGmailRail() else { return nil }
        return DiscoverySync.Context(
            source: GmailExporter(auth: auth),
            discovery: PatternDiscovery(
                learner: DefaultPatternLearner(
                    synthesizer: FoundationModelSynthesizer(),
                    // The only sender this can verify against a real oracle
                    // is blu — everything else falls through to coverage,
                    // same as the manual "Discovery" run in the Debug screen.
                    // `pureAgentMode` removes that one exception too, so
                    // nothing here is ever graded against a hand-written
                    // answer — see `pureAgentMode`'s own doc comment.
                    oracle: pureAgentMode ? NoOracle() : ParserOracle(BluReceiptParser())
                ),
                // "One sender per launch" — see DiscoverySync for why this is
                // tighter than the Debug screen's manual button (3). Same
                // reasoning for the near-miss top-up: one extra live Gmail
                // fetch per launch, not three.
                maxSendersPerRun: 1,
                maxNearMissesPerRun: 1
            ),
            patterns: patterns,
            activeParsers: rail.activeParsers
        )
    }

    /// The second tool, or nil when there is nothing for it to remember with.
    ///
    /// The model half is passed only when the device actually has a model, so a
    /// machine without one still gets the deterministic lookup — which is the
    /// wide path anyway, and the half that is right about the merchants you
    /// have actually settled.
    func makePurchaseTagger() -> (any PurchaseTagger)? {
        guard let tagMemory else { return nil }
        return DefaultPurchaseTagger(
            memory: tagMemory,
            proposer: FoundationModelTagger.isAvailable ? FoundationModelTagger() : nil,
            ledger: ledger
        )
    }

    func makeIncomeSplitViewModel(interval: DateInterval) -> IncomeSplitViewModel {
        IncomeSplitViewModel(budgets: budgets, ledger: ledger, interval: interval)
    }

    // MARK: - Migration

}
