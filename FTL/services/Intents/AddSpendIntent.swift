//
//  AddSpendIntent.swift
//  FTL — services/Intents · Phase 1
//
//  "Add spend" from Spotlight, Shortcuts, or Siri, without opening the app.
//
//  It records through `ManualEntry`, the same path the Add Spend sheet uses, so
//  a row typed into Spotlight is indistinguishable in the ledger from one typed
//  on the keypad — same source, same provenance, same immediate approval.
//  Invariant 1 is intact: this still goes cache → ApprovalService → ledger, and
//  there is no second way in.
//
//  Buckets come from the live sheet rather than a hard-coded list, because the
//  user's categories are whatever their budgets tab says they are.
//

import AppIntents
import Foundation

struct AddSpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Spend"
    static var description = IntentDescription(
        "Log a spend straight to your FTL ledger, without opening the app."
    )

    /// The whole point is not opening the app — the keypad screen is already
    /// two taps away if you wanted it.
    static var openAppWhenRun = false

    @Parameter(title: "Amount", description: "In rupiah, e.g. 25000")
    var amount: Int

    @Parameter(title: "Bucket", optionsProvider: BucketOptionsProvider())
    var bucket: String

    @Parameter(title: "Note", description: "Optional", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) to \(\.$bucket)") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = AppEnvironment.shared

        // A Spotlight run can be the first thing to touch the app after a cold
        // start, so the token may not be restored yet.
        if !environment.auth.isSignedIn {
            await environment.auth.restore()
        }
        guard environment.auth.isSignedIn else {
            throw AddSpendIntentError.notSignedIn
        }

        guard amount > 0 else { throw AddSpendIntentError.invalidAmount }

        // Match on the name the user picked, but fall back to the slug so a
        // typed or remembered value ("food") still lands.
        let categories = try await environment.ledger.categories()
        guard let category = categories.first(where: {
            $0.name.caseInsensitiveCompare(bucket) == .orderedSame
                || $0.id == CategoryID(rawValue: bucket)
        }) else {
            throw AddSpendIntentError.unknownBucket(bucket)
        }

        let money = Money.idr(amount)
        try await ManualEntry(
            provisional: environment.provisional,
            approvals: environment.approvals
        )
        .record(amount: money, categoryID: category.id, note: note)

        return .result(
            dialog: IntentDialog("Added \(MoneyFormatter.rp(money)) to \(category.name).")
        )
    }
}

// MARK: - Bucket options

/// Offers the buckets that actually exist in the user's sheet. Falls back to an
/// empty list rather than a guess: a made-up bucket name here would write spend
/// to a category the dashboard doesn't have.
struct BucketOptionsProvider: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        let environment = AppEnvironment.shared
        guard environment.auth.isSignedIn else { return [] }
        return (try? await environment.ledger.categories())?.map(\.name) ?? []
    }
}

// MARK: - Errors

enum AddSpendIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case invalidAmount
    case unknownBucket(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            "Open FTL and sign in with Google first."
        case .invalidAmount:
            "Enter an amount greater than zero."
        case .unknownBucket(let name):
            "There's no bucket called \(name) in your sheet."
        }
    }
}

// MARK: - Shortcut

/// Surfaces the intent in Spotlight and the Shortcuts app without the user
/// having to build anything first.
struct FTLShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddSpendIntent(),
            phrases: [
                "Add spend to \(.applicationName)",
                "Log a spend in \(.applicationName)",
                "\(.applicationName) add spend",
            ],
            shortTitle: "Add Spend",
            systemImageName: "plus.circle"
        )
    }
}
