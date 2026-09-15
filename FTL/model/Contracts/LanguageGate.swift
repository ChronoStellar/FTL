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

/// What the model is being asked to do — which decides how strict the gate is.
///
/// The 4-of-4 Indonesian refusal was measured on ONE task: read a receipt and
/// say what it is. That is a task whose answer is the product, taken on trust,
/// unrecoverable when wrong — so a language the model handles badly has to be
/// refused up front.
///
/// Synthesis is not that task. It asks the model to copy the literal words that
/// sit beside a number, and its answer is not trusted at all: `PatternVerifier`
/// runs the proposal over real emails and scores it deterministically before it
/// can touch anything. A bad proposal costs a retry.
///
/// So the gate keeps its job — every model call still passes through it,
/// Invariant 9 intact — but it answers the question the call actually raises.
nonisolated enum ModelTask: Sendable, Hashable {
    /// The model's answer IS the output. Strict: refuse what it handles badly.
    case classification

    /// The model's answer is a PROPOSAL, checked against real data before use.
    ///
    /// Language is not the right filter here, and applying it cost the Grab
    /// food layout outright: 10 of 10 excerpts read as Indonesian and were
    /// refused before the model was asked whether it could point at the word
    /// `TOTAL` — which is not a question about Indonesian. Whether the model
    /// can actually do it is now decided the way everything else in the loop
    /// is decided: by measuring the result.
    case anchorSynthesis
}

nonisolated protocol LanguageGate: Sendable {
    /// Cheap, local, no model call. Refusal means "do not attempt" — the caller
    /// flags and moves on.
    func canProcess(_ text: String, for task: ModelTask) -> GateDecision
}

extension LanguageGate {
    /// Classification is the strict default, so an unannotated call site cannot
    /// accidentally acquire the permissive behaviour.
    func canProcess(_ text: String) -> GateDecision {
        canProcess(text, for: .classification)
    }
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
