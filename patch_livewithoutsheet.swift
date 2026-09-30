import Foundation

let file = "FTL/services/AppEnvironment.swift"
var content = try String(contentsOfFile: file)

let search = """
    static func liveWithoutSheet() -> AppEnvironment {
        let base = Self.shared
        return AppEnvironment(
            auth: base.auth,
            ledger: InMemoryLedgerStore(empty: true),
            budgets: InMemoryBudgetStore(),
            provisional: base.provisional,
            isLive: base.isLive,
            captureLog: base.captureLog,
            patterns: base.patterns,
            tagMemory: base.tagMemory,
            patternMemory: base.patternMemory,
            merchantMemory: base.merchantMemory,
            isProvisionalStorePersistent: base.isProvisionalStorePersistent,
            ledgerBackend: .local
        )
    }
"""
let replace = """
    static func liveWithoutSheet() -> AppEnvironment {
        let base = Self.shared
        return AppEnvironment(
            auth: base.auth,
            ledger: InMemoryLedgerStore(empty: true),
            budgets: InMemoryBudgetStore(),
            provisional: base.provisional,
            analysisStore: base.analysisStore,
            isLive: base.isLive,
            captureLog: base.captureLog,
            patterns: base.patterns,
            tagMemory: base.tagMemory,
            patternMemory: base.patternMemory,
            merchantMemory: base.merchantMemory,
            isProvisionalStorePersistent: base.isProvisionalStorePersistent,
            ledgerBackend: .local
        )
    }
"""
content = content.replacingOccurrences(of: search, with: replace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
