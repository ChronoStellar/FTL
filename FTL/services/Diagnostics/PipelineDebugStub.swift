//
//  PipelineDebugStub.swift
//  FTL — services/Diagnostics
//
//  Debug observability stub for the pipeline.
//  Tracks and logs when an agent is invoked (pattern synthesizer, category tagger),
//  when a pre-made preset parser is matched, when a hand-written imperative parser
//  runs, when emails are skipped, and how entries are settled.
//

import Foundation
import SwiftUI
import Observation

/// The provenance and origin of a parser that handled an email.
nonisolated enum ParserOrigin: Sendable, Hashable {
    case preset(id: String, version: Int, author: String)
    case agentLearned(id: String, version: Int, author: String, verifiedCount: Int, isVouched: Bool)
    case handWritten(id: String)
    case manual
    case unknown(id: String)

    var badgeText: String {
        switch self {
        case .preset(let id, _, _):
            return "📦 Pre-made: \(id)"
        case .agentLearned(let id, _, _, _, let vouched):
            return "🤖 Agent: \(id)" + (vouched ? " (vouched)" : " (unverified)")
        case .handWritten(let id):
            return "🛠️ Hardcoded: \(id)"
        case .manual:
            return "✍️ Manual"
        case .unknown(let id):
            return "❓ \(id)"
        }
    }

    var shortTag: String {
        switch self {
        case .preset: return "PRE-MADE"
        case .agentLearned: return "AGENT"
        case .handWritten: return "HARDCODED"
        case .manual: return "MANUAL"
        case .unknown: return "UNKNOWN"
        }
    }

    var isAgent: Bool {
        if case .agentLearned = self { return true }
        return false
    }

    var isPreset: Bool {
        if case .preset = self { return true }
        return false
    }
}

/// The origin of a category suggestion.
nonisolated enum TaggerSource: Sendable, Hashable {
    case agentModel(modelName: String, thinking: String?)
    case memory(agreed: Int, total: Int)
    case skipped(reason: String)

    var badgeText: String {
        switch self {
        case .agentModel: return "🤖 Agent Tagger"
        case .memory(let agreed, let total): return "🧠 Memory (\(agreed)/\(total))"
        case .skipped(let reason): return "⏭️ Tagger Skipped (\(reason))"
        }
    }

    var isAgent: Bool {
        if case .agentModel = self { return true }
        return false
    }
}

/// A structured debug event recorded by the stub.
nonisolated struct PipelineDebugEvent: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: Kind
    let title: String
    let subtitle: String
    let details: String
    let badge: String
    let tagColorName: String

    nonisolated enum Kind: Sendable, Hashable {
        case parserMatched(origin: ParserOrigin)
        case parserSkipped
        case taggerApplied(source: TaggerSource)
        case taggerSkipped
        case synthesisAttempt
        case queueSettlement
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        title: String,
        subtitle: String,
        details: String,
        badge: String,
        tagColorName: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.badge = badge
        self.tagColorName = tagColorName
    }
}

/// Observable diagnostic hub and logging stub for all agent and parser executions.
@Observable @MainActor
final class PipelineDebugStub {
    static let shared = PipelineDebugStub()

    // MARK: - Live Trace Store
    var events: [PipelineDebugEvent] = []
    private let maxStoredEvents = 250

    // MARK: - Cumulative Metrics
    var countPreMadeParsers: Int = 0
    var countAgentParsers: Int = 0
    var countHardcodedParsers: Int = 0
    var countSkippedEmails: Int = 0
    var countAgentTaggerCalls: Int = 0
    var countMemoryTaggerHits: Int = 0
    var countSettlements: Int = 0

    private init() {}

    func clear() {
        events.removeAll()
        countPreMadeParsers = 0
        countAgentParsers = 0
        countHardcodedParsers = 0
        countSkippedEmails = 0
        countAgentTaggerCalls = 0
        countMemoryTaggerHits = 0
        countSettlements = 0
    }

