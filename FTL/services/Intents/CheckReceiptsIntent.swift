//
//  CheckReceiptsIntent.swift
//  FTL — services/Intents
//
//  "Check for receipts" from Shortcuts, Siri or Spotlight — and the honest
//  answer to scheduling a fetch at a set hour.
//
//  `BackgroundRefresh` asks iOS for a window and iOS decides when, which is
//  opportunistic by design and cannot be pinned to 8am. A Personal Automation
//  CAN: Shortcuts will run this at a time the user picks, every day, and that is
//  the only way an app on this platform gets scheduled execution it can predict.
//  So rather than pretend `BGAppRefreshTask` is a scheduler, the app exposes the
//  work as something the system's own scheduler can call.
//
//  Setup is two steps in Shortcuts — New Automation → Time of Day → "Check for
//  receipts" — which Settings spells out, because an intent nobody knows exists
//  is not a feature.
//
//  Same boundary as every other unattended path: it fetches, parses, dedups and
//  tags into the provisional cache, and approves nothing. Invariant 1 does not
//  bend for a scheduler.
//

import AppIntents
import Foundation

struct CheckReceiptsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check for Receipts"
    static var description = IntentDescription(
        "Fetch new receipts from Gmail into your approval queue, and refresh the widgets. Attach this to a Time of Day automation to check at a set hour."
    )

    /// Runs headless. Opening the app would defeat an automation meant to run
    /// while the phone is in a pocket.
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = AppEnvironment.shared

        // A scheduled run is routinely the first thing to touch the app after a
        // cold start, so the token may not be restored yet — same reason
        // `AddSpendIntent` does this.
        if !environment.auth.isSignedIn {
            await environment.auth.restore()
        }
        guard environment.auth.isSignedIn else {
            throw CheckReceiptsIntentError.notSignedIn
        }

        // `force: true` — the person (or their automation) asked for this
        // specific check, so the 15-minute freshness throttle that exists to
        // stop app-switching costing quota does not apply.
        let landed = await environment.autoSync.syncIfDue(force: true)

        await WidgetSnapshotWriter(
            calc: environment.calc,
            provisional: environment.provisional
        ).write()

        let pending = (try? await environment.provisional.pending())?.count ?? 0
        await NotificationSchedule.refreshDigest(pendingCount: pending)

        if pending == 0 {
            return .result(dialog: "Nothing waiting.")
        }
        return .result(dialog: landed
            ? "\(pending) waiting to approve."
            : "Nothing new. \(pending) still waiting to approve.")
    }
}

enum CheckReceiptsIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn: return "Open FTL and sign in with Google first."
        }
    }
}
