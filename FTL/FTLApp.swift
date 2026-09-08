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

    var body: some Scene {
        WindowGroup {
            RootView(
                environment: environment,
                isSampleMode: isBypassActive,
                onUseSampleData: {
                    environment = .sample()
                    isBypassActive = true
                }
            )
            .environmentObject(auth)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                // Completes the OAuth redirect back into the app.
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
