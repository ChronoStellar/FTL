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
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .environmentObject(auth)
                .onOpenURL { url in
                    // Completes the OAuth redirect back into the app.
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
