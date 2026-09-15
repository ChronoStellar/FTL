//
//  PatternDiscovery.swift
//  FTL — services/Pipeline · Stage 4
//
//  Points the loop at senders nobody has named.
//
//  Until now a synthesis run needed a person to say "learn blu" or "learn
//  Grab", which is hand-conditioning by another route: the parser stopped being
//  hand-written, but the choice of what to learn stayed hand-made. This is the
//  piece that closes that — the app finds its own candidates from mail it
//  cannot currently read.
//
//  Everything here is deterministic. No model call is made to decide where to
//  spend model calls, because a loop that asks the model what to work on next
//  is a loop with no bound.
//
//  The selection funnel, in order of cost:
//
//      all mail
//        ↓  carries Rp/IDR                       regex, free
//      money mail
//        ↓  no existing parser claims it         the coverage question
//      unread money mail
//        ↓  groups into a repeating layout       SenderTriage
//      candidate layouts
//        ↓  too thin to judge yet?               nearMisses → one top-up fetch ⭑⭑
//        ↓  its figures actually MOVE            distinctAmounts ⭑
//      worth a model call
//
//  ⭑ is the step that makes unattended running safe. Ranked by volume alone,
//  the top two candidates in the real corpus are Apple's "your iCloud storage
//  is full" and Traveloka's discount campaign — both templated, both full of
//  Rp figures, neither a transaction. A pattern learned from either would read
//  a number out of every email and score 1.0 coverage, which is precisely the
//  failure coverage cannot detect. Asking whether the numbers change costs one
//  regex pass and separates them completely: receipts 0.88–1.00, brochures
//  0.04–0.12.
//
//  ⭑⭑ added 2026-09-11. A low-*frequency* sender — real history, most of it
//  outside whatever window this particular sweep used — looks identical to a
//  sender that genuinely doesn't have enough mail, UNLESS something looks
//  past the window before giving up. `nearMisses` finds a sender too thin to
//  judge (not one already judged and rejected), and `run(fetching:...)` gives
//  it one bounded, unrestricted `from:(domain)` fetch before deciding. This
//  does not touch `minimumDistinctAmounts` or `minimumProvisionalEvidence` —
//  lowering either would trade statistical soundness for coverage, the exact
//  trade the constant-merchant defect above already burned once. It gives a
//  thin sender a fair look with its REAL history instead of a smaller bar.
//

import Foundation