    func formattedLogDump() -> String {
        let header = """
        FTL PIPELINE DEBUG LOG DUMP
        Exported: \(Date().ISO8601Format())
        Summary:
          • Pre-made Preset Parsers Used: \(countPreMadeParsers)
          • Agent-Learned Parsers Used:   \(countAgentParsers)
          • Hard-coded Parsers Used:      \(countHardcodedParsers)
          • Skipped Emails (No parser):   \(countSkippedEmails)
          • Agent Category Tagger Calls:  \(countAgentTaggerCalls)
          • Memory Tagger Hits:           \(countMemoryTaggerHits)
          • Queue Settlements:            \(countSettlements)
        ================================================================================
        """
        let body = events.map { event in
            """
            [\(event.timestamp.formatted(date: .omitted, time: .standard))] [\(event.badge)] \(event.title)
              \(event.subtitle)
              \(event.details.replacingOccurrences(of: "\n", with: "\n  "))
            """
        }.joined(separator: "\n--------------------------------------------------------------------------------\n")
        return header + "\n\n" + body
    }

    private func appendEvent(_ event: PipelineDebugEvent) {
        events.insert(event, at: 0)
        if events.count > maxStoredEvents {
            events.removeLast(events.count - maxStoredEvents)
        }

        switch event.kind {
        case .parserMatched(let origin):
            switch origin {
            case .preset: countPreMadeParsers += 1
            case .agentLearned: countAgentParsers += 1
            case .handWritten: countHardcodedParsers += 1
            default: break
            }
        case .parserSkipped:
            countSkippedEmails += 1
        case .taggerApplied(let source):
            switch source {
            case .agentModel: countAgentTaggerCalls += 1
            case .memory: countMemoryTaggerHits += 1
            case .skipped: break
            }
        default: break
        }
    }

    // MARK: - Thread-Safe Dispatch Loggers

    /// Log parser matching and extraction
    nonisolated static func recordParserMatch(
        email: CapturedEmail,
        parser: any ReceiptParser,
        result: ReceiptParseResult,
        isVouched: Bool
    ) {
        let origin = classify(parser: parser, isVouched: isVouched)
        let (extractedText, flagsText) = summarize(result: result)

        let badge: String
        let color: String
        switch origin {
        case .preset(let id, _, _):
            badge = "PRE-MADE"
            color = "blue"
            printConsole(
                tag: "📦 PRE-MADE PARSER MATCH",
                lines: [
                    "Parser ID:     \(id) (author: hand-written-preset)",
                    "Email Subject: \"\(email.subject)\"",
                    "Sender Domain: \(email.senderDomain) (ID: \(email.id.prefix(12))…)",
                    "Extracted:     \(extractedText)",
                    "Review Flags:  \(flagsText)"
                ]
            )
        case .agentLearned(let id, _, let author, let verified, let vouched):
            badge = "AGENT PARSER"
            color = "purple"
            printConsole(
                tag: "🤖 AGENT PARSER MATCH",
                lines: [
                    "Pattern ID:    \(id)",
                    "Author:        \(author)",
                    "Verification:  \(verified) emails | Vouched: \(vouched ? "YES" : "NO (flagged unverified)")",
                    "Email Subject: \"\(email.subject)\"",
                    "Sender Domain: \(email.senderDomain) (ID: \(email.id.prefix(12))…)",
                    "Extracted:     \(extractedText)",
                    "Review Flags:  \(flagsText)"
                ]
            )
        case .handWritten(let id):
            badge = "HARDCODED"
            color = "orange"
            printConsole(
                tag: "🛠️ HARD-CODED PARSER MATCH",
                lines: [
                    "Parser ID:     \(id) (imperative Swift)",
                    "Email Subject: \"\(email.subject)\"",
                    "Sender Domain: \(email.senderDomain) (ID: \(email.id.prefix(12))…)",
                    "Extracted:     \(extractedText)",
                    "Review Flags:  \(flagsText)"
                ]
            )
        default:
            badge = "PARSER"
            color = "gray"
        }

        let event = PipelineDebugEvent(
            kind: .parserMatched(origin: origin),
            title: origin.badgeText,
            subtitle: "\(email.subject) · \(email.senderDomain)",
            details: "Result: \(extractedText)\nFlags: \(flagsText)\nEmail ID: \(email.id)",
            badge: badge,
            tagColorName: color
        )

        Task { @MainActor in
            PipelineDebugStub.shared.appendEvent(event)
        }
    }

