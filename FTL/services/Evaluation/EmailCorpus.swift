//
//  EmailCorpus.swift
//  FTL — services/Evaluation
//
//  Loads the fixture corpus and its labels. The bridge between your Python
//  tooling and the Swift under test: JSON in, JSON out, nothing shared but the
//  file format.
//
//  ⚠️ `test/sample.json` is 6.6 MB and ships in the app bundle so the on-device
//  harness can read it. Move it behind a DEBUG-only resource rule before any
//  build that leaves your phone.
//

import Foundation

struct EmailCorpus: Sendable {
    let emails: [CapturedEmail]
    let labels: [String: Label]

    /// Ground truth for one email, keyed by Gmail message id.
    ///
    /// Produce this from Python — sampling and labelling are what you are fast
    /// at, and there is no reason to rewrite them here.
    struct Label: Sendable, Hashable, Codable {
        let isPurchase: Bool
        /// Minor units. Nil when `isPurchase` is false.
        let amount: Int?
        let merchant: String?
        let category: String?
        let kind: String?          // "spend" | "nonSpend"
        /// Free text — why this one is interesting. Shows up in the report.
        let note: String?
    }

    // MARK: - Loading

    enum LoadError: Error, LocalizedError {
        case missing(String)
        var errorDescription: String? {
            if case .missing(let name) = self {
                return "\(name) is not in the app bundle. Check it is inside FTL/ so the synchronized group picks it up."
            }
            return nil
        }
    }

    static func load(
        emails emailResource: String = "sample",
        labels labelResource: String = "labels",
        bundle: Bundle = .main
    ) throws -> EmailCorpus {
        guard let url = bundle.url(forResource: emailResource, withExtension: "json") else {
            throw LoadError.missing("\(emailResource).json")
        }
        let decoder = JSONDecoder()
        let emails = try decoder.decode([CapturedEmail].self, from: Data(contentsOf: url))

        // Labels are optional: an unlabelled run still reports coverage, latency
        // and refusals, which is enough to tell you whether the model is even
        // reachable before you have spent an afternoon labelling.
        var labels: [String: Label] = [:]
        if let labelURL = bundle.url(forResource: labelResource, withExtension: "json"),
           let data = try? Data(contentsOf: labelURL) {
            labels = (try? decoder.decode([String: Label].self, from: data)) ?? [:]
        }
        return EmailCorpus(emails: emails, labels: labels)
    }

    // MARK: - Sampling

    /// Senders that are never purchases. Free negatives — roughly 450 of the
    /// thousand — so hand-labelling can be spent on the ~216 that are ambiguous.
    static let knownNonPurchaseDomains: Set<String> = [
        "linkedin.com", "update.strava.com", "news.edx.org", "github.com",
        "nvidia.com", "binus.edu", "insideapple.apple.com",
    ]

    /// Emails worth a human's attention, newest first. Everything else is either
    /// auto-labelled or noise.
    func needingLabels() -> [CapturedEmail] {
        emails
            .filter { labels[$0.id] == nil }
            .filter { !Self.knownNonPurchaseDomains.contains($0.senderDomain) }
            .sorted { $0.date > $1.date }
    }

    func emails(from domain: String) -> [CapturedEmail] {
        emails.filter { $0.senderDomain.hasSuffix(domain) }
    }
}
