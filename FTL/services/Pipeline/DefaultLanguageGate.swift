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

    func canProcess(_ text: String, for task: ModelTask) -> GateDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .refuse(.emptyContent) }
        guard trimmed.count <= Self.maxCharacters else { return .refuse(.tooLong) }

        // The two cheap physical limits above apply to every call — an empty
        // prompt and a context overflow are failures whatever the task.
        //
        // The language check is not physical, it is a TRUST judgement, and it
        // only earns its keep when the model's answer is taken on trust.
        // Synthesis is verified against real emails before it can affect
        // anything, so refusing it here doesn't prevent a wrong answer — it
        // prevents finding out. See `ModelTask.anchorSynthesis`.
        guard task == .classification else { return .allow }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        // No confident guess is not the same as the wrong language: a short
        // templated receipt often has too few words to identify. Let it through
        // and let the schema catch a bad answer.
        guard let language = recognizer.dominantLanguage else { return .allow }
        return Self.supported.contains(language) ? .allow : .refuse(.unsupportedLanguage)
    }

    /// The recognizer's verdict on the exact strings a caller is about to gate.
    ///
    /// Exists so a debug run can print what the gate SAW rather than only what
    /// it decided. Twice now a gate refusal has been diagnosed by reasoning
    /// about which text it must have been reading; this makes that observable.
    static func languageTally(of excerpts: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for excerpt in excerpts {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(excerpt)
            counts[recognizer.dominantLanguage?.rawValue ?? "undetermined", default: 0] += 1
        }
        return counts
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
