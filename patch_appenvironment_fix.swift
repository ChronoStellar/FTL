import Foundation

let file = "FTL/services/AppEnvironment.swift"
var content = try String(contentsOfFile: file)

let search = """
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
"""
let replace = """
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
        isProvisionalStorePersistent: Bool = true,
        ledgerBackend: LedgerBackend = .sheets
    ) {
"""
content = content.replacingOccurrences(of: search, with: replace)

let search2 = """
            isProvisionalStorePersistent: store.isPersistent,
            ledgerBackend: .sheets
        )
"""
let replace2 = """
            isProvisionalStorePersistent: store.isPersistent,
            ledgerBackend: .sheets
        )
"""
// Wait, I should just make sure I got all instances.

try content.write(toFile: file, atomically: true, encoding: .utf8)
