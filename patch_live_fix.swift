import Foundation

let file = "FTL/services/AppEnvironment.swift"
var content = try String(contentsOfFile: file)

let search1 = """
            provisional: SwiftDataProvisionalStore(modelContainer: store.container),
            isLive: true,
            captureLog: SwiftDataCaptureLog(modelContainer: store.container),
"""
let replace1 = """
            provisional: SwiftDataProvisionalStore(modelContainer: store.container),
            analysisStore: SwiftDataAnalysisStore(modelContainer: store.container),
            isLive: true,
            captureLog: SwiftDataCaptureLog(modelContainer: store.container),
"""
content = content.replacingOccurrences(of: search1, with: replace1)

let search2 = """
            provisional: base.provisional,
            isLive: true, // we want to sync the mailbox and learn rules
"""
let replace2 = """
            provisional: base.provisional,
            analysisStore: base.analysisStore,
            isLive: true, // we want to sync the mailbox and learn rules
"""
content = content.replacingOccurrences(of: search2, with: replace2)

try content.write(toFile: file, atomically: true, encoding: .utf8)
