//
//  EndToEndRunner.swift
//  FTL — services/Evaluation
//
//  The whole pipeline, from a mailbox nobody has written anything for.
//
//  Every other harness in this app starts somewhere: the fixture cases ship a
//  preset and pinned patterns, the corpus run has blu. This one starts at
//  nothing — no preset, no hand-written parser, no learned pattern, no tag
//  memory, no capture log — and runs the arc the thesis actually claims:
//
//      100 emails in, NOTHING readable
//        ↓  discovery (deterministic — no model)
//      three senders worth a call, three refused for three different reasons
//        ↓  propose → verify → retry  (scripted — see ScriptedSynthesizer)
//      patterns, some promoted, some refused by the plausibility rules
//        ↓  sync again
//      rows arrive, FLAGGED, because nothing has verified them
//        ↓  tag
//      a suggested bucket per row
//        ↓  settle rows at the queue
//      the pattern earns its way out of being flagged
//
//  ⚠️ Two honest limits, both structural:
//
//  · The synthesizer is SCRIPTED. This measures the machinery — verifier, retry,
//    plausibility, promotion, trust — and says nothing about what a real model
//    would propose.
//  · The tagger's model half runs for real when the device has one, so the
//    suggested-bucket column is NOT deterministic. It is reported, never
//    asserted. Everything asserted here is deterministic.
//

import Foundation

