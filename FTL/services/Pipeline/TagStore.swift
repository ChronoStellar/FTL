//
//  TagStore.swift
//  FTL — services/Pipeline
//
//  Single source of truth for financial tags: canonical categories, service providers
//  (banks, payment rails, e-wallets), and merchant keyword rules.
//  Backed by a fast, editable JSON store.
//

import Foundation

nonisolated struct TagData: Codable, Sendable {
    var categories: [String]
    var serviceProviders: [ServiceProviderInfo]
    var keywordRules: [KeywordRule]

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
            "Food & Dining",
            "Ride & Transport",
            "Groceries & Supermarket",
            "E-Commerce & Shopping",
            "Utilities & Bills",
            "Subscriptions & Digital",
            "Bank Transfer / Top-Up",
            "Refund / Inflow",
            "Marketing / Notification"
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

    /// Checks if a given query string corresponds to a known banking/rail service provider.
    func identifyServiceProvider(_ query: String) -> String? {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for provider in cachedData.serviceProviders {
            if provider.name.lowercased().contains(q) {
                return provider.name
            }
            for alias in provider.aliases {
                if alias.lowercased() == q || q.contains(alias.lowercased()) {
                    return provider.name
                }
            }
        }
        return nil
    }

    /// Formats a clean reference guide for model system instructions.
    func promptTaxonomyGuide() -> String {
        let categoriesList = cachedData.categories.map { "- \($0)" }.joined(separator: "\n")
        let providersList = cachedData.serviceProviders.map { "\($0.name) (aliases: \($0.aliases.joined(separator: ", ")))" }.joined(separator: "; ")

        return """
        CANONICAL CATEGORIES:
        \(categoriesList)

        KNOWN SERVICE PROVIDERS (Banks, Rails, E-Wallets — NOT merchants):
        \(providersList)
        """
    }
}
