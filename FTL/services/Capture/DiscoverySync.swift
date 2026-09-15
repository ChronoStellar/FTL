//
//  DiscoverySync.swift
//  FTL — services/Capture
//
//  The last piece of "the agent extends itself" — ROADMAP, Automation item C.
//  `PatternDiscovery.run(over:isRead:)` already does discovery→learn; what was
//  missing was something that fed it LIVE Gmail instead of the frozen corpus,
//  persisted whatever cleared a bar, and held a call budget. This is that.
//
//  ## Why this is a separate trigger from AutoSync
//
//  AutoSync's job is cheap and safe to repeat: read the capture log, fetch a
//  narrow 14-day window for senders already readable, write to the
//  provisional cache. Discovery is a different shape of cost — it fetches an
//  entire 180-day, unscoped-by-sender window (`PatternDiscovery.discoveryQuery`,
//  `discoveryFetchLimit`) and, for whatever clears the evidence and variance
//  bars, spends real model calls. Running that on every foreground return
//  would be a battery complaint waiting to happen, so it runs once — **per
//  launch**, not on a throttled clock like AutoSync's fifteen minutes. The
//  feasibility run already produced one unbounded tool loop that hit 30
//  calls; every loop in this app is bounded, and here the bound is
//  `maxSendersPerRun: 1` on top of `PatternSynthesisPolicy.maxAttempts` per
//  layout.
//
//  ## What it does NOT do
//
//  · It never writes to the ledger, and nothing here is downstream of
//    Invariant 1. A promoted or provisional pattern is a STORED RULE, not a
//    queue entry — the rows it eventually produces still go through the
//    ordinary `GmailRail.sync()` path on the next sync and land `.pending`
//    like everything else, flagged `unverifiedPattern` until the queue has
//    vouched for it (`PatternTrustPolicy`).
//  · It never widens the call budget past what `PatternDiscovery` and
//    `PatternSynthesisPolicy` already bound.
//  · It never runs without an on-device model. `FoundationModelSynthesizer`
//    requires one; there is nothing to propose with on a machine — or a
//    simulator — that doesn't have one, so this is a no-op there.
//

import Foundation
import Observation

@Observable @MainActor
final class DiscoverySync {
    /// Everything one run needs. A factory rather than stored properties so
    /// `sample()` and a signed-out session can hand back nil, same reasoning
    /// as `AutoSync.makeRail`.
    struct Context {
        let source: any CapturedEmailSource
        let discovery: PatternDiscovery
        let patterns: PatternStore
        /// The rail's OWN precedence — learned patterns, then presets, then
        /// any hand-written parser (`GmailRail.activeParsers`) — so "unread"
        /// here means unread by the shipping app, not a parallel definition
        /// discovery invented for itself.
        let activeParsers: () async -> [any ReceiptParser]
    }

    private let makeContext: () -> Context?

    /// True once a run has been attempted this launch. Not a timestamp and no
    /// throttle window — the bound is "once per process": `AppEnvironment`
    /// and this object both live exactly as long as the app does, so that is
    /// what "per launch" means here.
    private var hasRun = false
    private var isRunning = false

    /// What the last run found, for the Debug screen. Same reasoning as
    /// `AutoSync.lastResult` — nobody asked for this to run, so nothing on a
    /// release screen reports it.
    private(set) var lastResult: String?

    init(makeContext: @escaping () -> Context?) {
        self.makeContext = makeContext
    }

    /// One bounded sweep: fetch, select candidates, learn, persist what
    /// clears a bar. `force` re-arms it for the Debug screen; nothing in the
    /// release app ever passes it.
    @discardableResult
    func runIfDue(force: Bool = false) async -> Bool {
        guard !isRunning else { return false }
        guard force || !hasRun else { return false }
        guard let context = makeContext() else { return false }

        guard FoundationModelSynthesizer.isAvailable else {
            lastResult = "No on-device model here — nothing to propose with."
            return false
        }

        isRunning = true
        defer { isRunning = false }

        do {
            let parsers = await context.activeParsers()
            let isRead: (CapturedEmail) -> Bool = { email in
                guard let parser = parsers.first(where: { $0.canParse(email) }) else { return false }
                if case .parsed = parser.parse(email) { return true }
                return false
            }

            // Senders with at least one pattern already active — the volume
            // gate that decides whether a LAYOUT is worth a model call
            // relaxes for these (`minimumProvisionalEvidenceForKnownSender`):
            // the question that gate exists to answer, "is this sender
            // real", is already settled for them.
            let activePatterns = (try? await context.patterns.active()) ?? []
            let knownSenders = Set(activePatterns.map(\.senderDomain))

            let findings = try await context.discovery.run(
                fetching: context.source,
                isRead: isRead,
                knownSenders: knownSenders
            )

            var promoted = 0
            var provisional = 0
            for finding in findings {
                for result in finding.outcomes {
                    switch result.outcome {
                    case .promoted(let pattern, _):
                        try? await context.patterns.save(pattern)
                        promoted += 1
                    case .provisional(let pattern, _, _):
                        try? await context.patterns.save(pattern)
                        provisional += 1
                    default:
                        // Rejected, insufficient evidence, not transactional,
                        // gated — nothing to persist. The candidate stays
                        // unread and is free to be reconsidered next launch.
                        break
                    }
                }
            }

            // Counted as run only on success, same reasoning as AutoSync: a
            // failure before any model call spent nothing, so it costs
            // nothing to let the next launch try again instead of burning
            // this one's only attempt on an empty result.
            hasRun = true
            lastResult = findings.isEmpty
                ? "No unread sender cleared the bars."
                : "\(promoted) promoted · \(provisional) provisional, \(findings.count) sender(s) attempted"
            return promoted + provisional > 0
        } catch {
            // Swallowed on purpose — see AutoSync. Nobody asked for this run,
            // so nobody is waiting on an answer. `hasRun` stays false.
            lastResult = "Failed: \(error.localizedDescription)"
            return false
        }
    }
}
