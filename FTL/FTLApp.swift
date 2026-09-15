//
//  FTLApp.swift
//  FTL
//
//  Created by Hendrik Nicolas Carlo on 03/09/26.
//

import SwiftUI
import GoogleSignIn

@main
struct FTLApp: App {
    @StateObject private var auth = GoogleAuthManager.shared

    /// The live environment reads and writes the user's own Google Sheet. The
    /// DEBUG skip-sign-in path swaps it for fixtures, because without a token
    /// every Sheets call would fail and the UI would be unworkable.
    @State private var environment = AppEnvironment.shared
    @State private var isBypassActive = false

    /// Backgrounding is what schedules the next unattended fetch.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must happen before the app finishes launching or iOS refuses the
        // handler, which is why it is here and not in a `.task`. Registering
        // when the feature is off costs nothing — the task is only ever
        // submitted by `BackgroundRefresh.schedule()`.
        //
        // `.shared` deliberately, not the `@State` environment: a background run
        // has no UI and no sample mode, and a fetch that ran against fixtures
        // would write nothing and notify about nothing.
        BackgroundRefresh.register { AppEnvironment.shared }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                environment: environment,
                isSampleMode: isBypassActive,
                onUseSampleData: {
                    environment = .sample()
                    isBypassActive = true
                },
                onUseLocalLedger: {
                    // Real sign-in still follows this — see SignInView. This
                    // only decides which environment that sign-in lands in.
                    environment = .liveWithoutSheet()
                }
            )
            .environmentObject(auth)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                // Completes the OAuth redirect back into the app.
                GIDSignIn.sharedInstance.handle(url)
            }
            // A submitted task is consumed by its one run, so the next one is
            // asked for every time the app goes away. Not doing this is how
            // background refresh silently stops after the first fetch.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background else { return }
                BackgroundRefresh.schedule()
            }
        }
    }
}