nonisolated struct PatternDiscovery: Sendable {

    /// A sender worth spending the budget on, and why.
    nonisolated struct Candidate: Sendable {
        let senderDomain: String
        /// Emails from this sender that carry money and nothing can read.
        let unreadMoneyMail: Int
        /// Its layouts that clear the variance bar, largest first.
        let transactionalLayouts: [SenderTriage.Template]

        var learnableEmails: Int {
            transactionalLayouts.reduce(0) { $0 + $1.emails.count }
        }
    }

    nonisolated struct Finding: Sendable {
        let senderDomain: String
        let outcomes: [TemplateOutcome]
    }

    /// A sender with real signal (currency-marker mail) that `candidates`
    /// didn't select — either there wasn't enough of it yet in THIS sweep to
    /// judge fairly, or it already looked transactional but hadn't
    /// accumulated enough volume to clear the evidence floor. Deliberately
    /// NOT a sender the sweep already saw enough of to fail the variance bar
    /// on its own merits — that is a real answer (a brochure), not a reason
    /// to spend a second fetch confirming it again. See `nearMisses` and
    /// `run(fetching:isRead:knownSenders:)`.
    nonisolated struct NearMiss: Sendable {
        let senderDomain: String
        let unreadMoneyMail: Int
    }

    private let learner: any PatternLearner
    private let policy: PatternSynthesisPolicy
    /// Bounded, always. Each sender costs up to `maxAttempts` model calls per
    /// layout, and an unattended run that walks a whole mailbox is how a
    /// background task becomes a battery complaint.
    private let maxSendersPerRun: Int
    /// Bounded separately from `maxSendersPerRun` — a near-miss top-up
    /// (`nearMisses`, `deepenFetchLimit`) spends a live Gmail fetch, not a
    /// model call, on a sender discovery has not yet decided is even real.
    /// See `run(fetching:isRead:knownSenders:)`.
    private let maxNearMissesPerRun: Int

    init(
        learner: any PatternLearner,
        policy: PatternSynthesisPolicy = .default,
        maxSendersPerRun: Int = 3,
        maxNearMissesPerRun: Int = 3
    ) {
        self.learner = learner
        self.policy = policy
        self.maxSendersPerRun = maxSendersPerRun
        self.maxNearMissesPerRun = maxNearMissesPerRun
    }

    /// Mail to look for candidates in — and the reason this exists at all.
    ///
    /// `GmailRail` asks Gmail for `from:(the domains it already parses)`, which
    /// is right for capture: downloading a mailbox to discard most of it is
    /// waste. But it means an unknown sender's mail never arrives, so selecting
    /// candidates from what the rail fetched can only ever return senders the
    /// app can already read. Discovery would find nothing, forever, by
    /// construction — not because no sender qualifies but because none can
    /// reach it.
    ///
    /// The recorded corpus hid this completely: `EmailCorpus` hands over all
    /// 1,000 emails regardless of sender, so discovery looked like it worked.
    /// It only surfaced once a fixture asked what the RAIL would have fetched.
    ///
    /// So discovery fetches for itself, unscoped by sender. That is a real
    /// cost — it is the whole window, not a filtered slice — paid down three
    /// ways: it runs rarely rather than every sync, `limit` caps it hard, and
    /// the currency filter runs locally so nothing beyond the cap is kept.
    ///
    /// Filtering client-side rather than searching Gmail for `Rp` is
    /// deliberate: a server-side term match depends on how Gmail tokenises
    /// `Rp18.000,00`, and a receipt missed there is invisible — it looks
    /// exactly like a sender that has no receipts.
    static let discoveryQuery = "newer_than:180d"
    /// One bounded sweep. Enough for a sender to clear the evidence floor
    /// several times over, small enough to stay a single background fetch.
    static let discoveryFetchLimit = 400

    /// Below this there is nothing to even group into a layout — one email is
    /// one data point, and a live top-up fetch is too expensive to spend
    /// confirming it. See `nearMisses`.
    static let minimumSignalForDeepening = 2
    /// One bounded top-up fetch per near-miss sender, unrestricted by date —
    /// the whole point is seeing past whatever the ambient sweep's window
    /// happened to catch, the same way `discoveryQuery`'s 180 days can still
    /// be narrower than a low-frequency sender's real history. Smaller than
    /// `discoveryFetchLimit`: this tops up ONE sender, it does not scan the
    /// mailbox.
    static let deepenFetchLimit = 200

    /// Money mail from anywhere, including senders nothing can read yet.
    func candidateMail(
        from source: any CapturedEmailSource,
        limit: Int = discoveryFetchLimit
    ) async throws -> [CapturedEmail] {
        try await source
            .fetchCaptured(query: Self.discoveryQuery, limit: limit)
            .filter(\.hasCurrencyMarker)
    }

    /// Domains worth a second look before discovery writes them off.
    ///
    /// `minimumDistinctAmounts` doubles as the fairness floor here: a layout
    /// needs at least that many raw emails before `distinctAmounts` means
    /// anything at all — you cannot have 5 distinct amounts from 3 emails —
    /// so a sender under that has not had a fair chance to prove itself
    /// either way. That is exactly the shape a low-*frequency* sender
    /// produces on a bounded ambient window: real history, most of it
    /// outside this particular sweep. Measured directly —
    /// `TemporalHoldoutRunner`'s 2026-09-11 run over a 2-month live slice
    /// found Grab clearing discovery zero times, where the full frozen
    /// export's longer span found it twice (`grab.com/compliments`,
    /// `grab.com/diterbitkan`). A sender the sweep already saw ENOUGH of
    /// (`≥ minimumDistinctAmounts` raw emails) and which still reads as a
    /// brochure is a real answer, not a near miss — excluded, so a rejected
    /// promo sender (Apple's storage nag, Traveloka's discount campaign) is
    /// not re-fetched forever.
    func nearMisses(
        in emails: [CapturedEmail],
        isRead: (CapturedEmail) -> Bool,
        excluding alreadyCandidates: Set<String>
    ) -> [NearMiss] {
        let unread = emails.filter { $0.hasCurrencyMarker && !isRead($0) }
        let bySender = Dictionary(grouping: unread, by: \.senderDomain)

        return bySender.compactMap { domain, mail -> NearMiss? in
            guard !alreadyCandidates.contains(domain),
                  mail.count >= Self.minimumSignalForDeepening
            else { return nil }

            let hadAFairShot = mail.count >= policy.minimumDistinctAmounts
            let readsLikeABrochure = SenderTriage.templates(from: mail)
                .allSatisfy { $0.distinctAmounts < policy.minimumDistinctAmounts }
            if hadAFairShot && readsLikeABrochure { return nil }

            return NearMiss(senderDomain: domain, unreadMoneyMail: mail.count)
        }
        .sorted { $0.unreadMoneyMail > $1.unreadMoneyMail }
    }

    /// Fetch, top up any near miss, then select. The two-argument form
    /// (`run(over:...)`) stays a plain pass over mail already in hand — a
    /// frozen corpus holds everything it will ever hold, so there is nothing
    /// to top up, and `TemporalHoldoutRunner`'s own train/test fetches go
    /// through that form deliberately, not this one.
    func run(
        fetching source: any CapturedEmailSource,
        isRead: (CapturedEmail) -> Bool,
        knownSenders: Set<String> = []
    ) async throws -> [Finding] {
        var pool = try await candidateMail(from: source)

        // Only a sender the ambient sweep couldn't already decide on gets a
        // top-up — one that already qualifies doesn't need more evidence,
        // and re-fetching it would just spend a call confirming a yes.
        let alreadyCandidates = Set(
            candidates(in: pool, isRead: isRead, knownSenders: knownSenders).map(\.senderDomain)
        )
        let targets = nearMisses(in: pool, isRead: isRead, excluding: alreadyCandidates)
            .prefix(maxNearMissesPerRun)

        for target in targets {
            // Best-effort: a failed top-up leaves the sender exactly as thin
            // as the ambient sweep found it — the same as never having
            // tried, not a reason to fail the whole run over one sender.
            guard let more = try? await source.fetchCaptured(
                query: "from:(\(target.senderDomain))",
                limit: Self.deepenFetchLimit
            ) else { continue }
            pool.append(contentsOf: more)
        }

        return await run(over: Self.deduplicated(pool), isRead: isRead, knownSenders: knownSenders)
    }

    /// A top-up query can return mail the ambient sweep already fetched —
    /// their windows overlap by construction. The same email counted twice
    /// would inflate every volume and distinctness check downstream, which
    /// is exactly the kind of silent double-count `possibleDuplicate` exists
    /// to catch elsewhere in this app; simplest to just not let it happen
    /// here; `id` is the Gmail message id, so it is the same identity a
    /// second fetch of the same message would carry.
    private static func deduplicated(_ emails: [CapturedEmail]) -> [CapturedEmail] {
        var seen = Set<String>()
        return emails.filter { seen.insert($0.id).inserted }
    }

    /// Who to learn next, best first. No model call, safe to run on every sync.
    ///
    /// `isRead` is the app's current reach — pass the same parser list the rail
    /// uses. A sender already covered still has unread mail (Grab sends three
    /// promos for every receipt) and that is not a reason to look at it again,
    /// so its remaining layouts have to fail the variance bar on their own
    /// merits, which they do.
    ///
    /// `knownSenders` — domains with at least one ALREADY ACTIVE pattern —
    /// get `minimumProvisionalEvidenceForKnownSender` instead of the normal
    /// floor: the volume gate exists to answer "is this sender real", and an
    /// active pattern already answered it, so a second, rarer layout from
    /// the same sender doesn't have to re-clear the full bar from nothing.
    /// See the policy field's doc comment.
    func candidates(
        in emails: [CapturedEmail],
        isRead: (CapturedEmail) -> Bool,
        knownSenders: Set<String> = []
    ) -> [Candidate] {
        let unread = emails.filter { $0.hasCurrencyMarker && !isRead($0) }

        let evidenceFloor = policy.maxExamples + policy.minimumProvisionalEvidence
        let relaxedEvidenceFloor = policy.maxExamples + policy.minimumProvisionalEvidenceForKnownSender
        let bySender: [String: [CapturedEmail]] = Dictionary(grouping: unread, by: \.senderDomain)

        var found: [Candidate] = []
        for (domain, mail) in bySender {
            let floor = knownSenders.contains(domain) ? relaxedEvidenceFloor : evidenceFloor
            let layouts = SenderTriage.templates(from: mail).filter { layout in
                layout.distinctAmounts >= policy.minimumDistinctAmounts
                    && layout.emails.count >= floor
            }
            guard !layouts.isEmpty else { continue }
            found.append(
                Candidate(
                    senderDomain: domain,
                    unreadMoneyMail: mail.count,
                    transactionalLayouts: layouts
                )
            )
        }

        // Most learnable mail first: the sender whose receipts are most often
        // missed is the one whose pattern is worth the most.
        return found.sorted { lhs, rhs in
            if lhs.learnableEmails != rhs.learnableEmails {
                return lhs.learnableEmails > rhs.learnableEmails
            }
            return lhs.unreadMoneyMail > rhs.unreadMoneyMail
        }
    }

    /// Runs the loop over the top candidates and reports what came back.
    ///
    /// Persisting the results is deliberately NOT done here. Whether a
    /// provisional pattern goes live is a trust decision, and trust decisions
    /// belong to the caller that knows the context — Invariant 10.
    func run(
        over emails: [CapturedEmail],
        isRead: (CapturedEmail) -> Bool,
        knownSenders: Set<String> = []
    ) async -> [Finding] {
        var findings: [Finding] = []
        for candidate in candidates(in: emails, isRead: isRead, knownSenders: knownSenders).prefix(maxSendersPerRun) {
            // The relaxed floor is not just a SELECTION filter — the learner
            // re-applies its own `minimumProvisionalEvidence` guard per
            // template (`DefaultPatternLearner.learn`), so a candidate that
            // only cleared selection under the relaxed floor must be handed
            // the SAME relaxed policy here, or it clears one gate only to be
            // rejected by the other with the exact same number.
            var effectivePolicy = policy
            if knownSenders.contains(candidate.senderDomain) {
                effectivePolicy.minimumProvisionalEvidence = policy.minimumProvisionalEvidenceForKnownSender
            }
            let outcomes = await learner.learn(
                senderDomain: candidate.senderDomain,
                from: candidate.transactionalLayouts.flatMap(\.emails),
                policy: effectivePolicy
            )
            findings.append(Finding(senderDomain: candidate.senderDomain, outcomes: outcomes))
        }
        return findings
    }
}
