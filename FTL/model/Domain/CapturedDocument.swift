//
//  CapturedDocument.swift
//  FTL — model/Domain
//
//  What a rail hands back: raw, unparsed, unjudged. One document may yield zero
//  transactions (marketing email) or many (a statement page).
//

import Foundation

nonisolated struct CapturedDocument: Sendable, Hashable, Identifiable, Codable {
    let id: UUID
    let source: CaptureSource

    /// Stable identifier from the rail itself — Gmail message id, a statement row
    /// hash, a PHAsset id. The dedup key for "have I already captured this?", and
    /// the reason re-running a capture is safe.
    let externalID: String

    let capturedAt: Date
    let payload: Payload

    nonisolated enum Payload: Sendable, Hashable, Codable {
        case email(EmailPayload)
        case statementRow(StatementRowPayload)
        case image(ImagePayload)
        case manual(ManualPayload)
    }
}

nonisolated struct EmailPayload: Sendable, Hashable, Codable {
    let messageID: String
    let threadID: String?
    let from: String
    let subject: String
    let receivedAt: Date
    /// Plain-text body, already stripped of HTML by the rail.
    let body: String
}

nonisolated struct StatementRowPayload: Sendable, Hashable, Codable {
    let institution: String
    let postedAt: Date
    /// The descriptor exactly as the bank wrote it — bank prefixes and all.
    let descriptor: String
    let amountMinorUnits: Int
    let currency: CurrencyCode
    /// Statements express direction; the normalizer maps it onto `Money`'s sign.
    let isDebit: Bool
}

nonisolated struct ImagePayload: Sendable, Hashable, Codable {
    /// Local asset identifier. Images never leave the device.
    let assetIdentifier: String
    let scannedAt: Date
}

nonisolated struct ManualPayload: Sendable, Hashable, Codable {
    let date: Date
    let amountMinorUnits: Int
    let currency: CurrencyCode
    let merchant: String
    let categoryID: CategoryID?
    let note: String?
}
