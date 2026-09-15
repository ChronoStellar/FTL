//
//  Evaluator.swift
//  FTL — services/Evaluation
//
//  Runs a classifier over the corpus and emits a report. NOT a unit test:
//  Foundation Models only runs on-device, its output is nondeterministic, and at
//  a 3.8s p95 a thousand emails is an hour. That is a measurement run, and its
//  product is a number you can argue with.
//
//  The same harness measures a deterministic parser and the model, because the
//  question is identical — how often is it right, and when it is wrong, does it
//  say so? Run the parser first: whatever it settles is work the model never has
//  to see, and the gap between them is the model's actual job.
//

import Foundation

/// Anything that can produce a verdict for one email. A `ReceiptParser` and a
/// `PurchaseClassifier` both fit, which is the point.
protocol EmailJudge: Sendable {
    var name: String { get }
    func judge(_ email: CapturedEmail) async -> Verdict
}

nonisolated struct Verdict: Sendable {
    var isPurchase: Bool
    var amount: Money?
    var merchantRaw: String?
    var kind: TransactionKind?
    var confidence: Double?
    var flags: [ReviewFlag]
    var refused: Bool = false
    var thinking: String? = nil
    var transactionType: String? = nil
    var taggedKeywords: [String] = []
    var dateString: String? = nil
    var serviceProvider: String? = nil
    /// nil covers two different things: a deterministic parser (kind isn't its
    /// job to report) and a classifier verdict where the category said
    /// not-a-transaction. Distinguish them via `isPurchase`.
    var nonSpendType: NonSpendType? = nil

    // MARK: - Latency instrumentation
    //
    // Same email, different wall-clock time, more than once. These three are the
    // candidate explanations that live inside a single `classify()` call — how
    // much the model asked for, how much it wrote back, how much it was given to
    // read. Filled in by FoundationModelClassifier; zero for a deterministic
    // ReceiptParser, which makes neither tool calls nor a chosen-length answer.

    /// How many times the model invoked a tool before answering. Each call is a
    /// full extra inference round trip — this is usually the dominant variable.
    var toolCallCount: Int = 0
    /// Total characters across the model's free-text output fields (`thinking`,
    /// `taggedKeywords`, `reviewReason`). A proxy for output tokens, which is what
    /// on-device generation cost is actually dominated by.
    var outputCharacterCount: Int = 0
    /// Characters of email content actually sent to the model, after the 4000-char
    /// cap. Varies well below the cap on shorter emails.
    var inputCharacterCount: Int = 0

    static let notAPurchase = Verdict(isPurchase: false, flags: [])
}

// MARK: - Individual Item Result

nonisolated struct ItemResult: Sendable, Codable, Identifiable {
    var id: String
    var date: String
    var subject: String
    var from: String
    var isPurchase: Bool
    var transactionType: String?
    var serviceProvider: String?
    var taggedKeywords: [String]
    var amount: String?
    var merchant: String?
    var thinking: String?
    var refused: Bool
    var latencyMs: Int
    var toolCallCount: Int = 0
    var outputCharacterCount: Int = 0
    var inputCharacterCount: Int = 0
    var kind: String? = nil          // "spend" | "nonSpend" | nil (not a transaction)
    var nonSpendType: String? = nil
    /// True when a ReviewFlag was raised over the category — unrecognized, or
    /// disagreed with the model's own isFinancialTransaction/isTransferOrRefund.
    /// This is what would have told us about the refund without reading `thinking`.
    var hadCategoryFlag: Bool = false
}

// MARK: - Report

