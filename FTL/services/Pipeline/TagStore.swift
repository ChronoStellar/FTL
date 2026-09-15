//
//  TagStore.swift
//  FTL — services/Pipeline
//
//  Single source of truth for financial tags: canonical categories, service providers
//  (banks, payment rails, e-wallets), and merchant keyword rules.
//  Backed by a fast, editable JSON store.
//
//  Each category carries its own `ledgerTreatment`. This is what lets
//  FoundationModelClassifier derive `kind` (spend / non-spend / not-a-transaction)
//  from the model's own categorical choice instead of a second, independent
//  boolean — the model previously emitted `isTransferOrRefund` with no required
//  agreement with `transactionType`, so a refund whose boolean disagreed with its
//  own category fell through with `kind = nil` and vanished. A category not in
//  this list is now a detectable event (flag it) instead of silently-accepted
//  free text.
//

import Foundation

nonisolated struct TagData: Codable, Sendable {
    var categories: [CategoryInfo]
    var serviceProviders: [ServiceProviderInfo]
    var keywordRules: [KeywordRule]

    nonisolated struct CategoryInfo: Codable, Sendable, Identifiable, Hashable {
        var id: String { name }
        var name: String
        /// "spend" | "nonSpend" | "notATransaction". Not `TransactionKind`
        /// directly — "notATransaction" has no row to have a kind at all, it
        /// means the category is marketing/noise and nothing gets created.
        var ledgerTreatment: String
        /// One of `NonSpendType`'s raw values ("refund", "transfer", "topup",
        /// "creditCardPayment", "cashback"), or nil when the category doesn't map
        /// cleanly to one — "Bank Transfer / Top-Up" straddles two and is left
        /// nil rather than guessed. Meaningless unless `ledgerTreatment == "nonSpend"`.
        var nonSpendType: String?

        init(name: String, ledgerTreatment: String, nonSpendType: String? = nil) {
            self.name = name
            self.ledgerTreatment = ledgerTreatment
            self.nonSpendType = nonSpendType
        }
    }

    nonisolated struct ServiceProviderInfo: Codable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        var aliases: [String]
        var type: String // "bank" | "ewallet" | "payment_gateway"

        init(name: String, aliases: [String], type: String) {
            self.name = name
            self.aliases = aliases
            self.type = type
        }
    }

    nonisolated struct KeywordRule: Codable, Sendable {
        var keyword: String
        var category: String

        init(keyword: String, category: String) {
            self.keyword = keyword
            self.category = category
        }
    }

    static let defaults = TagData(
        categories: [
            CategoryInfo(name: "Food & Dining", ledgerTreatment: "spend"),
            CategoryInfo(name: "Ride & Transport", ledgerTreatment: "spend"),
            CategoryInfo(name: "Groceries & Supermarket", ledgerTreatment: "spend"),
            CategoryInfo(name: "E-Commerce & Shopping", ledgerTreatment: "spend"),
            CategoryInfo(name: "Utilities & Bills", ledgerTreatment: "spend"),
            CategoryInfo(name: "Subscriptions & Digital", ledgerTreatment: "spend"),
            CategoryInfo(name: "Bank Transfer / Top-Up", ledgerTreatment: "nonSpend"),
            CategoryInfo(name: "Refund / Inflow", ledgerTreatment: "nonSpend", nonSpendType: "refund"),
            CategoryInfo(name: "Marketing / Notification", ledgerTreatment: "notATransaction"),
        ],
        serviceProviders: [
            ServiceProviderInfo(name: "blu by BCA Digital", aliases: ["blu", "bluAccount", "blubybcadigital.id"], type: "bank"),
            ServiceProviderInfo(name: "Bank Central Asia", aliases: ["BCA", "myBCA", "KlikBCA"], type: "bank"),
            ServiceProviderInfo(name: "Bank Mandiri", aliases: ["Mandiri", "Livin' by Mandiri", "Livin", "bankmandiri.co.id"], type: "bank"),
            ServiceProviderInfo(name: "Bank Rakyat Indonesia", aliases: ["BRI", "BRImo", "bri.co.id"], type: "bank"),
            ServiceProviderInfo(name: "Bank Negara Indonesia", aliases: ["BNI", "BNI Mobile", "bni.co.id"], type: "bank"),
            ServiceProviderInfo(name: "CIMB Niaga", aliases: ["CIMB", "OCTO Mobile"], type: "bank"),
            ServiceProviderInfo(name: "Bank Permata", aliases: ["Permata", "PermataME"], type: "bank"),
            ServiceProviderInfo(name: "Jenius", aliases: ["Jenius", "BTPN"], type: "bank"),
            ServiceProviderInfo(name: "GoPay", aliases: ["GoPay", "Gojek", "GoTo"], type: "ewallet"),
            ServiceProviderInfo(name: "OVO", aliases: ["OVO", "Visionet"], type: "ewallet"),
            ServiceProviderInfo(name: "DANA", aliases: ["DANA", "DANA Indonesia"], type: "ewallet"),
            ServiceProviderInfo(name: "ShopeePay", aliases: ["ShopeePay", "SeaBank"], type: "ewallet")
        ],
        keywordRules: [
            KeywordRule(keyword: "gofood", category: "Food & Dining"),
            KeywordRule(keyword: "grabfood", category: "Food & Dining"),
            KeywordRule(keyword: "shopeefood", category: "Food & Dining"),
            KeywordRule(keyword: "goride", category: "Ride & Transport"),
            KeywordRule(keyword: "gocar", category: "Ride & Transport"),
            KeywordRule(keyword: "grabcar", category: "Ride & Transport"),
            KeywordRule(keyword: "tokopedia", category: "E-Commerce & Shopping"),
            KeywordRule(keyword: "shopee", category: "E-Commerce & Shopping"),
            KeywordRule(keyword: "indomaret", category: "Groceries & Supermarket"),
            KeywordRule(keyword: "alfamart", category: "Groceries & Supermarket"),
            KeywordRule(keyword: "pln", category: "Utilities & Bills"),
            KeywordRule(keyword: "telkomsel", category: "Utilities & Bills"),
            KeywordRule(keyword: "spotify", category: "Subscriptions & Digital"),
            KeywordRule(keyword: "netflix", category: "Subscriptions & Digital")
        ]
    )
}

