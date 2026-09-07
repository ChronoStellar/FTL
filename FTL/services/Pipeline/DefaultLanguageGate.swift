//
//  DefaultLanguageGate.swift
//  FTL — services/Pipeline
//
//  Invariant 9, and the cheapest useful measurement you can run today.
//
//  Measured 2026-09-03: the on-device framework refused 4 of 4 Indonesian
//  prompts and 0 of 4 English controls on identical transactions. This gate runs
//  BEFORE any model call so a refusal is a decision the app made — flagged, cheap,
//  local — rather than an exception thrown from inside the framework.
//
//  Run it over the corpus on its own, with no model, to find out what share of
//  your actual receipts the classifier could ever process. If that number is
//  small, the classifier is not the next thing to build.
//

import Foundation
import NaturalLanguage

struct DefaultLanguageGate: LanguageGate {
    /// Languages the framework handled without refusing.
    static let supported: Set<NLLanguage> = [.english]

    /// 2 context overflows in 84 calls. Truncate rather than discover the limit
    /// at runtime — a receipt's signal is in its first paragraph anyway.
    static let maxCharacters = 4_000

    func canProcess(_ text: String) -> GateDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .refuse(.emptyContent) }
        guard trimmed.count <= Self.maxCharacters else { return .refuse(.tooLong) }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        // No confident guess is not the same as the wrong language: a short
        // templated receipt often has too few words to identify. Let it through
        // and let the schema catch a bad answer.
        guard let language = recognizer.dominantLanguage else { return .allow }
        return Self.supported.contains(language) ? .allow : .refuse(.unsupportedLanguage)
    }

    /// What language each email is in, no model involved. Feeds the "can the
    /// classifier even see my receipts?" question.
    static func languageBreakdown(_ emails: [CapturedEmail]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for email in emails {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(email.searchText)
            let key = recognizer.dominantLanguage?.rawValue ?? "undetermined"
            counts[key, default: 0] += 1
        }
        return counts
    }
}
