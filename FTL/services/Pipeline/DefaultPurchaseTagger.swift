//
//  DefaultPurchaseTagger.swift
//  FTL — services/Pipeline · Stage 4.5
//
//  Memory first, model second — and the ordering is the whole design, not an
//  optimisation.
//
//  A merchant you have settled before needs no model: you already answered, and
//  repeating your own answer back is both free and more accurate than anything a
//  small model can say about a shop it has never heard of. The model exists for
//  the merchant with no history, and it is asked only then. As the ledger fills,
//  the model's share of the work shrinks — which is the same property that makes
//  the merchant dictionary worth having (see `Merchant`).
//
//  What it deliberately does NOT tag:
//
//  · A row already read as **non-spend**. A refund, an incoming payment or a
//    transfer has no bucket to go in, and asking a model to pick one for it
//    would produce a confident answer to a question nobody asked.
//  · A row a parser **could not read** — `.unparseable`, amount zero. Its
//    merchant is a subject line. Suggesting a bucket from that is guessing on
//    top of a known failure.
//  · A row a **person has settled**. `provenance == .manual` means someone
//    already chose, and a suggestion arriving on top of that is the app
//    overwriting a decision — the one thing this must never do.
//
//  A row carrying a category from an earlier SUGGESTION is fair game, though,
//  and `refresh` replaces it whenever memory now has something to say. A stored
//  model guess is not a decision; yours is.
//

import Foundation