actor TagStore {
    static let shared = TagStore()

    private var cachedData: TagData
    private let fileURL: URL

    private init() {
        let fileManager = FileManager.default
        let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let url = docDir.appendingPathComponent("tag_store.json")
        self.fileURL = url

        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(TagData.self, from: data) {
            self.cachedData = loaded
        } else {
            self.cachedData = .defaults
            // Write defaults to disk
            if let initialData = try? JSONEncoder().encode(TagData.defaults) {
                try? initialData.write(to: url, options: .atomic)
            }
        }
    }

    func get() -> TagData {
        cachedData
    }

    func update(_ data: TagData) throws {
        cachedData = data
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        try encoded.write(to: fileURL, options: .atomic)
    }

    /// Replaces the "spend" entries with the categories actually sitting in the
    /// user's own Sheet, leaving the fixed non-spend / notATransaction entries
    /// untouched — those describe how the app itself routes money movement
    /// (a transfer, a refund, marketing noise) and were never a budget bucket a
    /// person set up, so a Sheet has nothing to say about them.
    ///
    /// Google Sheets is canonical (CLAUDE.md); `TagData.defaults`' six spend
    /// names were only ever a placeholder for a sheet that doesn't have its own
    /// yet. Call this whenever the live ledger's categories are available, so
    /// the model is never asked to classify against a taxonomy the user didn't
    /// choose. Never call it from the evaluation harness — that runs against a
    /// fixed corpus and needs a fixed taxonomy to stay reproducible.
    ///
    /// Keyword rules whose target category didn't survive reconciliation are
    /// dropped rather than left dangling — a rule pointing at nothing is worse
    /// than no rule (Invariant 6: escalate, don't guess).
    func reconcile(spendCategories: [SpendCategory]) throws {
        let fixed = cachedData.categories.filter { $0.ledgerTreatment != "spend" }
        let reconciledSpend = spendCategories.map {
            TagData.CategoryInfo(name: $0.name, ledgerTreatment: "spend")
        }
        let validNames = Set((fixed + reconciledSpend).map(\.name))

        var next = cachedData
        next.categories = reconciledSpend + fixed
        next.keywordRules = cachedData.keywordRules.filter { validNames.contains($0.category) }
        try update(next)
    }

    /// Case-insensitive, exact-name lookup against the canonical category list.
    /// nil means the model named a category that isn't in the store — the caller
    /// must flag this rather than trust the free text.
    func categoryInfo(named name: String) -> TagData.CategoryInfo? {
        let q = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return cachedData.categories.first { $0.name.lowercased() == q }
    }

    /// Formats a clean reference guide for model system instructions.
    func promptTaxonomyGuide() -> String {
        let categoriesList = cachedData.categories
            .map { "- \($0.name) [\($0.ledgerTreatment)]" }
            .joined(separator: "\n")
        let providersList = cachedData.serviceProviders.map { "\($0.name) (aliases: \($0.aliases.joined(separator: ", ")))" }.joined(separator: "; ")

        return """
        CANONICAL CATEGORIES (must choose one of these EXACTLY — a category not on \
        this list will be rejected):
        \(categoriesList)

        KNOWN SERVICE PROVIDERS (Banks, Rails, E-Wallets — NOT merchants):
        \(providersList)
        """
    }
}
