//
//  PipelineCase.swift
//  FTL — services/Evaluation
//
//  Synthetic emails with the answers attached.
//
//  Everything measured so far came from one recorded mailbox with exactly two
//  learnable senders, and it could only ever answer "what does the pipeline do
//  with MY mail". The cases it does not contain are the ones that matter: a
//  refund that should not reduce a bucket, a promo that must never be queued, a
//  receipt whose amount is missing, a card charge that arrives a day after its
//  receipt.
//
//  Three properties the real corpus cannot have:
//
//  · **Committable.** No merchant you visited, no account number, no names.
//    `FTL/test/` is gitignored and 82 MB; this lives in the repo and is read by
//    anyone who checks it out.
//  · **Expectations, not just data.** A corpus you eyeball is a corpus you stop
//    eyeballing. Each case states the verdict, amount, merchant, kind and flags
//    it must produce, so a regression is a failing name rather than a number
//    that looks slightly different from last week.
//  · **Pinned patterns.** The learned Grab patterns live in the file rather
//    than on a device, so the executor is testable without the model — and the
//    two that are currently WRONG are pinned as they actually behave, marked
//    `knownIssue`. Fixing them turns those cases green; nothing else has to
//    change.
//
//  Sender domains are real because parser dispatch keys on them. Everything
//  inside the emails is invented.
//

import Foundation

nonisolated struct PipelineCase: Sendable, Codable {
    /// Kebab-case, stable. This is what a failure is reported as.
    let name: String
    /// Why the case exists — what would break if it were deleted.
    let note: String
    let email: CapturedEmail
    let expect: Expectation
    /// Set when the case documents behaviour that is wrong but not yet fixed.
    /// Reported apart from failures: a known defect is not a regression, and
    /// burying it among passes is how it stays known and never fixed.
    let knownIssue: String?

    nonisolated struct Expectation: Sendable, Codable {
        /// `queued`, `flagged`, `notAPurchase` or `skipped` — the rail's own
        /// verdict, from the capture log.
        let verdict: String
        /// Minor units. Nil when the case expects no row.
        let amount: Int?
        let merchantRaw: String?
        let kind: String?
        let nonSpendType: String?
        /// Exact set, order-insensitive. `[]` asserts NO flags, which is a real
        /// assertion — a flag that fires on everything is worthless, so cases
        /// that must stay quiet say so.
        let flags: [String]?
    }
}

/// What the discovery pass must and must not pick, over out-of-vocabulary mail.
///
/// Selection only. Synthesis needs the model and is nondeterministic, but
/// WHICH senders the loop spends a call on is pure, and it is the half that
/// decides whether an agent is safe to leave running unattended.
nonisolated struct DiscoveryExpectation: Sendable, Codable {
    let note: String
    let expectedCandidates: [String]

    /// Domain → how many of its layouts must qualify.
    ///
    /// Selecting the sender is not enough. A sender that uses two subjects had
    /// half its mail silently discarded by the old subject-first triage, and
    /// the symptom was invisible: discovery still picked the sender, still
    /// learned a pattern, and simply never saw the other layout. Counting is
    /// what makes that visible.
    let expectedLayouts: [String: Int]
    /// Domain → why it must be refused. The reasons differ, and a single pass/
    /// fail would hide that: a brochure, a sender with too few emails, and a
    /// sender in another currency are rejected by three different tests.
    let expectedNonCandidates: [String: String]
}

nonisolated struct PipelineFixture: Sendable, Codable {
    /// Learned patterns, pinned. Lets the fixture exercise
    /// `PatternDrivenParser` with no model, no device and no network.
    let patterns: [ExtractionPattern]
    let cases: [PipelineCase]

    /// Mail from senders nothing can read — the only kind discovery is for.
    /// Kept out of `cases` because per-email assertions are the wrong shape
    /// here: what matters is which SENDER is chosen, not what each email does.
    let discoveryCorpus: [CapturedEmail]
    let discovery: DiscoveryExpectation

    static func load(
        resource: String = "pipeline-cases",
        bundle: Bundle = .main
    ) throws -> PipelineFixture {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let decoder = JSONDecoder()
        // ISO strings, so a hand-written fixture is readable and diffable —
        // `.deferredToDate` would put seconds-since-2001 floats in the file.
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PipelineFixture.self, from: Data(contentsOf: url))
    }
}
