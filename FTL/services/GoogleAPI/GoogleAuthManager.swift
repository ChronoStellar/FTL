//
//  GoogleAuthManager.swift
//  google-api-test
//
//  Owns Google OAuth state via the GoogleSignIn SDK: sign-in / sign-out,
//  silent restore of a previous session, and handing out fresh access tokens.
//

import Foundation
import Combine
import UIKit
import GoogleSignIn

@MainActor
final class GoogleAuthManager: ObservableObject {
    static let shared = GoogleAuthManager()

    // MARK: - Configuration

    /// The OAuth client, read from `secrets.plist` — the file downloaded from the
    /// Google Cloud Console for the *iOS* client whose bundle ID matches this app.
    /// Keeping both IDs in one place means they can never drift apart in code; the
    /// reversed ID still has to be repeated as a URL scheme in Info.plist, which is
    /// what `configurationProblem` checks for at sign-in time.
    struct Secrets {
        let clientID: String
        let reversedClientID: String
        let bundleID: String?

        static let fileName = "secrets"

        /// Loads `secrets.plist` from the app bundle, or nil if it is missing or malformed.
        static func load(from bundle: Bundle = .main) -> Secrets? {
            guard let url = bundle.url(forResource: fileName, withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data, format: nil
                  ) as? [String: Any],
                  let clientID = plist["CLIENT_ID"] as? String,
                  let reversedClientID = plist["REVERSED_CLIENT_ID"] as? String
            else { return nil }

            return Secrets(
                clientID: clientID,
                reversedClientID: reversedClientID,
                bundleID: plist["BUNDLE_ID"] as? String
            )
        }
    }

    static let secrets = Secrets.load()

    // Scopes requested in addition to the default profile/email.
    static let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/spreadsheets",
    ]

    // MARK: - Published state

    @Published private(set) var user: GIDGoogleUser?
    @Published var errorMessage: String?

    var isSignedIn: Bool { user != nil }
    var email: String? { user?.profile?.email }
    var name: String? { user?.profile?.name }

    private init() {
        if let secrets = Self.secrets {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: secrets.clientID)
        }
        errorMessage = Self.configurationProblem
    }

    // MARK: - Auth actions

    /// Silently restores the previous session on launch, if one exists.
    func restore() async {
        guard Self.secrets != nil else { return } // Unconfigured; signIn() reports why.
        do {
            user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        } catch {
            user = nil // No previous session — expected on first launch.
        }
    }

    func signIn() async {
        // The SDK raises an uncatchable Obj-C exception (a hard crash) rather than
        // throwing if the client ID and URL scheme disagree, so check them first.
        if let problem = Self.configurationProblem {
            errorMessage = problem
            return
        }
        guard let presenter = Self.rootViewController else {
            errorMessage = "Could not find a view controller to present sign-in."
            return
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: Self.scopes
            )
            user = result.user
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        user = nil
    }

    /// Returns a valid access token, refreshing it first if it is close to expiry.
    func accessToken() async throws -> String {
        guard let user else { throw AuthError.notSignedIn }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }

    enum AuthError: LocalizedError {
        case notSignedIn
        var errorDescription: String? { "You are not signed in to Google." }
    }

    // MARK: - Helpers

    /// Every URL scheme declared under CFBundleURLTypes in Info.plist.
    static var registeredURLSchemes: [String] {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    }

    /// Describes the first misconfiguration that would make sign-in fail, or nil if
    /// everything lines up. Each of these otherwise surfaces as a crash or as an
    /// opaque `invalid_client` / `redirect_uri_mismatch` from Google.
    static var configurationProblem: String? {
        guard let secrets else {
            return "secrets.plist is missing from the app bundle, or has no CLIENT_ID / REVERSED_CLIENT_ID."
        }
        guard registeredURLSchemes.contains(secrets.reversedClientID) else {
            return """
            Info.plist doesn't register the URL scheme \(secrets.reversedClientID). \
            Add it under CFBundleURLTypes so Google can redirect back into the app.
            """
        }
        if let expected = secrets.bundleID, expected != Bundle.main.bundleIdentifier {
            return """
            secrets.plist was issued for bundle ID \(expected), but this app is \
            \(Bundle.main.bundleIdentifier ?? "unknown"). Google will reject the sign-in.
            """
        }
        return nil
    }

    /// Finds the key window's root view controller to present the OAuth flow from.
    static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
