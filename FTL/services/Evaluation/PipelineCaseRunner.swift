//
//  PipelineCaseRunner.swift
//  FTL — services/Evaluation
//
//  Runs the fixture cases through the REAL rail and diffs each result against
//  what the case says should happen.
//
//  Real parsers, real precedence, real dedup, real provisional writes. Only the
//  mailbox and the two stores are swapped — the stores because a test run must
//  not touch the approval queue, and `empty: true` on both because their
//  seeded defaults once reported four preview placeholders as pipeline output.
//
//  Patterns come from the fixture rather than the device, so this is
//  deterministic: no model, no network, no dependence on what someone happened
//  to learn last Tuesday.
//

import Foundation

nonisolated struct PipelineCaseRunner: Sendable {

    nonisolated struct Outcome: Sendable {
        let name: String
        let passed: Bool
        /// Empty when it passed. One line per field that disagreed.
        let differences: [String]
        let knownIssue: String?
    }

    nonisolated struct Report: Sendable {
        let outcomes: [Outcome]

        var failures: [Outcome] { outcomes.filter { !$0.passed && $0.knownIssue == nil } }
        /// Cases that pass while documenting behaviour known to be wrong. Kept
        /// apart from failures: a known defect is not a regression, and listing
        /// it among the passes is how it stays known and never fixed.
        var known: [Outcome] { outcomes.filter { $0.knownIssue != nil } }
        var passed: Int { outcomes.filter(\.passed).count }
    }

    func run(_ fixture: PipelineFixture) async throws -> Report {
        let provisional = InMemoryProvisionalStore(empty: true)
        let log = InMemoryCaptureLog()

        let rail = GmailRail(
            exporter: CorpusEmailSource(fixture.cases.map(\.email)),
            parsers: [BluReceiptParser()],
            provisional: provisional,
            log: log,
            patterns: FixedPatternStore(fixture.patterns),
            fetchLimit: fixture.cases.count
        )
        _ = try await rail.sync()

        let verdicts = Dictionary(
            await log.recorded().map { ($0.messageID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let rows = Dictionary(
            try await provisional.pending().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var outcomes = fixture.cases.map { testCase -> Outcome in
            let differences = Self.diff(
                testCase,
                record: verdicts[testCase.email.id],
                rows: rows
            )
            return Outcome(
                name: testCase.name,
                passed: differences.isEmpty,
                differences: differences,
                knownIssue: testCase.knownIssue
            )
        }
        outcomes.append(contentsOf: try await discoveryOutcomes(fixture))
        return Report(outcomes: outcomes)
    }

    /// Discovery, over mail from senders nothing can read.
    ///
    /// Fetched through `PatternDiscovery.candidateMail` rather than handed the
    /// array directly, so the FETCH is what is under test. Passing the corpus
    /// in is exactly the shortcut that hid the bug: `EmailCorpus` returns every
    /// sender, while the rail's query returns only senders it can already
    /// parse, and discovery fed from the latter can never grow.
    private func discoveryOutcomes(_ fixture: PipelineFixture) async throws -> [Outcome] {
        // Nothing here is readable: no parser claims these senders, which is
        // the definition of a discovery candidate.
        let readable: [any ReceiptParser] = [BluReceiptParser()]
            + fixture.patterns.map(PatternDrivenParser.init(pattern:))
        let isRead: (CapturedEmail) -> Bool = { email in
            guard let parser = readable.first(where: { $0.canParse(email) }) else { return false }
            if case .parsed = parser.parse(email) { return true }
            return false
        }

        let discovery = PatternDiscovery(learner: UncallableLearner())
        let mail = try await discovery.candidateMail(
            from: CorpusEmailSource(fixture.discoveryCorpus + fixture.cases.map(\.email))
        )
        let selected = discovery.candidates(in: mail, isRead: isRead)
        let chosen = selected.map(\.senderDomain)

        var outcomes: [Outcome] = []
        for (domain, expected) in fixture.discovery.expectedLayouts.sorted(by: { $0.key < $1.key }) {
            let actual = selected
                .first { $0.senderDomain.hasSuffix(domain) }?
                .transactionalLayouts.count ?? 0
            outcomes.append(
                Outcome(
                    name: "discovery-layouts-\(domain)",
                    passed: actual == expected,
                    differences: actual == expected
                        ? []
                        : ["\(actual) qualifying layout(s), expected \(expected)"],
                    knownIssue: nil
                )
            )
        }
        for domain in fixture.discovery.expectedCandidates {
            let found = chosen.contains { $0.hasSuffix(domain) }
            outcomes.append(
                Outcome(
                    name: "discovery-selects-\(domain)",
                    passed: found,
                    differences: found ? [] : ["not selected; chose \(chosen.isEmpty ? "nothing" : chosen.joined(separator: ", "))"],
                    knownIssue: nil
                )
            )
        }
        for (domain, reason) in fixture.discovery.expectedNonCandidates.sorted(by: { $0.key < $1.key }) {
            let found = chosen.contains { $0.hasSuffix(domain) }
            outcomes.append(
                Outcome(
                    name: "discovery-refuses-\(domain)",
                    passed: !found,
                    differences: found ? ["selected, but should be refused: \(reason)"] : [],
                    knownIssue: nil
                )
            )
        }
        return outcomes
    }

    /// Every disagreement, not the first. A case that got the amount AND the
    /// kind wrong is a different problem from one that only got the kind wrong,
    /// and stopping at the first difference hides which.
    private static func diff(
        _ testCase: PipelineCase,
        record: CaptureLogEntry?,
        rows: [ProvisionalEntry.ID: ProvisionalEntry]
    ) -> [String] {
        var differences: [String] = []
        let expected = testCase.expect

        // `notFetched` is a verdict the rail cannot record, because a message
        // it never asked Gmail for produces no log entry at all. It is still
        // worth asserting: the difference between "fetched and rejected" and
        // "never requested" is invisible in the queue and decides whether a
        // sender can ever be discovered.
        guard let record else {
            return expected.verdict == "notFetched"
                ? []
                : ["never fetched — the sender query did not ask for it, expected \(expected.verdict)"]
        }
        if expected.verdict == "notFetched" {
            differences.append("verdict: \(record.verdict.rawValue), expected never to be fetched")
        } else if record.verdict.rawValue != expected.verdict {
            differences.append("verdict: \(record.verdict.rawValue), expected \(expected.verdict)")
        }

        guard let entryID = record.entryID, let entry = rows[entryID] else {
            // No row is the right answer for `skipped` and `notAPurchase`; the
            // verdict check above has already caught the case where it isn't.
            if expected.amount != nil {
                differences.append("no queue row, but the case expects one")
            }
            return differences
        }

        if let amount = expected.amount, entry.transaction.amount.minorUnits != amount {
            differences.append("amount: \(entry.transaction.amount.minorUnits), expected \(amount)")
        }
        if let merchant = expected.merchantRaw, entry.transaction.merchantRaw != merchant {
            differences.append("merchant: \"\(entry.transaction.merchantRaw)\", expected \"\(merchant)\"")
        }
        if let kind = expected.kind, entry.resolution.kind.rawValue != kind {
            differences.append("kind: \(entry.resolution.kind.rawValue), expected \(kind)")
        }
        if let nonSpend = expected.nonSpendType {
            let actual = entry.resolution.nonSpendType?.rawValue ?? "none"
            if actual != nonSpend {
                differences.append("nonSpendType: \(actual), expected \(nonSpend)")
            }
        }
        if let flags = expected.flags {
            // A set, so ordering never causes a spurious failure — but an exact
            // set, so an EXTRA flag fails too. Flag inflation is the way a flag
            // stops meaning anything.
            let actual = Set(entry.flags.map(\.reason.rawValue))
            if actual != Set(flags) {
                let shown = actual.sorted().joined(separator: ",")
                differences.append("flags: [\(shown)], expected [\(flags.sorted().joined(separator: ","))]")
            }
        }
        return differences
    }
}

/// Fails loudly if selection ever reaches synthesis.
///
/// The fixture asserts WHICH senders get a model call, so a learner that could
/// actually run would make the test nondeterministic and slow, and would hide
/// the thing being measured behind whatever the model happened to say.
nonisolated struct UncallableLearner: PatternLearner {
    func learn(
        senderDomain: String,
        from corpus: [CapturedEmail],
        policy: PatternSynthesisPolicy
    ) async -> [TemplateOutcome] {
        assertionFailure("Fixture discovery must not invoke the model — it asserts selection only.")
        return []
    }
}

/// A `PatternStore` backed by the fixture. Read-only on purpose: a fixture run
/// that could write patterns would change the thing it is measuring.
nonisolated struct FixedPatternStore: PatternStore {
    private let patterns: [ExtractionPattern]

    init(_ patterns: [ExtractionPattern]) { self.patterns = patterns }

    func save(_ pattern: ExtractionPattern) async throws {}
    func active() async throws -> [ExtractionPattern] { patterns }
    func all() async throws -> [ExtractionPattern] { patterns }
    func revoke(id: String) async throws {}
}
