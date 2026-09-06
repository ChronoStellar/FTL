//
//  DocumentNormalizer.swift
//  FTL — model/Contracts · Phase 1
//
//  Deterministic parsing: raw document in, fingerprinted candidates out. No model,
//  no network, no judgment about whether the result is a purchase.
//
//  This layer fails loudly. An unparseable document produces a flagged entry, never
//  a silently dropped one — a transaction that vanishes without trace is worse than
//  one that arrives wrong, because only the second is visible.
//
//  Implementations: services/Pipeline/Normalization/*
//

import Foundation

nonisolated protocol DocumentNormalizer: Sendable {
    /// Cheap, total, and side-effect free — the pipeline asks every normalizer this
    /// before handing over a document.
    func canHandle(_ document: CapturedDocument) -> Bool

    /// One document may yield zero transactions (a marketing email, a statement
    /// header page) or many (a statement with 40 lines).
    func normalize(_ document: CapturedDocument) throws -> [NormalizedTransaction]
}

nonisolated enum NormalizationError: Error, Sendable {
    case unsupportedDocument(CapturedDocument.ID)
    case missingAmount(CapturedDocument.ID)
    case missingDate(CapturedDocument.ID)
    case unreadableFormat(CapturedDocument.ID, detail: String)
}
