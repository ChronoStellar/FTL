//
//  PurchaseTagger.swift
//  FTL — model/Contracts · Stage 4.5 · ★ THE SECOND TOOL
//
//  Given a transaction, which bucket does it go in.
//
//  It is a genuinely different problem from pattern synthesis and must not be
//  built by copying it. Synthesis has an ORACLE: run the proposed rule over mail
//  the model never saw and score it, deterministically, before it can affect
//  anything. That is what lets the first tool run unattended.
//
//  Tagging has no oracle and cannot have one. Whether `KAYABOYS1 SURABAYA` is
//  food or entertainment is not in the email — it is a decision about your own
//  budget — so there is nothing for code to check the answer against. The only
//  honest source of truth is what you approved last time.
//
//  So the shape is inverted. Not propose → verify → promote, but:
//
//      PROPOSE     the tool suggests a bucket; the row lands in the queue
//        ↓         pre-tagged, and clearly marked as a suggestion
//      YOU DECIDE  you approve, or you retag — either way you settled it
//        ↓
//      ACCRUE      the choice is recorded against the normalized merchant, and
//                  the hit rate is what the third rung is earned against
//
//  Which makes the approval queue the tagger's training signal rather than
//  overhead around the loop. That is also why the queue has to stay pleasant to
//  use: it is the other half of this.
//
//  Two hard rules, both from the roadmap and both load-bearing:
//
//  · **Deterministic first, model second.** A merchant you have tagged three
//    times the same way needs no model at all — that is a lookup, and it is the
//    wide path. The model is for the merchant you have never seen, and it is
//    asked only then.
//  · **`merchantRaw` is not the key.** `bigA bakehouse SURABAYA` and
//    `BIGA BAKEHOUSE SURABAYA` are one shop. Invariant 3 keeps the raw string
//    forever; `MerchantID(normalizing:)` derives what accrues.
//
//  Invariant 1 is untouched: a suggestion writes to `ProvisionalEntry`, never to
//  the ledger. Invariant 2 is untouched: it selects a bucket, it never computes.
//
//  Implementations: services/Pipeline/DefaultPurchaseTagger (the layering),
//  services/Agent/FoundationModelTagger (the model half).
//

import Foundation

//  ## Why there are two entry points, and not one
//
//  The first version tagged once, at capture, and that was wrong in a way that
//  only shows up in use. A sync brings in five rows; the tagger looks up what it
//  knows BEFORE you have settled any of them, so the first row gets a model
//  guess and the other four get the same nothing — and then you settle the
//  first, and the four beside it never find out. The suggestion was buried at
//  the start of the pipeline and frozen there, so everything you taught it
//  during a queue session went unused until the next fetch. A row already
//  waiting in the queue from last week never got a suggestion at all.
//
//  The two halves have completely different costs, so they run at different
//  times:
//
//  · `tag` runs ONCE, at capture. It is allowed to call the model, which costs
//    3.8s p95, so it must not be on a render path and must be bounded.
//  · `refresh` runs EVERY TIME the queue is read. It is a memory lookup and
//    nothing else — no model, no network — so it is free to re-run, and it is
//    what makes the second row of a merchant benefit from the first.
//
//  What `tag` produces is therefore a cache of the expensive half, and
//  `refresh` is the cheap half re-derived from the current truth. Memory beats
//  a stored model guess whenever both exist, because memory is the only one of
//  the two that is grounded in a decision you actually made.

nonisolated protocol PurchaseTagger: Sendable {
    /// Attaches a suggestion to each entry it has something to say about, and
    /// returns the rest unchanged.
    ///
    /// A BATCH, not one row at a time, and that is a design decision rather
    /// than a convenience:
    ///
    /// · the bucket list belongs to the sheet, so it is read ONCE per pass
    ///   instead of once per row over a rate-limited network API;
    /// · the model half costs a measured 3.8s p95 per call, so how many rows
    ///   reach it is a decision that has to be made with the whole batch in
    ///   view — see `maxModelCalls`. One runaway loop in the feasibility run
    ///   hit 30 calls; every loop in this app is bounded.
    ///
    /// Never throws. A tagger that fails is a row with no suggestion on it,
    /// which is exactly what every row looked like before this existed — and
    /// stranding a captured purchase because a bucket could not be guessed
    /// would be the pipeline losing spending over a cosmetic feature.
    func tag(_ entries: [ProvisionalEntry]) async -> [ProvisionalEntry]

    /// Re-derives the memory half against what you have decided by NOW, and
    /// returns only the entries whose suggestion actually changed.
    ///
    /// Called every time the queue is read, which is the point: approving one
    /// `HOKKY SUPERMARKET` row has to be visible on the next one immediately,
    /// not after the next fetch. Cheap enough to run on every load —
    /// deterministic, no model, and the categories are passed in because the
    /// caller has already read them.
    ///
    /// Returns the CHANGED subset rather than everything, so the caller can
    /// persist a handful of rows instead of rewriting the queue on every open.
    ///
    /// It must never touch a row the person has already settled: a suggestion
    /// arriving on top of someone's own retag is the app overwriting a decision,
    /// which is the one thing the second tool is not allowed to do.
    func refresh(
        _ entries: [ProvisionalEntry],
        among categories: [SpendCategory]
    ) async -> [ProvisionalEntry]
}

/// The model half, alone behind its own seam so the deterministic half can be
/// exercised with no device, no model and no network.
nonisolated protocol TagProposer: Sendable {
    /// Nil when it cannot say — gated, unavailable, or it named a bucket that
    /// isn't one of `categories`.
    ///
    /// A named bucket that doesn't exist is a REFUSAL, not free text to be
    /// accepted. The same argument `TagStore` already makes: a category outside
    /// the canonical list is a detectable event, and the detectable version is
    /// worth more than a plausible-looking string.
    func propose(
        for context: TagContext,
        among categories: [SpendCategory]
    ) async -> CategoryID?
}

/// What the tagger is given. Assembled deterministically; the tool does not
/// fetch, and it never sees the email body — a bucket is a decision about a
/// purchase, not a re-reading of the receipt the parser already read.
nonisolated struct TagContext: Sendable, Hashable {
    let merchantRaw: String
    /// The accrual key. See `MerchantID(normalizing:)`.
    let merchant: MerchantID
    let amount: Money
    let date: Date
    /// Which parser produced the row — a hint a person would use too, since the
    /// sender says a great deal about what kind of purchase this is.
    let ruleID: String?

    init(entry: ProvisionalEntry) {
        self.merchantRaw = entry.transaction.merchantRaw
        self.merchant = MerchantID(normalizing: entry.transaction.merchantRaw)
        self.amount = entry.transaction.amount
        self.date = entry.transaction.date
        if case .rule(let id) = entry.provenance { self.ruleID = id.rawValue } else { self.ruleID = nil }
    }
}
