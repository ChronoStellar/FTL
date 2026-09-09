//
//  PresetPatterns.swift
//  FTL — services/Pipeline · Stage 4.5
//
//  Patterns that ship with the app.
//
//  A preset is not a different kind of thing from a learned pattern. It is the
//  same `ExtractionPattern`, run by the same `PatternDrivenParser`, carrying the
//  same provenance fields — the only difference is that a person wrote it and
//  `author` says so.
//
//  ## Why this exists at all
//
//  It is what lets `BluReceiptParser` leave the runtime path.
//
//  The rail took `handWritten + learned` and used the FIRST parser that claimed
//  an email, so a learned pattern never read a blu email — the loop was shut out
//  of the one sender it could be verified against, and nothing ever accrued.
//  Audited 2026-09-09, the swap turns out to cost nothing: expressed with its
//  own terminator list and its own `Total`/`Amount` fallback, the parser is
//  EXACTLY reproducible as a pattern — 116/116 over the real corpus, zero
//  disagreement on amount, merchant, kind or subtype.
//
//  So the reference parser keeps the job only it can do — being the oracle
//  `PatternVerifier` scores proposals against — and stops doing the job that was
//  blocking the loop.
//
//  ## The provenance is a measurement, not a courtesy
//
//  `verifiedAgainst: 116` and `accuracy: 1.0` on the blu preset are the numbers
//  from that audit, against `ParserOracle(BluReceiptParser())`. They are the
//  reason its rows do not carry `unverifiedPattern`: the claim has been checked,
//  by the same verifier everything else is checked by. A preset added without
//  running that check must ship `verifiedAgainst: 0` and let its rows be
//  flagged, like any other unverified pattern.
//

import Foundation

nonisolated enum PresetPatterns {
    /// Decoded once. Failure is silent and empty on purpose: a missing or
    /// malformed preset file must not stop the rail — it degrades to "this
    /// sender is unknown", which is a state the loop already knows how to be in.
    static func load(bundle: Bundle = .main) -> [ExtractionPattern] {
        guard let url = bundle.url(forResource: "preset-patterns", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(File.self, from: data))?.patterns ?? []
    }

    private struct File: Decodable {
        let patterns: [ExtractionPattern]
    }
}
