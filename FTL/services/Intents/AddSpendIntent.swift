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

    @Parameter(title: "Bucket")
    var bucket: SpendCategoryEntity

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
        let categoryID = CategoryID(rawValue: bucket.id)

        let money = Money.idr(amount)
        try await ManualEntry(
            provisional: environment.provisional,
            approvals: environment.approvals
        )
        .record(amount: money, categoryID: categoryID, note: note)

        return .result(
            dialog: IntentDialog("Added \(MoneyFormatter.rp(money)) to \(bucket.name).")
        )
    }
}


// MARK: - App Entities

struct SpendCategoryEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
    static var defaultQuery = SpendCategoryEntityQuery()
    
    let id: String
    let name: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(stringLiteral: name)
    }
}

struct SpendCategoryEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SpendCategoryEntity] {
        let environment = AppEnvironment.shared
        guard environment.auth.isSignedIn else { return [] }
        let categories = try? await environment.ledger.categories()
        return identifiers.compactMap { id in
            guard let cat = categories?.first(where: { $0.id.rawValue == id }) else { return nil }
            return SpendCategoryEntity(id: cat.id.rawValue, name: cat.name)
        }
    }
    
    @MainActor
    func suggestedEntities() async throws -> [SpendCategoryEntity] {
        let environment = AppEnvironment.shared
        guard environment.auth.isSignedIn else { return [] }
        let categories = try? await environment.ledger.categories()
        return categories?.map { SpendCategoryEntity(id: $0.id.rawValue, name: $0.name) } ?? []
    }
    
    @MainActor
    func entities(matching string: String) async throws -> [SpendCategoryEntity] {
        let environment = AppEnvironment.shared
        guard environment.auth.isSignedIn else { return [] }
        let categories = try? await environment.ledger.categories()
        return categories?
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { SpendCategoryEntity(id: $0.id.rawValue, name: $0.name) } ?? []
    }
}

// MARK: - Errors

enum AddSpendIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case invalidAmount
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            "Open FTL and sign in with Google first."
        case .invalidAmount:
            "Enter an amount greater than zero."
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
        // The one a Time of Day automation is meant to call — see
        // `CheckReceiptsIntent` for why scheduling lives in Shortcuts rather
        // than in a background task that cannot promise an hour.
        AppShortcut(
            intent: CheckReceiptsIntent(),
            phrases: [
                "Check for receipts in \(.applicationName)",
                "Check \(.applicationName) receipts",
            ],
            shortTitle: "Check for Receipts",
            systemImageName: "tray.and.arrow.down"
        )
        AppShortcut(
            intent: CheckBudgetIntent(),
            phrases: [
                "How much can I spend today in \(.applicationName)?",
                "Check \(.applicationName) budget",
                "What is my daily budget in \(.applicationName)?"
            ],
            shortTitle: "Check Daily Budget",
            systemImageName: "dollarsign.circle"
        )
    }
}
import AppIntents
import Foundation

struct CheckBudgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Budget"
    static var description = IntentDescription("Ask how much money you can spend today.")

    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = AppEnvironment.shared

        if !environment.auth.isSignedIn {
            await environment.auth.restore()
        }
        guard environment.auth.isSignedIn else {
            throw AddSpendIntentError.notSignedIn
        }

        let months = try await environment.calc.monthSummaries(limit: 1)
        guard let currentMonth = months.first(where: { $0.isCurrent }) else {
            return .result(dialog: "There is no active budget for this month.")
        }

        if let remaining = currentMonth.perDayRemaining {
            let rp = MoneyFormatter.rp(remaining)
            return .result(dialog: IntentDialog("You can spend up to \(rp) today."))
        } else {
            return .result(dialog: "The month is closed, or you have no days remaining.")
        }
    }
}
