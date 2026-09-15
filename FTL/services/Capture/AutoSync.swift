//
//  AutoSync.swift
//  FTL — services/Capture
//
//  The first thing in this app that runs without a tap.
//
//  Until now every part of the pipeline had exactly one trigger: a button in the
//  Debug screen. The loop was real, verified, and manual — `rail.sync()` had a
//  single caller and it was inside `#if DEBUG`, so in a release build nothing
//  ever fetched anything. This is what makes the app fill itself.
//
//  ## What is allowed to run unattended, and why
//
//  The invariants already draw the line; this only enforces it.
//
//      fetch + parse   → writes to ProvisionalStore     recoverable (Invariant 7)
//      dedup + pairing → flags on provisional rows      recoverable
//      tag             → a suggestion on a pending row  recoverable
//      approve         → writes to the LEDGER           NEVER (Invariant 1)
//
//  Everything up to the queue runs itself. The queue is where a person shows up,
//  and that is unchanged — this moves no row into the ledger and touches no
//  trust level. `TrustLevel` is still pinned to `.assist`.
//
//  ## Foreground — and no longer the only trigger
//
//  This is the sync that runs when the app becomes active, and it remains the
//  RELIABLE one: it happens every time, immediately, with no permission and
//  nothing for iOS to decide. The behaviour a person notices is "I opened the
//  app and my receipts were already there".
//
//  This header used to say `BGAppRefreshTask` was deliberately not taken yet,
//  on the grounds that the capture path had never run unattended even once.
//  It has now, so it was taken — see `BackgroundRefresh`, which runs the same
//  rail (minus the tagger, which cannot fit in a ~30s budget) when iOS grants a
//  window, and `CheckReceiptsIntent`, which is how a fetch gets scheduled at an
//  hour a person actually chose. Neither changes the boundary: both stop at the
//  provisional cache, exactly like this one.
//

import Foundation
import Observation

@Observable @MainActor
final class AutoSync {
    /// Nil when there is no mailbox to sync — `sample()`, or a signed-out
    /// session. A nil rail makes every call a no-op rather than an error.
    private let makeRail: () -> GmailRail?

    /// How long a sync stays fresh. Receipts arrive a few times a day and Gmail
    /// is rate-limited, so re-fetching on every foreground would spend quota to
    /// learn nothing. Fifteen minutes is short enough that switching back to the
    /// app after lunch checks again, long enough that flicking between apps
    /// does not.
    private let interval: TimeInterval

    private var lastCompleted: Date?
    private var isRunning = false

    /// What the last run did, for the Debug screen. Deliberately not surfaced
    /// on any release screen: a sync that found nothing is not news, and a
    /// failed one is not something a person can act on.
    private(set) var lastResult: String?

    init(interval: TimeInterval = 15 * 60, makeRail: @escaping () -> GmailRail?) {
        self.interval = interval
        self.makeRail = makeRail
    }

    /// True when the sync ran AND put something new in the queue, so the caller
    /// knows whether anything on screen is now stale.
    @discardableResult
    func syncIfDue(force: Bool = false) async -> Bool {
        guard !isRunning else { return false }
        if !force, let lastCompleted, Date.now.timeIntervalSince(lastCompleted) < interval {
            return false
        }
        guard let rail = makeRail() else { return false }

        isRunning = true
        defer { isRunning = false }

        do {
            let result = try await rail.sync()
            // On success only. A failed run must not start the clock, or one
            // offline moment buys fifteen minutes of not trying again.
            lastCompleted = .now
            lastResult = result.summary
            return result.queued > 0 || result.flagged > 0 || result.backlogTagged > 0
        } catch {
            // Swallowed on purpose. Nobody asked for this sync, so nobody is
            // waiting on an answer, and an error banner for a background fetch
            // is an interruption reporting something the person cannot fix.
            // The Debug screen still shows it.
            lastResult = "Failed: \(error.localizedDescription)"
            return false
        }
    }
}
