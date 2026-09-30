import Foundation

let file = "FTL/services/AppEnvironment.swift"
var content = try String(contentsOfFile: file)

let search1 = """
    let merchantMemory: MerchantMemory?
"""
let replace1 = """
    let merchantMemory: MerchantMemory?
    
    /// Stored analysis reports per month.
    let analysisStore: AnalysisStore
"""
content = content.replacingOccurrences(of: search1, with: replace1)

let search2 = """
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
        ledgerBackend: LedgerBackend,
        isProvisionalStorePersistent: Bool = true
    ) {
"""
let replace2 = """
    private init(
        auth: GoogleAuthManager,
        ledger: LedgerStore,
        budgets: BudgetStore,
        provisional: ProvisionalStore,
        analysisStore: AnalysisStore,
        isLive: Bool,
        captureLog: CaptureLog? = nil,
        patterns: PatternStore? = nil,
        tagMemory: TagMemory? = nil,
        patternMemory: PatternMemory? = nil,
        merchantMemory: MerchantMemory? = nil,
        ledgerBackend: LedgerBackend,
        isProvisionalStorePersistent: Bool = true
    ) {
"""
content = content.replacingOccurrences(of: search2, with: replace2)

let search3 = """
        self.provisional = provisional
"""
let replace3 = """
        self.provisional = provisional
        self.analysisStore = analysisStore
"""
content = content.replacingOccurrences(of: search3, with: replace3)

let searchLive = """
        return AppEnvironment(
            auth: auth,
            ledger: ledger,
            budgets: SheetsBudgetStore(ledger: ledger),
            provisional: SwiftDataProvisionalStore(modelContainer: store.container),
            isLive: true,
            captureLog: SwiftDataCaptureLog(modelContainer: store.container),
            patterns: SwiftDataPatternStore(modelContainer: store.container),
            tagMemory: tagMemory,
            patternMemory: SwiftDataPatternMemory(modelContainer: store.container),
            merchantMemory: merchantMemory,
            ledgerBackend: .sheets,
            isProvisionalStorePersistent: store.isPersistent
        )
"""
let replaceLive = """
        return AppEnvironment(
            auth: auth,
            ledger: ledger,
            budgets: SheetsBudgetStore(ledger: ledger),
            provisional: SwiftDataProvisionalStore(modelContainer: store.container),
            analysisStore: SwiftDataAnalysisStore(modelContainer: store.container),
            isLive: true,
            captureLog: SwiftDataCaptureLog(modelContainer: store.container),
            patterns: SwiftDataPatternStore(modelContainer: store.container),
            tagMemory: tagMemory,
            patternMemory: SwiftDataPatternMemory(modelContainer: store.container),
            merchantMemory: merchantMemory,
            ledgerBackend: .sheets,
            isProvisionalStorePersistent: store.isPersistent
        )
"""
content = content.replacingOccurrences(of: searchLive, with: replaceLive)

let searchLiveW = """
        return AppEnvironment(
            auth: auth,
            ledger: InMemoryLedgerStore(),
            budgets: InMemoryBudgetStore(),
            provisional: SwiftDataProvisionalStore(modelContainer: store.container),
            isLive: true, // we want to sync the mailbox and learn rules
            captureLog: SwiftDataCaptureLog(modelContainer: store.container),
            patterns: SwiftDataPatternStore(modelContainer: store.container),
            tagMemory: tagMemory,
            patternMemory: SwiftDataPatternMemory(modelContainer: store.container),
            merchantMemory: merchantMemory,
            ledgerBackend: .local,
            isProvisionalStorePersistent: store.isPersistent
        )
"""
let replaceLiveW = """
        return AppEnvironment(
            auth: auth,
            ledger: InMemoryLedgerStore(),
            budgets: InMemoryBudgetStore(),
            provisional: SwiftDataProvisionalStore(modelContainer: store.container),
            analysisStore: SwiftDataAnalysisStore(modelContainer: store.container),
            isLive: true, // we want to sync the mailbox and learn rules
            captureLog: SwiftDataCaptureLog(modelContainer: store.container),
            patterns: SwiftDataPatternStore(modelContainer: store.container),
            tagMemory: tagMemory,
            patternMemory: SwiftDataPatternMemory(modelContainer: store.container),
            merchantMemory: merchantMemory,
            ledgerBackend: .local,
            isProvisionalStorePersistent: store.isPersistent
        )
"""
content = content.replacingOccurrences(of: searchLiveW, with: replaceLiveW)

let searchSample = """
        return AppEnvironment(
            auth: auth,
            ledger: ledger,
            budgets: budgets,
            provisional: InMemoryProvisionalStore(),
            isLive: false,
            merchantMemory: InMemoryMerchantMemory(),
            ledgerBackend: .sample
        )
"""
let replaceSample = """
        return AppEnvironment(
            auth: auth,
            ledger: ledger,
            budgets: budgets,
            provisional: InMemoryProvisionalStore(),
            analysisStore: InMemoryAnalysisStore(),
            isLive: false,
            merchantMemory: InMemoryMerchantMemory(),
            ledgerBackend: .sample
        )
"""
content = content.replacingOccurrences(of: searchSample, with: replaceSample)

let searchSchema = """
            TagDecisionRecord.self,
            MerchantNameRecord.self,
            PatternObservationRecord.self,
        ])
"""
let replaceSchema = """
            TagDecisionRecord.self,
            MerchantNameRecord.self,
            PatternObservationRecord.self,
            AnalysisReportRecord.self,
        ])
"""
content = content.replacingOccurrences(of: searchSchema, with: replaceSchema)

try content.write(toFile: file, atomically: true, encoding: .utf8)
