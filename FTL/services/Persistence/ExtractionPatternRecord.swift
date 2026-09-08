//
//  ExtractionPatternRecord.swift
//  FTL — services/Persistence
//
//  A promoted pattern, kept. This is where "the app learns to read your
//  receipts" stops being a slogan: without it, every synthesis run starts from
//  nothing and the loop is a demo.
//
//  Versions are kept, not overwritten. The whole argument for patterns over
//  opinions is that the output is an artifact you can read, diff, version and
//  revoke — replacing v1 in place would throw away three of those four.
//

import Foundation
import SwiftData

@Model
final class ExtractionPatternRecord {
    /// `senderDomain:version` — the pattern's own identity.
    @Attribute(.unique) var id: String

    // Queried: the rail asks for the best pattern per sender, and provenance
    // has to be readable without decoding the blob.
    var senderDomain: String
    /// Which of the sender's layouts. Defaulted, so patterns stored before
    /// layouts existed migrate as the sender's single unnamed template.
    var template: String = ""
    var version: Int
    var accuracy: Double
    var verifiedAgainst: Int
    var promotedAt: Date
    /// Set when a person or a later run retires it. Revoked patterns are kept —
    /// knowing a pattern was tried and withdrawn is worth more than a clean table.
    var revokedAt: Date?

    var payload: Data

    init(pattern: ExtractionPattern, promotedAt: Date = .now) throws {
        self.id = pattern.id
        self.senderDomain = pattern.senderDomain
        self.template = pattern.template
        self.version = pattern.version
        self.accuracy = pattern.accuracy
        self.verifiedAgainst = pattern.verifiedAgainst
        self.promotedAt = promotedAt
        self.revokedAt = nil
        self.payload = try JSONEncoder().encode(pattern)
    }

    func pattern() throws -> ExtractionPattern {
        try JSONDecoder().decode(ExtractionPattern.self, from: payload)
    }
}