    /// Log when an email is skipped because no parser claimed it
    nonisolated static func recordParserSkipped(
        email: CapturedEmail,
        activeParserIDs: [String]
    ) {
        printConsole(
            tag: "⏭️ EMAIL SKIPPED (NO PARSER)",
            lines: [
                "Email Subject: \"\(email.subject)\"",
                "Sender Domain: \(email.senderDomain) (ID: \(email.id.prefix(12))…)",
                "Active Parsers Checked (\(activeParserIDs.count)): \(activeParserIDs.prefix(4).joined(separator: ", "))" + (activeParserIDs.count > 4 ? "…" : "")
            ]
        )

        let event = PipelineDebugEvent(
            kind: .parserSkipped,
            title: "No Parser Claimed Email",
            subtitle: "\(email.subject) · \(email.senderDomain)",
            details: "Checked against \(activeParserIDs.count) active parsers.\nSender: \(email.senderDomain)\nMessage ID: \(email.id)",
            badge: "SKIPPED",
            tagColorName: "gray"
        )

        Task { @MainActor in
            PipelineDebugStub.shared.appendEvent(event)
        }
    }

    /// Log when category tagger was applied (Agent LLM vs TagMemory)
    nonisolated static func recordTaggerDecision(
        merchant: MerchantID,
        amount: Money?,
        categoryName: String,
        source: TaggerSource
    ) {
        let amtText = amount.map { MoneyFormatter.rp($0) } ?? "n/a"
        let badge: String
        let color: String
        let title: String
        let details: String

        switch source {
        case .agentModel(let modelName, let thinking):
            badge = "AGENT TAGGER"
            color = "purple"
            title = "🤖 Agent Proposed: \(categoryName)"
            let thinkText = thinking ?? "No chain-of-thought"
            details = "Merchant: \(merchant.rawValue)\nAmount: \(amtText)\nModel: \(modelName)\nReasoning: \(thinkText)"
            printConsole(
                tag: "🤖 AGENT TAGGER (LLM) CALLED",
                lines: [
                    "Merchant:  \"\(merchant.rawValue)\" | Amount: \(amtText)",
                    "Proposed:  \"\(categoryName)\"",
                    "Model:     \(modelName)",
                    "Thinking:  \"\(thinkText)\""
                ]
            )

        case .memory(let agreed, let total):
            badge = "TAG MEMORY"
            color = "teal"
            title = "🧠 Memory Suggested: \(categoryName)"
            details = "Merchant: \(merchant.rawValue)\nConfidence: Chose \(agreed) of last \(total) times\nAmount: \(amtText)"
            printConsole(
                tag: "🧠 TAG MEMORY LOOKUP",
                lines: [
                    "Merchant:  \"\(merchant.rawValue)\"",
                    "Suggested: \"\(categoryName)\"",
                    "History:   Agreed \(agreed) of the last \(total) settlements"
                ]
            )

        case .skipped(let reason):
            badge = "TAGGER SKIPPED"
            color = "gray"
            title = "⏭️ Tagger Skipped: \(merchant.rawValue)"
            details = "Reason: \(reason)\nAmount: \(amtText)"
            printConsole(
                tag: "⏭️ TAGGER SKIPPED",
                lines: [
                    "Merchant: \"\(merchant.rawValue)\"",
                    "Reason:   \(reason)"
                ]
            )
        }

        let event = PipelineDebugEvent(
            kind: .taggerApplied(source: source),
            title: title,
            subtitle: "Merchant: \(merchant.rawValue) (\(amtText))",
            details: details,
            badge: badge,
            tagColorName: color
        )

        Task { @MainActor in
            PipelineDebugStub.shared.appendEvent(event)
        }
    }

    /// Log when tagger refuses / skips an LLM call intentionally
    nonisolated static func recordTaggerSkipped(
        merchant: MerchantID,
        reason: String
    ) {
        recordTaggerDecision(
            merchant: merchant,
            amount: nil,
            categoryName: "Untagged",
            source: .skipped(reason: reason)
        )
    }

