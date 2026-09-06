//
//  LanguageGate.swift
//  FTL — model/Contracts · Phase 2
//
//  Invariant 9. Measured 2026-09-03: the on-device framework refused 4 of 4
//  Indonesian prompts and 0 of 4 English controls on identical transactions, and
//  28 of 84 calls suite-wide were refused before the model saw them.
//
//  This ledger's own language is not reliably processable on-device. Every model
//  call is gated here first, and a refusal is a normal, expected outcome — not an
//  error path. A gated-out row still produces a cache entry, flagged
//  `.languageUnsupported`. It is never dropped and never guessed at.
//
//  Implementation: services/Agent/DefaultLanguageGate
//

import Foundation

nonisolated protocol LanguageGate: Sendable {
    /// Cheap, local, no model call. False means "do not attempt" — the caller
    /// flags and moves on.
    func canProcess(_ text: String) -> GateDecision
}

nonisolated enum GateDecision: Sendable, Hashable {
    case allow
    case refuse(Reason)

    nonisolated enum Reason: String, Sendable, Hashable {
        case unsupportedLanguage
        case tooLong          // 2 context overflows in the feasibility run
        case emptyContent
    }
}
