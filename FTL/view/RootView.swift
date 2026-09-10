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
    /// DEBUG only: whether `environment` is the fixture one. Owned by FTLApp so
    /// the flag and the environment can never disagree.
    var isSampleMode: Bool = false
    var onUseSampleData: () -> Void = {}
    /// DEBUG only — see `SignInView`. Swaps the environment BEFORE the real
    /// sign-in that follows it, so the mailbox is real but the ledger isn't.
    var onUseLocalLedger: () -> Void = {}

    @State private var hasAttemptedRestore = false

    private var isUnlocked: Bool {
        #if DEBUG
        return auth.isSignedIn || isSampleMode
        #else
        return auth.isSignedIn
        #endif
    }

    var body: some View {
        Group {
            if !hasAttemptedRestore {
                launchPlaceholder
            } else if isUnlocked {
                // Rebuild from scratch when the environment is swapped: the
                // screens hold their view models in @State and would otherwise
                // keep the ones built against the old store.
                ContentView(environment: environment)
                    .id(ObjectIdentifier(environment))
            } else {
                SignInView(onDebugBypass: onUseSampleData, onDebugLocalLedger: onUseLocalLedger)
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