    /// Log when pattern synthesizer is invoked
    nonisolated static func recordSynthesis(
        domain: String,
        template: String,
        attempt: Int,
        outcome: String
    ) {
        printConsole(
            tag: "🧬 PATTERN SYNTHESIS LOOP",
            lines: [
                "Domain:   \(domain)",
                "Template: \"\(template)\" (Attempt \(attempt))",
                "Outcome:  \(outcome)"
            ]
        )

        let event = PipelineDebugEvent(
            kind: .synthesisAttempt,
            title: "Synthesis: \(domain) (Attempt \(attempt))",
            subtitle: outcome,
            details: "Template: \(template)\nDomain: \(domain)",
            badge: "SYNTHESIS",
            tagColorName: "indigo"
        )

        Task { @MainActor in
            PipelineDebugStub.shared.appendEvent(event)
        }
    }

    /// Log when an entry is settled in the approval queue
    nonisolated static func recordSettlement(
        entryID: UUID,
        merchant: String,
        parserOrigin: ParserOrigin?,
        verdict: String
    ) {
        let originText = parserOrigin?.badgeText ?? "unknown parser"
        printConsole(
            tag: "✍️ QUEUE SETTLEMENT",
            lines: [
                "Entry ID: \(entryID)",
                "Merchant: \"\(merchant)\"",
                "Verdict:  \(verdict)",
                "Parser:   \(originText)"
            ]
        )

        let event = PipelineDebugEvent(
            kind: .queueSettlement,
            title: "Settled: \(merchant) (\(verdict))",
            subtitle: "Parser: \(originText)",
            details: "Entry ID: \(entryID)\nVerdict: \(verdict)",
            badge: "SETTLED",
            tagColorName: "green"
        )

        Task { @MainActor in
            PipelineDebugStub.shared.appendEvent(event)
        }
    }

    // MARK: - Helpers

    nonisolated static func classify(parser: any ReceiptParser, isVouched: Bool) -> ParserOrigin {
        if let pdp = parser as? PatternDrivenParser {
            let pat = pdp.pattern
            if pat.author == "hand-written-preset" || PresetPatterns.isPreset(id: pat.id) {
                return .preset(id: pat.id, version: pat.version, author: pat.author)
            } else {
                return .agentLearned(
                    id: pat.id,
                    version: pat.version,
                    author: pat.author,
                    verifiedCount: pat.verifiedAgainst,
                    isVouched: isVouched
                )
            }
        }
        return .handWritten(id: parser.id.rawValue)
    }

    nonisolated static func classify(ruleID: RuleID) -> ParserOrigin {
        let raw = ruleID.rawValue
        if raw == "manual-entry" {
            return .manual
        }
        if PresetPatterns.isPreset(id: raw) {
            let version = Int(raw.split(separator: ":").last ?? "1") ?? 1
            return .preset(id: raw, version: version, author: "hand-written-preset")
        } else if ExtractionPattern.namesPattern(ruleID) {
            let version = Int(raw.split(separator: ":").last ?? "1") ?? 1
            return .agentLearned(id: raw, version: version, author: "synthesized", verifiedCount: 0, isVouched: false)
        } else {
            return .handWritten(id: raw)
        }
    }

    nonisolated private static func summarize(result: ReceiptParseResult) -> (extracted: String, flags: String) {
        switch result {
        case .parsed(let r):
            let amt = MoneyFormatter.rp(r.amount)
            let desc = "\(amt) at \"\(r.merchantRaw)\" [\(r.kind.rawValue)]"
            let flags = r.flags.isEmpty ? "none" : r.flags.map(\.reason.label).joined(separator: ", ")
            return (desc, flags)
        case .incomplete(let missing):
            return ("INCOMPLETE (missing: \(missing))", "unparseable")
        case .notAPurchase:
            return ("NOT A PURCHASE", "none")
        case .notApplicable:
            return ("NOT APPLICABLE", "none")
        }
    }

    nonisolated private static func printConsole(tag: String, lines: [String]) {
        let border = String(repeating: "─", count: 68)
        var msg = "\n┌\(border)\n│ [FTL:DEBUG] \(tag)\n"
        for line in lines {
            msg += "│   \(line)\n"
        }
        msg += "└\(border)"
        print(msg)
    }
}
