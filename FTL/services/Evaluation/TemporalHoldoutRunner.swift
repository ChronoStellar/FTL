//
//  TemporalHoldoutRunner.swift
//  FTL — services/Evaluation
//
//  Train on the past, test on the future, check against the one thing in this
//  app that isn't the pipeline's own opinion: the Sheet.
//
//  Every other harness either starts from nothing (`EndToEndRunner`, scripted)
//  or replays a frozen export (`PipelineCaseRunner`, `EmailCorpus`). Neither
//  answers the question this one exists for: pointed at a REAL mailbox, with
//  NO knowledge of what comes after a cutoff date, does the loop generalise
//  forward in time the way it's supposed to generalise across senders?
//
//      July–August mail  →  discover → learn → promote   (isolated stores;
//                                                           nothing here
//                                                           touches the app's
//                                                           real patterns)
//      September mail    →  read with ONLY what was just learned
//      the real Sheet    →  did the learned patterns find what's actually
//                             there, and read it right?
//
//  ⚠️ Two honest limits, both structural:
//
//  · **"Compare to the Sheet" measures agreement, not independent truth.**
//    The Sheet's July–September rows are themselves the product of this app's
//    ORDINARY (preset-and-oracle-assisted) pipeline plus human approval — the
//    same epistemic status every other measurement in this codebase already
//    accepts (`ROADMAP.md`: "the approval queue is the only oracle"). This
//    run asks "does a purely self-taught pass over July–August reproduce what
//    the assisted pipeline plus a person already established as true", not
//    "is the pipeline correct against ground truth no rail here produced."
//  · **Tagging is checked by MERCHANT ONLY, not `TagKey` (merchant + layout).**
//    A promoted `LedgerTransaction` carries no `readBy` — that field exists
//    only on `ProvisionalEntry`, and is gone by the time a row reaches the
//    Sheet. There is no way to reconstruct which layout a July–August ledger
//    row was read by, so this can only ask the coarser, pre-`TagKey`
//    question: "would a plain merchant-name history have predicted
//    September's category." A real run of `DefaultPurchaseTagger` (memory +
//    model, keyed by `TagKey`) is not exercised here at all.
//
//  Uses REAL Gmail (read-only) and READS the real Sheet — never writes to
//  either. Patterns are learned into an isolated `MutablePatternStore` and
//  discarded when the run ends; nothing here touches `AppEnvironment.shared`'s
//  actual `patterns`, `tagMemory`, `captureLog` or `provisional` stores.
//

import Foundation