nonisolated struct EvaluationReport: Sendable, Codable {
    var judge: String
    var runAt: Date
    var total: Int
    var labelled: Int

    /// Coverage: produced a verdict at all. A refused row is not a wrong row,
    /// but it is still a row that didn't get logged.
    var judged: Int
    var refused: Int

    /// Of the labelled ones.
    var correct: Int
    var wrong: Int
    /// Wrong but flagged — recoverable at the human gate, so not a silent error.
    var wrongButFlagged: Int
    /// Wrong, unflagged, high confidence. The number that decides whether Auto is
    /// ever safe. The last run put this at 8.
    var confidentlyWrong: Int

    var amountExactMatches: Int
    var medianLatencyMs: Int
    var p95LatencyMs: Int

    /// Quick on-device signal before you ever open Python: does latency actually
    /// move with tool calls, or is something else (thermal, simulator load)
    /// driving the variance instead?
    var averageToolCalls: Double = 0
    var averageOutputCharacters: Double = 0

    /// How often the model's category disagreed with its own booleans, or named
    /// a category TagStore doesn't recognize. Each one is a row that would have
    /// silently gotten the wrong kind (or vanished) before this was flagged.
    var categoryFlagCount: Int = 0

    /// Per-sender breakdown — where the wins and the gaps actually are.
    var bySender: [String: SenderStats]

    /// Detailed inspection results for each judged email.
    var items: [ItemResult] = []

    nonisolated struct SenderStats: Sendable, Codable {
        var total = 0
        var judged = 0
        var correct = 0
        var refused = 0
    }

    var coverage: Double { total == 0 ? 0 : Double(judged) / Double(total) }
    var accuracy: Double { labelled == 0 ? 0 : Double(correct) / Double(labelled) }
    /// Right, or wrong but flagged. The bar that actually matters at Assist.
    var honestRate: Double {
        labelled == 0 ? 0 : Double(correct + wrongButFlagged) / Double(labelled)
    }

    /// Written next to the app's documents so you can pull it into Python.
    func write(to directory: URL = URL.documentsDirectory) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let stamp = Int(runAt.timeIntervalSince1970)
        let url = directory.appending(path: "eval-\(judge)-\(stamp).json")
        try encoder.encode(self).write(to: url)
        return url
    }
}

// MARK: - Runner

struct Evaluator {
    let corpus: EmailCorpus

    /// `limit` keeps a first pass to a couple of minutes. Raise it once the
    /// numbers stop moving.
    func run(
        _ judge: EmailJudge,
        limit: Int? = nil,
        filterCurrency: Bool = false,
        onProgress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> EvaluationReport {
        let baseList = filterCurrency ? corpus.emailsWithCurrency() : corpus.emails
        let emails = limit.map { Array(baseList.prefix($0)) } ?? baseList
        var report = EvaluationReport(
            judge: judge.name, runAt: .now, total: emails.count,
            labelled: 0, judged: 0, refused: 0, correct: 0, wrong: 0,
            wrongButFlagged: 0, confidentlyWrong: 0, amountExactMatches: 0,
            medianLatencyMs: 0, p95LatencyMs: 0, bySender: [:]
        )
        var latencies: [Int] = []
        var toolCallCounts: [Int] = []
        var outputCharCounts: [Int] = []

        for (index, email) in emails.enumerated() {
            let started = ContinuousClock.now
            let verdict = await judge.judge(email)
            let elapsed = Int(started.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
            latencies.append(elapsed)
            toolCallCounts.append(verdict.toolCallCount)
            outputCharCounts.append(verdict.outputCharacterCount)

            var stats = report.bySender[email.senderDomain] ?? .init()
            stats.total += 1

            if verdict.refused {
                report.refused += 1
                stats.refused += 1
            } else {
                report.judged += 1
                stats.judged += 1
            }

            if let label = corpus.labels[email.id] {
                report.labelled += 1
                let right = label.isPurchase == verdict.isPurchase
                    && (!label.isPurchase || amountsAgree(label, verdict))
                if right {
                    report.correct += 1
                    stats.correct += 1
                } else {
                    report.wrong += 1
                    if verdict.flags.isEmpty {
                        // Wrong, and said nothing about it. This is the number
                        // that decides whether Auto is ever safe.
                        if (verdict.confidence ?? 1) >= 0.85 { report.confidentlyWrong += 1 }
                    } else {
                        report.wrongButFlagged += 1
                    }
                }
                if amountsAgree(label, verdict) { report.amountExactMatches += 1 }
            }

            report.bySender[email.senderDomain] = stats

            let displayDate: String
            if let txnDate = verdict.dateString, !txnDate.isEmpty {
                displayDate = txnDate
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                displayDate = formatter.string(from: email.date)
            }

            let amountStr = verdict.amount.map { "\($0.currency.symbol) \($0.minorUnits)" }
            let hadCategoryFlag = verdict.flags.contains { $0.reason == .ambiguousKind }
            if hadCategoryFlag { report.categoryFlagCount += 1 }
            let item = ItemResult(
                id: email.id,
                date: displayDate,
                subject: email.subject,
                from: email.from,
                isPurchase: verdict.isPurchase,
                transactionType: verdict.transactionType,
                serviceProvider: verdict.serviceProvider,
                taggedKeywords: verdict.taggedKeywords,
                amount: amountStr,
                merchant: verdict.merchantRaw,
                thinking: verdict.thinking,
                refused: verdict.refused,
                latencyMs: elapsed,
                toolCallCount: verdict.toolCallCount,
                outputCharacterCount: verdict.outputCharacterCount,
                inputCharacterCount: verdict.inputCharacterCount,
                kind: verdict.kind?.rawValue,
                nonSpendType: verdict.nonSpendType?.rawValue,
                hadCategoryFlag: hadCategoryFlag
            )
            report.items.append(item)

            onProgress(index + 1, emails.count)
        }

        latencies.sort()
        if !latencies.isEmpty {
            report.medianLatencyMs = latencies[latencies.count / 2]
            report.p95LatencyMs = latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.95))]
        }
        if !toolCallCounts.isEmpty {
            report.averageToolCalls = Double(toolCallCounts.reduce(0, +)) / Double(toolCallCounts.count)
        }
        if !outputCharCounts.isEmpty {
            report.averageOutputCharacters = Double(outputCharCounts.reduce(0, +)) / Double(outputCharCounts.count)
        }
        return report
    }

    private func amountsAgree(_ label: EmailCorpus.Label, _ verdict: Verdict) -> Bool {
        guard let expected = label.amount else { return verdict.amount == nil }
        return verdict.amount?.minorUnits == expected
    }
}