nonisolated struct DefaultPurchaseTagger: PurchaseTagger {
    private let memory: TagMemory
    /// Nil when there is no model on this device, or when the tagger is being
    /// run deliberately without one. The deterministic half still works.
    private let proposer: (any TagProposer)?
    /// Where the buckets come from. The sheet is canonical (Stage 0.5): the app
    /// adapts to the categories a person set up, never the other way round.
    private let ledger: any CategorySource

    /// The call budget, per pass.
    ///
    /// A sync of forty unknown merchants would otherwise be forty sequential
    /// 3.8s calls — two and a half minutes of an unbounded loop, which is the
    /// failure the feasibility run already produced once at 30 calls. Rows past
    /// the budget simply arrive untagged; that is the status quo, not a loss.
    private let maxModelCalls: Int

    init(
        memory: TagMemory,
        proposer: (any TagProposer)? = nil,
        ledger: any CategorySource,
        maxModelCalls: Int = 8
    ) {
        self.memory = memory
        self.proposer = proposer
        self.ledger = ledger
        self.maxModelCalls = maxModelCalls
    }

    func tag(_ entries: [ProvisionalEntry]) async -> [ProvisionalEntry] {
        let taggable = entries.indices.filter { Self.isTaggable(entries[$0]) }
        guard !taggable.isEmpty else { return entries }

        // One read for the batch. `categories()` is a Sheets call and is not
        // cached the way `all()` is, so per-row would be one network round trip
        // per captured email.
        guard let categories = try? await ledger.categories(), !categories.isEmpty else {
            // No vocabulary means no suggestion. Not an error: a fresh install
            // with no buckets set up yet has nothing to tag into, and inventing
            // a taxonomy for the user is exactly what Invariant 8 forbids.
            return entries
        }

        let contexts = taggable.map { TagContext(entry: entries[$0]) }
        let known = (try? await memory.history(for: contexts.map(\.merchant))) ?? [:]
        let valid = Set(categories.map(\.id))

        var tagged = entries
        var modelCalls = 0
        /// Merchants the model has already answered for in THIS batch. The
        /// outer optional is "did we ask"; the inner is "did it say anything".
        var asked: [MerchantID: CategoryID?] = [:]

        for (context, index) in zip(contexts, taggable) {
            var suggestion = Self.remembered(context.merchant, in: known, valid: valid)
            if let mem = suggestion,
               case .memory(let agreed, let total) = mem.basis,
               let catName = categories.first(where: { $0.id == mem.categoryID })?.name {
                PipelineDebugStub.recordTaggerDecision(
                    merchant: context.merchant,
                    amount: context.amount,
                    categoryName: catName,
                    source: .memory(agreed: agreed, total: total)
                )
            }

            // The model is asked ONLY for a merchant you have no opinion about,
            // and only within the call budget.
            //
            // "No suggestion" and "nothing known" are different states, and
            // conflating them is what made the most-used merchant the most
            // expensive one — see `MerchantTagHistory.hasOpinion`.
            if suggestion == nil {
                if !Self.worthAsking(context.merchant, in: known) {
                    PipelineDebugStub.recordTaggerSkipped(
                        merchant: context.merchant,
                        reason: "merchant already settled or has conflicted opinion"
                    )
                } else if modelCalls >= maxModelCalls {
                    PipelineDebugStub.recordTaggerSkipped(
                        merchant: context.merchant,
                        reason: "model call budget reached (\(maxModelCalls))"
                    )
                } else if let proposer {
                    // Once per MERCHANT, not once per row.
                    //
                    // The budget counts model calls, and asking per row spends
                    // it on rows rather than on questions: a sync of 45 rows
                    // across 20 merchants used all 8 calls on the first 8 rows
                    // and left later rows from merchants it had ALREADY
                    // answered untagged. Measured on a real device run —
                    // `APOTEK SEHAT JAYA` appeared twice, the first row got
                    // `Subscriptions` and the second got nothing.
                    //
                    // Memory cannot cover this: it only fills from approvals,
                    // and `minimumDecisions` is 2, so a merchant seen twice in
                    // one batch never benefits from its own first row. Caching
                    // the answer for the batch is what makes the budget buy
                    // merchants instead of rows.
                    if let cached = asked[context.merchant] {
                        suggestion = cached.map { TagSuggestion(categoryID: $0, basis: .model) }
                    } else {
                        modelCalls += 1
                        let proposed = await proposer.propose(for: context, among: categories)
                        asked[context.merchant] = .some(proposed)
                        suggestion = proposed.map { TagSuggestion(categoryID: $0, basis: .model) }
                    }
                }
            }

            guard let suggestion else { continue }
            Self.apply(suggestion, to: &tagged[index])
        }
        return tagged
    }

    /// The cheap half, re-run on every read. No model, no network — the
    /// categories arrive from the caller, which has just read them anyway.
    func refresh(
        _ entries: [ProvisionalEntry],
        among categories: [SpendCategory]
    ) async -> [ProvisionalEntry] {
        let candidates = entries.filter(Self.isRefreshable)
        guard !candidates.isEmpty, !categories.isEmpty else { return [] }

        let contexts = candidates.map(TagContext.init(entry:))
        let known = (try? await memory.history(for: contexts.map(\.merchant))) ?? [:]
        let valid = Set(categories.map(\.id))

        var changed: [ProvisionalEntry] = []
        for (context, entry) in zip(contexts, candidates) {
            guard let suggestion = Self.remembered(context.merchant, in: known, valid: valid) else { continue }
            // Nothing to write when the row already says this. Without the
            // check, opening the queue would rewrite every remembered row every
            // time — a store write per row per open, to change nothing.
            guard entry.resolution.suggestedTag != suggestion else { continue }

            var updated = entry
            Self.apply(suggestion, to: &updated)
            changed.append(updated)
        }
        return changed
    }

    // MARK: - The one suggestion rule, shared by both paths

    /// What memory says about this merchant, or nil.
    ///
    /// A settled outcome of nil means you consistently mark this merchant as
    /// NOT a spend, and that is deliberately not turned into a suggestion —
    /// see `TagSuggestion.categoryID`.
    private static func remembered(
        _ merchant: MerchantID,
        in known: [MerchantID: MerchantTagHistory],
        valid: Set<CategoryID>
    ) -> TagSuggestion? {
        guard let settled = known[merchant]?.settled(),
              let category = settled.categoryID,
              // A bucket you have since deleted from the sheet is not a
              // suggestion — it is a row that would land nowhere. The row then
              // arrives untagged and no model call is spent on it, because you
              // DO have an opinion about this merchant; it just points at a
              // bucket you removed, and a model that has never seen your budget
              // cannot recover what you meant by it.
              valid.contains(category)
        else { return nil }
        return TagSuggestion(
            categoryID: category,
            basis: .memory(agreed: settled.agreed, of: settled.of)
        )
    }

    /// A merchant the model might be able to help with: one you have not
    /// settled often enough to have an opinion about.
    ///
    /// Two histories produce no suggestion and mean opposite things:
    ///
    /// · **never seen** — the model is the only thing that can say anything,
    ///   and this is what it is for;
    /// · **seen and unsettled** — 22 decisions split across two buckets, or
    ///   repeatedly marked not-a-spend. Your own history is the most
    ///   informative thing in the system here and it does not point one way.
    ///   A model that has never seen your budget will not resolve that; it will
    ///   just spend the call budget guessing, every sync, forever.
    private static func worthAsking(
        _ merchant: MerchantID,
        in known: [MerchantID: MerchantTagHistory]
    ) -> Bool {
        guard let history = known[merchant] else { return true }
        return !history.hasOpinion
    }

    private static func apply(_ suggestion: TagSuggestion, to entry: inout ProvisionalEntry) {
        entry.resolution.suggestedTag = suggestion
        // Pre-tagged, not decided. `status` is still `.pending` and
        // `provenance` still names the parser that read the email — the human
        // gate is unchanged, and Invariant 1 with it.
        entry.resolution.categoryID = suggestion.categoryID
    }

    // MARK: - Which rows either path may touch

    /// See the file header. Every exclusion here is a case where a suggestion
    /// would be an answer to a question that was not asked.
    static func isTaggable(_ entry: ProvisionalEntry) -> Bool {
        entry.resolution.kind == .spend
            && entry.resolution.categoryID == nil
            && entry.transaction.amount.minorUnits > 0
            && !entry.flags.contains { $0.reason == .unparseable }
    }

    /// Looser than `isTaggable` in exactly one way, and stricter in another.
    ///
    /// LOOSER: a row that already carries a category is still refreshable, so
    /// long as that category came from a suggestion. A stored model guess is
    /// replaced the moment memory has something to say — memory is grounded in
    /// a decision you actually made and the guess is not, and leaving the guess
    /// in place would mean the row you settled last week never improved the one
    /// beside it.
    ///
    /// STRICTER: a row whose provenance is `.manual` is untouchable. That is a
    /// bucket a person chose, and replacing it with a suggestion would be the
    /// app overwriting a decision — the one thing this tool may never do.
    static func isRefreshable(_ entry: ProvisionalEntry) -> Bool {
        guard entry.status == .pending else { return false }
        if case .manual = entry.provenance { return false }
        guard entry.resolution.kind == .spend,
              entry.transaction.amount.minorUnits > 0,
              !entry.flags.contains(where: { $0.reason == .unparseable })
        else { return false }
        // Either nothing has tagged it, or only a suggestion has.
        return entry.resolution.categoryID == nil || entry.resolution.suggestedTag != nil
    }
}