nonisolated struct TemporalHoldoutRunner: Sendable {

    nonisolated struct Config: Sendable {
        var trainingStart: Date
        /// Exclusive.
        var trainingEnd: Date
        var testStart: Date
        /// Exclusive. Defaults to now — September isn't over yet.
        var testEnd: Date

        /// Bounded like every other unattended fetch in this app
        /// (`PatternDiscovery.discoveryFetchLimit` is 400 for a live 180-day
        /// sweep); two months of one mailbox's mail is comparable in scale.
        var trainingFetchLimit = 800
        var testFetchLimit = 400
        /// Not capped at 1 the way `DiscoverySync` is for a live, unattended,
        /// every-launch run — this is a deliberate one-off measurement, and
        /// the cost that cap exists to bound (battery, a background task
        /// running long) doesn't apply here.
        var maxSendersPerRun = 8
        /// Matches `AppEnvironment.pureAgentMode`'s current default: no
        /// ground truth, because the question is whether the agent can learn
        /// this itself. Set true to score against `BluReceiptParser` instead,
        /// for whichever emails are blu's.
        var useBluOracle = false

        /// July 1 – September 1 train, September 1 – now test. The literal
        /// request this runner was built for, and a sensible default as more
        /// of September accumulates.
        static func julyAugustToSeptember(now: Date = .now, calendar: Calendar = .current) -> Config {
            let year = calendar.component(.year, from: now)
            let trainingStart = calendar.date(from: DateComponents(year: year, month: 7, day: 1))!
            let trainingEnd = calendar.date(from: DateComponents(year: year, month: 9, day: 1))!
            return Config(trainingStart: trainingStart, trainingEnd: trainingEnd, testStart: trainingEnd, testEnd: now)
        }
    }

    struct Report: Sendable {
        var lines: [String] = []
    }

    func run(auth: GoogleAuthManager, ledger: LedgerStore, config: Config) async throws -> Report {
        var lines: [String] = []
        guard FoundationModelSynthesizer.isAvailable else {
            return Report(lines: ["⚠︎ FoundationModels unavailable here — needs a real device."])
        }

        let exporter = GmailExporter(auth: auth)

        // ── Train ────────────────────────────────────────────────────────
        lines.append("═══ TRAIN — \(Self.fmt(config.trainingStart)) to \(Self.fmt(config.trainingEnd)) ═══")
        let trainingMail = try await exporter.fetchCaptured(
            query: Self.gmailRange(from: config.trainingStart, to: config.trainingEnd),
            limit: config.trainingFetchLimit
        )
        lines.append("fetched \(trainingMail.count) email(s)")

        let patterns = MutablePatternStore()
        let oracle: any PatternOracle = config.useBluOracle ? ParserOracle(BluReceiptParser()) : NoOracle()
        let learner = DefaultPatternLearner(synthesizer: FoundationModelSynthesizer(), oracle: oracle)
        let discovery = PatternDiscovery(learner: learner, maxSendersPerRun: config.maxSendersPerRun)

        // `isRead` is always false — a from-scratch run, deliberately not
        // building on whatever `AppEnvironment.shared` already knows. The
        // question is what the loop learns from THIS window alone.
        let started = Date.now
        let findings = await discovery.run(over: trainingMail, isRead: { _ in false })
        lines.append(String(format: "elapsed %.1fs", Date.now.timeIntervalSince(started)))

        var promoted = 0
        var provisional = 0
        for finding in findings {
            for result in finding.outcomes {
                let name = "\(finding.senderDomain)/\(result.template.isEmpty ? "-" : result.template)"
                switch result.outcome {
                case .promoted(let pattern, let feedback):
                    try? await patterns.save(pattern)
                    promoted += 1
                    lines.append("  ✓ \(name) — PROMOTED \(feedback.succeeded)/\(feedback.attempted)")
                case .provisional(let pattern, let coverage, let evidence):
                    try? await patterns.save(pattern)
                    provisional += 1
                    lines.append(String(format: "  ◐ %@ — provisional, coverage %.0f%% over %d", name, coverage * 100, evidence))
                case .rejected(_, _, let attempts, let lastError):
                    lines.append("  ✗ \(name) — rejected after \(attempts) attempt(s)" + (lastError.map { " (\($0))" } ?? ""))
                case .notTransactional(let distinct, let of):
                    lines.append("  ○ \(name) — not transactional (\(distinct) of \(of))")
                case .insufficientEvidence(let available):
                    lines.append("  ○ \(name) — insufficient evidence (\(available))")
                case .gated(let reason):
                    lines.append("  ⚠ \(name) — gated: \(reason)")
                }
            }
        }
        if findings.isEmpty {
            lines.append("  nothing cleared discovery's bars in this window")
        }
        lines.append("learned: \(promoted) promoted, \(provisional) provisional, \(findings.count) sender(s) attempted")
        lines.append("")

        // A merchant-only category history from what the REAL Sheet already
        // says about July–August — see the file header on why this is
        // merchant-only rather than `TagKey`. Same bars as
        // `MerchantTagHistory.settled()` (≥2 decisions, ≥60% one bucket),
        // applied by hand because there is no `ProvisionalEntry` here to
        // build a real `TagContext`/`TagKey` from.
        let trainingLedgerRows = try await ledger.transactions(in: DateInterval(start: config.trainingStart, end: config.trainingEnd))
        var merchantCategoryCounts: [MerchantID: [CategoryID: Int]] = [:]
        for row in trainingLedgerRows where row.kind == .spend {
            guard let category = row.categoryID else { continue }
            merchantCategoryCounts[MerchantID(normalizing: row.merchantRaw), default: [:]][category, default: 0] += 1
        }
        func settledCategory(for merchant: MerchantID) -> CategoryID? {
            guard let counts = merchantCategoryCounts[merchant] else { return nil }
            let total = counts.values.reduce(0, +)
            guard total >= 2, let leader = counts.max(by: { $0.value < $1.value }) else { return nil }
            return Double(leader.value) / Double(total) >= 0.6 ? leader.key : nil
        }
        lines.append("\(merchantCategoryCounts.count) merchant(s) with a category history from the Sheet's own July–August rows")
        lines.append("")

        // ── Test ─────────────────────────────────────────────────────────
        lines.append("═══ TEST — \(Self.fmt(config.testStart)) to \(Self.fmt(config.testEnd)) ═══")
        let testMail = try await exporter.fetchCaptured(
            query: Self.gmailRange(from: config.testStart, to: config.testEnd),
            limit: config.testFetchLimit
        )
        lines.append("fetched \(testMail.count) email(s)")

        // Same precedence rule `GmailRail.activeParsers` uses — most specific
        // layout first, so a subject-only pattern doesn't claim an email a
        // more specific one also matches.
        let learnedPatterns = (try? await patterns.active()) ?? []
        let readers: [any ReceiptParser] = learnedPatterns
            .sorted { $0.bodyContains.count > $1.bodyContains.count }
            .map(PatternDrivenParser.init(pattern:))

        struct Produced {
            let amount: Money
            let date: Date
            let merchantRaw: String
            let kind: TransactionKind
        }
        var produced: [Produced] = []
        for email in testMail {
            guard let parser = readers.first(where: { $0.canParse(email) }),
                  case .parsed(let receipt) = parser.parse(email)
            else { continue }
            produced.append(Produced(amount: receipt.amount, date: receipt.date, merchantRaw: receipt.merchantRaw, kind: receipt.kind))
        }
        lines.append("read \(produced.count) of \(testMail.count) test email(s) using \(readers.count) learned pattern(s)")

        // Printed regardless of whether the Sheet has anything to compare
        // against — see below. A Sheet with nothing recorded yet for the
        // test window (a fresh month nobody has approved into) shouldn't
        // mean this run has nothing to show; eyeballing what was actually
        // read is still a real check.
        if !produced.isEmpty {
            lines.append("")
            lines.append("  what the learned patterns read from September:")
            for row in produced.sorted(by: { $0.date < $1.date }) {
                let kindTag = row.kind == .spend ? "" : " · \(row.kind.rawValue)"
                lines.append("    \(Self.fmt(row.date)) · \(MoneyFormatter.rp(row.amount)) · \(row.merchantRaw)\(kindTag)")
            }
        }
        lines.append("")

        // ── Compare against the Sheet ────────────────────────────────────
        let realRows = try await ledger.transactions(in: DateInterval(start: config.testStart, end: config.testEnd))
            .filter { $0.kind == .spend }
        // Spend-only for the join too — a produced refund or incoming
        // transfer must never stand in for a real spend row just because it
        // happens to share an amount and a date.
        let producedSpend = produced.filter { $0.kind == .spend }
        lines.append("═══ COMPARE against the Sheet — \(realRows.count) real spend row(s) in that window ═══")

        var matched = 0
        var amountExact = 0
        var tagCandidates = 0
        var tagMatched = 0
        var missed: [LedgerTransaction] = []

        for real in realRows {
            // The same blocking key `GmailRail`'s own duplicate detection
            // uses — this is a JOIN against the Sheet, not a duplicate
            // check, but it's the same underlying question: "is this the
            // same purchase, described by a different source."
            let fp = Fingerprint(amount: real.amount, date: real.date)
            let candidateBuckets = Set([fp] + fp.adjacent)
            guard let twin = producedSpend.first(where: { candidateBuckets.contains(Fingerprint(amount: $0.amount, date: $0.date)) }) else {
                missed.append(real)
                continue
            }
            matched += 1
            if twin.amount == real.amount { amountExact += 1 }

            if let realCategory = real.categoryID {
                tagCandidates += 1
                if settledCategory(for: MerchantID(normalizing: real.merchantRaw)) == realCategory {
                    tagMatched += 1
                }
            }
        }

        lines.append(realRows.isEmpty
            ? "  no real spend rows in the test window yet — nothing to compare against"
            : String(format: "  found %d/%d (%.0f%%) of the Sheet's real transactions", matched, realRows.count, matched == 0 ? 0 : Double(matched) / Double(realRows.count) * 100))
        if matched > 0 {
            lines.append("  exact amount on a found row: \(amountExact)/\(matched)")
        }
        if tagCandidates > 0 {
            lines.append(String(format: "  merchant-history category would have matched: %d/%d (%.0f%%)", tagMatched, tagCandidates, Double(tagMatched) / Double(tagCandidates) * 100))
        } else if matched > 0 {
            lines.append("  no found row had a category on the Sheet to compare against")
        }

        if !missed.isEmpty {
            lines.append("")
            lines.append("  missed (\(missed.count)):")
            for row in missed.sorted(by: { $0.date < $1.date }).prefix(20) {
                lines.append("    \(Self.fmt(row.date)) · \(MoneyFormatter.rp(row.amount)) · \(row.merchantRaw)")
            }
            if missed.count > 20 { lines.append("    … \(missed.count - 20) more") }
        }

        return Report(lines: lines)
    }

    private static func gmailRange(from start: Date, to end: Date) -> String {
        "after:\(gmailDate(start)) before:\(gmailDate(end))"
    }

    private static func gmailDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private static func fmt(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}
