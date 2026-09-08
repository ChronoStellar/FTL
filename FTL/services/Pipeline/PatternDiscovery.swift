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
//        ↓  its figures actually MOVE            amountVariance ⭑
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

    private let learner: any PatternLearner
    private let policy: PatternSynthesisPolicy
    /// Bounded, always. Each sender costs up to `maxAttempts` model calls per
    /// layout, and an unattended run that walks a whole mailbox is how a
    /// background task becomes a battery complaint.
    private let maxSendersPerRun: Int

    init(
        learner: any PatternLearner,
        policy: PatternSynthesisPolicy = .default,
        maxSendersPerRun: Int = 3
    ) {
        self.learner = learner
        self.policy = policy
        self.maxSendersPerRun = maxSendersPerRun
    }

    /// Who to learn next, best first. No model call, safe to run on every sync.
    ///
    /// `isRead` is the app's current reach — pass the same parser list the rail
    /// uses. A sender already covered still has unread mail (Grab sends three
    /// promos for every receipt) and that is not a reason to look at it again,
    /// so its remaining layouts have to fail the variance bar on their own
    /// merits, which they do.
    func candidates(
        in emails: [CapturedEmail],
        isRead: (CapturedEmail) -> Bool
    ) -> [Candidate] {
        let unread = emails.filter { $0.hasCurrencyMarker && !isRead($0) }

        let evidenceFloor = policy.maxExamples + policy.minimumProvisionalEvidence
        let bySender: [String: [CapturedEmail]] = Dictionary(grouping: unread, by: \.senderDomain)

        var found: [Candidate] = []
        for (domain, mail) in bySender {
            let layouts = SenderTriage.templates(from: mail).filter { layout in
                layout.amountVariance >= policy.minimumAmountVariance
                    && layout.emails.count >= evidenceFloor
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
        isRead: (CapturedEmail) -> Bool
    ) async -> [Finding] {
        var findings: [Finding] = []
        for candidate in candidates(in: emails, isRead: isRead).prefix(maxSendersPerRun) {
            let outcomes = await learner.learn(
                senderDomain: candidate.senderDomain,
                from: candidate.transactionalLayouts.flatMap(\.emails),
                policy: policy
            )
            findings.append(Finding(senderDomain: candidate.senderDomain, outcomes: outcomes))
        }
        return findings
    }
}
