//
//  BackgroundRefresh.swift
//  FTL — services/Capture
//
//  Fetching while the app is closed, and saying so.
//
//  `AutoSync` runs when the app becomes active — "I opened it and my receipts
//  were already there". This is the step its own doc comment deferred until the
//  foreground path had been proven: the same sync, run by iOS while the app is
//  not open, with a notification when something actually landed.
//
//  ## It is a LOCAL notification, not a push
//
//  There is no server in this architecture and that is the point — Gmail is read
//  on the device, parsing happens on the device, the ledger is the user's own
//  Sheet. Nothing anywhere is in a position to push. So the device wakes itself
//  up, looks, and posts a notification to itself. The difference a person sees
//  is timing: a real push arrives seconds after the receipt does, this arrives
//  whenever iOS next grants the app a window.
//
//  ## What iOS actually promises, which is very little
//
//  `BGAppRefreshTask` is opportunistic. The system decides when — learned from
//  when the app is normally used, deferred on low battery, not at all in Low
//  Power Mode, and never while the app is force-quit. `earliestBeginDate` is a
//  floor, never a schedule. Hours can pass. This is a nice-to-have on top of the
//  foreground sync, not a replacement for it, and the copy in Settings says so
//  rather than promising a freshness the OS will not deliver.
//
//  ## What it is allowed to do
//
//  Exactly what `AutoSync` is allowed to do, and for the same reason: fetch,
//  parse, dedup, flag — all of it into the provisional cache, all of it
//  recoverable (Invariant 7). It does NOT approve. Invariant 1 is a statement
//  about who writes to the ledger, and "the user was asleep" is not a human
//  gate.
//
//  Two things it skips that the foreground run does, both because of the ~30s
//  budget: the tagger (see `AppEnvironment.makeGmailRail(tagged:)`) and
//  discovery, which fetches its own 180-day window.
//

import BackgroundTasks
import Foundation
import UserNotifications

@MainActor
enum BackgroundRefresh {

    /// Must also appear in Info.plist under `BGTaskSchedulerPermittedIdentifiers`
    /// or registration throws at launch.
    static let taskIdentifier = "hend-aml.FTL.refresh"

    /// Whether the user asked for this. Off until they turn it on in Settings:
    /// scheduling background work and posting notifications are both things to
    /// be asked for, not assumed.
    @MainActor
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    private static let enabledKey = "backgroundRefreshEnabled"

    /// A floor, not a schedule — see the note above. Matched to `AutoSync`'s own
    /// freshness window so the two agree about how often is often enough.
    private static let earliest: TimeInterval = 15 * 60

    // MARK: - Lifecycle

    /// Registered once, before the app finishes launching, or iOS refuses the
    /// handler. Safe to call when disabled: registering costs nothing and the
    /// task is only ever submitted by `schedule()`.
    static func register(environment: @escaping () -> AppEnvironment) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            MainActor.assumeIsolated { handle(task, environment: environment()) }
        }
    }

    /// Asks for the next window. Called on every background transition, because
    /// a submitted task is consumed by its one run — not rescheduling is how
    /// this silently stops working after the first fetch.
    static func schedule() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliest)
        // Throws when the app is not permitted (Background App Refresh off
        // system-wide, Low Power Mode, a simulator without the capability).
        // Nothing a person can act on from here, and the foreground sync still
        // covers them, so it is recorded and not surfaced.
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    // MARK: - The run

    private static func handle(_ task: BGAppRefreshTask, environment: AppEnvironment) {
        // Chain the next one FIRST. If this run is killed at the expiration
        // handler, a request submitted after the work would never be made.
        schedule()

        let work = Task { @MainActor in
            let landed = await run(environment: environment)

            // Unconditionally, not just when rows landed. The home screen
            // figures go stale on their own as the month runs down — the
            // per-day allowance moves every midnight whether or not anything
            // was bought — so this is the one chance to correct them without
            // the app being opened.
            await WidgetSnapshotWriter(
                calc: environment.calc,
                provisional: environment.provisional
            ).write()

            // Whether or not anything landed: a fetch that found nothing still
            // confirms what is waiting, and the reminder should not go on
            // quoting a count from before the app last ran.
            let pending = (try? await environment.provisional.pending())?.count ?? 0
            await NotificationSchedule.refreshDigest(pendingCount: pending)

            if landed > 0 { await notify(count: landed) }
            task.setTaskCompleted(success: true)
        }

        // iOS gives no warning beyond this. Whatever the rail has already
        // written to the provisional cache stays written — the cache is the
        // recoverable layer, so a half-finished sync costs a re-fetch and
        // nothing else.
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Returns how many rows reached the queue, which is the only thing worth
    /// interrupting somebody for.
    private static func run(environment: AppEnvironment) async -> Int {
        guard let rail = environment.makeGmailRail(tagged: false) else { return 0 }
        do {
            let result = try await rail.sync()
            return result.queued
        } catch {
            // Same reasoning as `AutoSync`: nobody asked, nobody is waiting, and
            // a notification saying the fetch failed is an interruption about
            // something the person cannot act on.
            return 0
        }
    }

    // MARK: - Notification

    /// Asks for permission. Foreground only — a prompt cannot be shown from a
    /// background task, which is why the Settings toggle is where this lives.
    static func requestAuthorization() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted
    }

    private static func notify(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "1 charge to approve" : "\(count) charges to approve"
        // No amounts and no merchant names on the lock screen. This app reads a
        // person's mailbox; what it found there is not something to put where a
        // stranger glancing at the phone can read it.
        content.body = "Captured while you were away. Nothing counts against a bucket until you approve it."
        content.sound = .default

        // nil trigger — deliver now. The work already happened.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
