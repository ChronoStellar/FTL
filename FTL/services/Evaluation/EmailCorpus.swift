//
//  EmailCorpus.swift
//  FTL — services/Evaluation
//
//  Loads the fixture corpus and its labels. The bridge between your Python
//  tooling and the Swift under test: JSON in, JSON out, nothing shared but the
//  file format.
//
//  ⚠️ BOTH corpora ship in the app bundle: `sample.json` (6.6 MB) and
//  `gmail_export.json` (75 MB) — 82 MB of real email metadata in a 94 MB app.
//  Roadmap Stage 0 #3 still records this as "6.6 MB"; it isn't. This has to be
//  gated out of Release before any build leaves the device.
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

    /// Defaults to `gmail_export.json` — the export that KEPT `bodyHtml`.
    ///
    /// `sample.json` had bodies stripped, so every parser measured against it
    /// was really measured against Gmail snippets. That number didn't transfer:
    /// `BluReceiptParser` scored 116/116 on snippets and 3/112 the first time
    /// GmailRail handed it a real HTML body, because a stripped table puts each
    /// field on its own line. A harness that can't see that shape can't catch
    /// that class of bug. Falls back to `sample.json` when the export isn't
    /// present.
    ///
    /// ⚠️ The export is ~75 MB on disk and decodes to substantially more in
    /// memory. Fine for a DEBUG harness run; it is not something to load on a
    /// screen the user waits for.
    static func load(
        emails emailResource: String = "gmail_export",
        labels labelResource: String = "labels",
        bundle: Bundle = .main
    ) throws -> EmailCorpus {
        let url = bundle.url(forResource: emailResource, withExtension: "json")
            ?? bundle.url(forResource: "sample", withExtension: "json")
        guard let url else {
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

    /// Emails that contain currency markers (Rp / IDR), candidate receipts.
    func emailsWithCurrency() -> [CapturedEmail] {
        emails.filter { $0.hasCurrencyMarker }
    }
}