// MARK: - Adapters

/// Wraps a deterministic parser as a judge, so both lanes report identically.
struct ParserJudge: EmailJudge {
    let parser: ReceiptParser
    var name: String { parser.id.rawValue }

    func judge(_ email: CapturedEmail) async -> Verdict {
        switch parser.parse(email) {
        case .parsed(let receipt):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let dateFormatted = formatter.string(from: receipt.date)
            return Verdict(
                isPurchase: receipt.kind == .spend,
                amount: receipt.amount,
                merchantRaw: receipt.merchantRaw,
                kind: receipt.kind,
                confidence: nil,
                flags: receipt.flags,
                refused: false,
                thinking: "Deterministic extraction matched template '\(parser.id.rawValue)'. Service provider: blu by BCA Digital. Merchant: \(receipt.merchantRaw). Amount: \(receipt.amount.currency.symbol) \(receipt.amount.minorUnits). Date: \(dateFormatted).",
                transactionType: receipt.kind == .nonSpend ? (receipt.nonSpendType == .refund ? "Refund / Inflow" : "Bank Transfer / Top-Up") : "Food & Dining",
                taggedKeywords: ["bluAccount", "Amount", receipt.merchantRaw],
                dateString: dateFormatted,
                serviceProvider: "blu by BCA Digital"
            )
        case .notAPurchase:
            return Verdict(
                isPurchase: false,
                flags: [],
                thinking: "Subject did not contain transaction or refund indicators.",
                transactionType: "Marketing / Notification",
                taggedKeywords: []
            )
        case .incomplete(let missing):
            // Recognised but unreadable. Flagged, not guessed (Invariant 6).
            return Verdict(
                isPurchase: true, amount: nil, merchantRaw: nil, kind: nil,
                confidence: nil,
                flags: [ReviewFlag(reason: .unparseable, detail: "missing \(missing)")],
                thinking: "Matched sender template but missing required field: \(missing).",
                transactionType: "Incomplete Receipt",
                taggedKeywords: [missing]
            )
        case .notApplicable:
            return Verdict(isPurchase: false, flags: [], refused: true, thinking: "Sender does not match parser domain.")
        }
    }
}

/// Evaluates using Apple's on-device Foundation Models with guided generation.
struct FoundationModelJudge: EmailJudge {
    var name: String { "foundation-models" }

    func judge(_ email: CapturedEmail) async -> Verdict {
        await FoundationModelClassifier.classify(email)
    }
}

