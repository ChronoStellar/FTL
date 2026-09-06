//
//  RootView.swift
//  FTL — view
//
//  The auth gate. Three states, and the third one matters: while a previous
//  session is being restored we show neither screen, because flashing the sign-in
//  view at someone who is already signed in is the most common way this gate goes
//  wrong.
//
//  Session state is the one service views read directly, through the environment.
//  It gates the app rather than feeding it data, so it does not belong behind a
//  view model. Everything else goes through one.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: GoogleAuthManager
    let environment: AppEnvironment

    @State private var hasAttemptedRestore = false

    /// DEBUG only: lets the tabs be opened without a Google account, so UI work
    /// doesn't require a live session. Compiled out of Release along with the
    /// button that sets it.
    @State private var bypassAuth = false

    private var isUnlocked: Bool {
        #if DEBUG
        return auth.isSignedIn || bypassAuth
        #else
        return auth.isSignedIn
        #endif
    }

    var body: some View {
        Group {
            if !hasAttemptedRestore {
                launchPlaceholder
            } else if isUnlocked {
                ContentView(environment: environment)
            } else {
                SignInView(onDebugBypass: { bypassAuth = true })
            }
        }
        .task {
            guard !hasAttemptedRestore else { return }
            await auth.restore()
            hasAttemptedRestore = true
        }
    }

    private var launchPlaceholder: some View {
        ZStack {
            GlowBackground()
            ProgressView().tint(FTLColor.textTertiary)
        }
    }
}