nonisolated struct EndToEndRunner: Sendable {

    nonisolated struct Report: Sendable {
        var lines: [String] = []
        var failures: [Failure] = []
        /// Filled in only when something failed and a model was available.
        var reading: String?

        var isClean: Bool { failures.isEmpty }
    }

    /// One broken assertion, with the evidence the PIPELINE ITSELF produced.
    ///
    /// The evidence is the point. A failure that says only "expected 3, got 2"
    /// sends a person hunting; the concrete misses, coverage complaints and log
    /// verdicts that the run already computed say where to look. Anything that
    /// explains a failure — a person or the model — reads this, and nothing
    /// downstream is allowed to speculate past it.
    nonisolated struct Failure: Sendable {
        let stage: String
        let assertion: String
        let got: String
        let expected: String
        /// Deterministic, from the run. Never a guess.
        let evidence: [String]
    }

    /// Assertions are deterministic; observations are reported and never
    /// decide pass/fail.
    private struct Log {
        var report = Report()
        var stage = ""
        mutating func say(_ line: String = "") { report.lines.append(line) }
        mutating func check(
            _ label: String,
            _ got: Any,
            _ want: Any,
            evidence: [String] = []
        ) {
            let ok = "\(got)" == "\(want)"
            report.lines.append("  \(ok ? "✓" : "✗") \(label): \(got)" + (ok ? "" : "  — expected \(want)"))
            guard !ok else { return }
            report.failures.append(
                Failure(stage: stage, assertion: label,
                        got: "\(got)", expected: "\(want)", evidence: evidence)
            )
            for line in evidence { report.lines.append("      · \(line)") }
        }
    }

    /// Buckets are passed in rather than read from a ledger: the tagger needs a
    /// vocabulary and nothing else here needs a ledger at all, so this takes the
    /// narrowest dependency that does the job — the same split `CategorySource`
    /// draws for `DefaultPurchaseTagger`.
    func run(
        bundle: Bundle = .main,
        buckets: [SpendCategory] = SampleLedger.categories
    ) async throws -> Report {
        var log = Log()
        let corpus = try EndToEndCorpus.load(bundle: bundle)

        log.say("100 invented emails · 6 senders · nothing written for any of them")
        log.say()

        // ── 1. Empty state ──────────────────────────────────────────────────
        log.stage = "① empty state"
        log.say("① EMPTY STATE — what the rail does with no parser at all")
        let provisional = InMemoryProvisionalStore(empty: true)
        let captureLog = InMemoryCaptureLog()
        let patterns = MutablePatternStore()
        let tagMemory = InMemoryTagMemory()
        let patternMemory = InMemoryPatternMemory()
        let ledger = FixedCategories(buckets)

        func rail(
            into store: ProvisionalStore = provisional,
            tagger: (any PurchaseTagger)? = nil
        ) -> GmailRail {
            GmailRail(
                exporter: CorpusEmailSource(corpus),
                parsers: [], provisional: store, log: captureLog,
                patterns: patterns, presets: [], tagger: tagger, trust: patternMemory,
                fetchLimit: corpus.count
            )
        }

        let first = try await rail().sync()
        log.check("emails fetched", first.fetched, corpus.count,
                  evidence: ["the sender query is built from active parsers; with none it is empty",
                             "fetched \(first.fetched), skipped \(first.skipped), already seen \(first.alreadySeen)"])
        log.check("rows queued", first.queued, 0,
                  evidence: ["nothing should be readable yet — no preset, no learned pattern, no hand-written parser",
                             "GmailRail.activeParsers returned an empty list"])
        log.say("  · with no parser the sender query is empty, so it asks for EVERYTHING")
        log.say("  · and reads none of it — \(first.skipped) skipped")
        log.say()

        // ── 2. Discovery ────────────────────────────────────────────────────
        log.stage = "② discovery"
        log.say("② DISCOVERY — deterministic, no model, no labels")
        let learner = DefaultPatternLearner(
            synthesizer: ScriptedSynthesizer(),
            oracle: NoOracle()
        )
        let discovery = PatternDiscovery(learner: learner)
        let selected = discovery.candidates(in: corpus, isRead: { _ in false })
        log.check("senders worth a model call", selected.count, 3,
                  evidence: Self.triageEvidence(corpus))
        for candidate in selected.sorted(by: { $0.senderDomain < $1.senderDomain }) {
            for layout in candidate.transactionalLayouts {
                log.say("  ✓ \(candidate.senderDomain)/\(layout.key.isEmpty ? "-" : layout.key)"
                        + " — \(layout.emails.count) emails, \(layout.distinctAmounts) distinct figure-sets")
            }
        }
        let refused = ["promo.tokobagus.example.com": "brochure — 1 distinct figure-set in 15",
                       "warungkopi.example.com": "genuine receipts, only 6 — below the evidence floor",
                       "kabar.example.com": "no currency anywhere — dropped by the first filter"]
        for (domain, why) in refused.sorted(by: { $0.key < $1.key }) {
            log.say("  ✗ \(domain) — \(why)")
        }
        log.say()

        // ── 3. Learn ────────────────────────────────────────────────────────
        log.stage = "③ learn"
        log.say("③ LEARN — propose → verify → retry (scripted proposals)")
        var promoted = 0, refusedPatterns = 0
        var learnEvidence: [String] = []
        for candidate in selected.sorted(by: { $0.senderDomain < $1.senderDomain }) {
            let outcomes = await learner.learn(
                senderDomain: candidate.senderDomain, from: corpus, policy: .default
            )
            for outcome in outcomes {
                let name = "\(candidate.senderDomain)/\(outcome.template.isEmpty ? "-" : outcome.template)"
                switch outcome.outcome {
                case .provisional(let pattern, let coverage, let evidence):
                    try await patterns.save(pattern)
                    promoted += 1
                    log.say(String(format: "  ✓ %@ — provisional, coverage %.0f%% over %d held-out", name, coverage * 100, evidence))
                case .promoted(let pattern, let feedback):
                    try await patterns.save(pattern)
                    promoted += 1
                    log.say("  ✓ \(name) — PROMOTED, \(feedback.succeeded)/\(feedback.attempted)")
                case .rejected(_, let feedback, let attempts, let lastError):
                    refusedPatterns += 1
                    log.say("  ✗ \(name) — rejected after \(attempts) attempts")
                    if let lastError { learnEvidence.append("\(name): last model error — \(lastError)") }
                    for miss in (feedback?.failures ?? []).prefix(3) {
                        learnEvidence.append(
                            "\(name): field '\(miss.field)' came back as "
                            + (miss.extracted.map { "\"\($0)\"" } ?? "nothing")
                            + ", expected \(miss.expected ?? "—")")
                    }
                case .notTransactional(let distinct, let of):
                    log.say("  ○ \(name) — not transactional (\(distinct) of \(of))")
                case .insufficientEvidence(let available):
                    log.say("  ○ \(name) — insufficient evidence (\(available))")
                case .gated(let reason):
                    log.say("  ⚠︎ \(name) — gated: \(reason)")
                }
            }
        }
        log.check("patterns stored", promoted, 3, evidence: learnEvidence)
        log.check("patterns refused", refusedPatterns, 1, evidence: learnEvidence)
        log.say("  · dompetku is the refusal: its counterparty is the same string in")
        log.say("    every email, so the anchor reads a label. No attempt can fix that.")
        log.say()

        // ── 4. Sync again ───────────────────────────────────────────────────
        log.stage = "④ sync again"
        log.say("④ SYNC AGAIN — now something can read the mail")
        let tagger = DefaultPurchaseTagger(
            memory: tagMemory,
            proposer: FoundationModelTagger.isAvailable ? FoundationModelTagger() : nil,
            ledger: ledger
        )
        await captureLog.forget()
        let second = try await rail(tagger: tagger).sync()
        log.say("  \(second.summary)")
        let queued = try await provisional.pending()
        let stored = try await patterns.active()
        log.check("rows in the queue", queued.count > 0, true,
                  evidence: ["\(stored.count) active pattern(s): " + stored.map(\.id).joined(separator: ", "),
                             "rail result — \(second.summary)"])
        let flagged = queued.filter { $0.flags.contains { $0.reason == .unverifiedPattern } }
        log.check("every row flagged unverified", flagged.count, queued.count,
                  evidence: stored.map { "\($0.id): verifiedAgainst \($0.verifiedAgainst), accuracy \($0.accuracy)" }
                    + ["a pattern is flagged while verifiedAgainst == 0 AND the queue has not vouched for it"])
        log.say("  · nothing verified them: no hand-written parser exists for these")
        log.say("    senders, so `verify` never ran and coverage is not correctness")

        // The designed lesson of nusabank's minority layouts.
        let directionRows = queued.filter { $0.resolution.kind == .nonSpend }
        log.check("refunds and incoming that made it through", directionRows.count, 0,
                  evidence: stored.map { "\($0.id) claims subjects: \($0.subjectContains.joined(separator: " | "))" }
                    + ["nusabank's refunds say 'Refund Processed' and its inflows say 'Funds Received'"])
        log.say("  · nusabank sends 2 refunds and 2 incoming transfers. Triage keeps a")
        log.say("    sender's DOMINANT subject cluster, so the model only ever saw")
        log.say("    purchases — and proposed a pattern that does not claim the others.")
        log.say("    A sender's rare layouts are invisible to the loop. Not a bug in")
        log.say("    this run; a real limit, and this is where it shows.")
        log.say()

        // ── 5. What it thinks the tag should be ─────────────────────────────
        log.say("⑤ THE TAG IT THINKS IT SHOULD BE" +
                (FoundationModelTagger.isAvailable ? "  (model available)" : "  (no model here — memory only)"))
        log.say("  observed, never asserted — the model half is not deterministic")
        log.say()
        log.say("  merchant                        amount        suggested        basis")
        for entry in queued.sorted(by: { $0.transaction.merchantRaw < $1.transaction.merchantRaw }).prefix(14) {
            let merchant = String(entry.transaction.merchantRaw.prefix(30))
                .padding(toLength: 31, withPad: " ", startingAt: 0)
            let amount = MoneyFormatter.rp(entry.transaction.amount)
                .padding(toLength: 13, withPad: " ", startingAt: 0)
            let suggestion = entry.resolution.suggestedTag
            let bucket = suggestion.flatMap { s in buckets.first { $0.id == s.categoryID }?.name }
            log.say("  \(merchant)\(amount)"
                    + (bucket ?? "—").padding(toLength: 17, withPad: " ", startingAt: 0)
                    + Self.describe(suggestion?.basis))
        }
        if queued.count > 14 { log.say("  … \(queued.count - 14) more") }
        log.say()

        // ── 6. The queue earns the pattern its way out of being flagged ─────
        log.stage = "⑥ settling"
        log.say("⑥ SETTLING ROWS — the queue is the only oracle here")
        let approvals = DefaultApprovalService(
            store: provisional, ledger: InMemoryLedgerStore(empty: true),
            tags: tagMemory, patterns: patternMemory
        )
        let target = queued.filter { $0.readBy.map(ExtractionPattern.namesPattern) == true }
        let nusabankRows = target.filter { $0.readBy?.rawValue.hasPrefix("nusabank") == true }
        let policy = PatternTrustPolicy.default

        _ = try await approvals.approve(Array(nusabankRows.prefix(policy.minimumSettled - 1)).map(\.id))
        let beforeBar = try await patternMemory.records(for: [nusabankRows[0].readBy!.rawValue])
        log.check("vouched at \(policy.minimumSettled - 1) approvals",
                  policy.isVouchedFor(beforeBar.values.first), false,
                  evidence: beforeBar.values.map { "\($0.patternID): \($0.accepted) kept / \($0.settled) settled" }
                    + ["the bar is \(policy.acceptanceThreshold) over \(policy.minimumSettled) settled rows"])

        _ = try await approvals.approve(Array(nusabankRows.dropFirst(policy.minimumSettled - 1).prefix(1)).map(\.id))
        let atBar = try await patternMemory.records(for: [nusabankRows[0].readBy!.rawValue])
        log.check("vouched at \(policy.minimumSettled)",
                  policy.isVouchedFor(atBar.values.first), true,
                  evidence: atBar.values.map { "\($0.patternID): \($0.accepted) kept, \($0.correctedKind) kind-corrected, \($0.correctedAmount) amount-corrected, \($0.correctedMerchant) name-corrected, \($0.dropped) dropped" })
        log.say("  · \(atBar.values.first?.accepted ?? 0) kept of \(atBar.values.first?.settled ?? 0) settled")

        // And the flag stops, which is the whole visible payoff.
        // A FRESH store for the re-fetch rather than emptying the old one:
        // provisional rows are never deleted (Invariant 5), and widening the
        // contract with a delete just to make a harness tidy is the wrong trade.
        let reQueued = InMemoryProvisionalStore(empty: true)
        await captureLog.forget()
        let third = try await rail(into: reQueued, tagger: tagger).sync()
        let afterRows = try await reQueued.pending()
        let stillFlagged = afterRows.filter { row in
            row.readBy?.rawValue.hasPrefix("nusabank") == true
                && row.flags.contains { $0.reason == .unverifiedPattern }
        }
        log.check("nusabank rows still flagged after vouching", stillFlagged.count, 0,
                  evidence: stillFlagged.prefix(3).map { "still flagged: \($0.transaction.merchantRaw) via \($0.readBy?.rawValue ?? "?")" }
                    + ["GmailRail.vouchedPatterns reads PatternMemory once per sync"])
        log.say("  · \(third.queued) rows re-fetched; the nusabank pattern's rows now arrive")
        log.say("    unflagged because YOU stood behind \(policy.minimumSettled) of them. Drops take it back.")
        log.say()
        log.say("⚠︎ acceptance, not accuracy — the queue cannot correct a figure yet")

        return log.report
    }

    /// Per-sender triage numbers, so a discovery failure says which gate moved
    /// rather than only that the count was wrong.
    private static func triageEvidence(_ corpus: [CapturedEmail]) -> [String] {
        var bySender: [String: [CapturedEmail]] = [:]
        for email in corpus where email.hasCurrencyMarker {
            bySender[email.senderDomain, default: []].append(email)
        }
        let policy = PatternSynthesisPolicy.default
        return bySender.sorted { $0.value.count > $1.value.count }.map { domain, mail in
            let layouts = SenderTriage.templates(from: mail).map {
                "\($0.emails.count)e/\($0.distinctAmounts)d"
            }.joined(separator: " ")
            return "\(domain): \(mail.count) money mail · \(layouts.isEmpty ? "no layout" : layouts)"
        } + ["gates — distinct ≥ \(policy.minimumDistinctAmounts), volume ≥ \(policy.maxExamples + policy.minimumProvisionalEvidence) per layout"]
    }

    private static func describe(_ basis: TagSuggestion.Basis?) -> String {
        switch basis {
        case .memory(let agreed, let of): return "you chose it \(agreed)/\(of)"
        case .model: return "model — merchant not seen before"
        case nil: return "nothing to go on"
        }
    }
}

/// Truth for nobody. On a mailbox with no hand-written parser this is the only
/// oracle available, and it is empty by construction — which is exactly why
/// every pattern below lands `.provisional` rather than promoted.
/// The bucket list, and nothing else. See `run(bundle:buckets:)`.
nonisolated struct FixedCategories: CategorySource {
    private let buckets: [SpendCategory]
    init(_ buckets: [SpendCategory]) { self.buckets = buckets }
    func categories() async throws -> [SpendCategory] { buckets }
}

nonisolated enum EndToEndCorpus {
    static func load(bundle: Bundle = .main) throws -> [CapturedEmail] {
        guard let url = bundle.url(forResource: "empty-state-corpus", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).emails
    }
    private struct File: Decodable { let emails: [CapturedEmail] }
}
