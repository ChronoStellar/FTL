//
//  SenderTriage.swift
//  FTL — services/Pipeline · Stage 4 #10
//
//  How many LAYOUTS a sender's mail comes in, and which emails share each one.
//
//  A layout is the thing a pattern can be written against: one document shape,
//  reused. Senders have several, and the count is not guessable from the
//  outside — Grab sends two receipt layouts plus a dozen campaign layouts under
//  overlapping subjects, blu sends three.
//
//  ONE SUBJECT IS NOT ONE LAYOUT. This is what broke the first Grab run, and it
//  was this file's fault, not the model's. All 21 of Grab's receipts share the
//  subject "Your Grab E-Receipt", but they are two different documents:
//
//      food (10)   TOTAL Rp 44300 … Pesanan Dari: Rasapi - Sambikerep …
//      ride (11)   Total Paid Rp9.000 … Receipt issued by the driver …
//
//  Handing the learner all 21 as one template produced a perfectly good RIDE
//  pattern scored against a holdout that was half food: 0.52 coverage, under
//  the bar, rejected. The same pattern scores 1.00 against rides alone.
//
//  AND ONE LAYOUT IS NOT ONE SUBJECT. The mirror case, found later. This file
//  used to keep only the dominant subject cluster before looking at bodies, on
//  the theory that a repeating subject is a template and marketing is written
//  fresh each time. It cost data both ways: a sender using two subjects had
//  half its mail discarded unseen, and blu's third layout — 12 real receipts —
//  never reached the loop.
//
//  Both mistakes had the same root: subject was being used as a proxy for
//  layout. So clustering reads the BODY, over all of the sender's mail, and
//  marketing is refused by `Template.amountVariance` — a brochure repeats its
//  prices, a receipt does not — rather than by guessing from the subject line.
//
//  Measured on the real export, no model, no labels, no network:
//
//      grab   11 @ 0.91 ✓   10 @ 1.00 ✓   promos 0.41, 0.30, 0.11, 0.29 ✗
//      blu    70 @ 0.86 ✓   34 @ 0.91 ✓   12 @ 0.75 ✓   fraud warnings ✗
//

import Foundation

nonisolated enum SenderTriage: Sendable {

    /// One layout from one sender: the emails that share it, and the text that
    /// tells it apart from the sender's other layouts.
    nonisolated struct Template: Sendable {
        let emails: [CapturedEmail]

        /// Words present in EVERY email of this layout and in NO email of the
        /// sender's other layouts. Becomes the pattern's `bodyContains`, which
        /// is what stops the ride pattern from claiming a food receipt.
        ///
        /// Empty for a sender with a single layout, and for the one layout that
        /// is a subset of another — those are matched by subject alone, and
        /// `GmailRail` runs more specific patterns first.
        let discriminators: [String]

        /// Readable identity, e.g. `compliments` or `diterbitkan`. Part of the
        /// pattern's id, so two layouts from one sender are two artifacts
        /// rather than one overwriting the other.
        var key: String { discriminators.joined(separator: "+") }

        /// Share of this layout's emails whose set of Rp figures is unique.
        ///
        /// The one question that separates a receipt template from a brochure,
        /// and it needs no model, no labels and no vocabulary: **a receipt's
        /// numbers move, an advertisement's do not**. Every email in a campaign
        /// quotes the same price; every receipt states a different total.
        ///
        /// This exists because "contains Rp" is not nearly enough to point the
        /// loop at a sender. Measured over the real corpus:
        ///
        ///     blu   layout 55   0.91  ┐
        ///     blu   layout 40   0.88  │ receipts
        ///     grab  ride  11    0.91  │
        ///     grab  food  10    1.00  ┘
        ///     apple       13    0.08  ┐
        ///     traveloka   17    0.06  │ brochures quoting prices
        ///     linkedin    25    0.04  │
        ///     edx         10    0.10  ┘
        ///
        /// No close call anywhere. Without it, the two senders with the most
        /// unread money mail are Apple's storage nag and Traveloka's discount
        /// campaign — and a pattern anchored on a promo reads a figure from
        /// every email and scores 1.0 coverage, which is exactly the failure
        /// `PatternVerifier.coverage` warns it cannot catch.
        let amountVariance: Double
    }

    /// The sender's layouts, largest first, each newest-first inside.
    ///
    /// Every layout, marketing included — judging them is not this type's job.
    /// `Template.amountVariance` says which are transactional and the caller's
    /// evidence floor says which are worth a model call, and those two together
    /// do the filtering that a subject pre-pass used to attempt.
    ///
    /// It used to keep only the dominant SUBJECT cluster first, on the theory
    /// that a repeating subject is a template and marketing is written fresh.
    /// That was written before the variance test existed and it loses data two
    /// ways: a sender with two subjects has half its mail discarded, and blu's
    /// third layout — 12 real receipts — never reached the loop at all.
    ///
    /// Measured over the full corpora with the pre-pass removed:
    ///
    ///     grab  11 @ 0.91 ✓   10 @ 1.00 ✓   promos 0.41, 0.30, 0.11, 0.29 ✗
    ///     blu   70 @ 0.86 ✓   34 @ 0.91 ✓   12 @ 0.75 ✓   warnings ✗
    ///
    /// Both receipt layouts kept, every promo refused, and blu's third layout
    /// recovered. Note the margin narrowed: brochures scored 0.04–0.12 when
    /// only subject-matched mail reached here, and Grab's largest promo cluster
    /// now scores 0.41 against a 0.5 bar, because campaigns quote different
    /// discounts to each other even while repeating within a campaign. Still a
    /// clear separation — 0.41 to 0.75 — but no longer a chasm, and worth
    /// re-measuring before that threshold is moved.
    static func templates(from emails: [CapturedEmail]) -> [Template] {
        let receipts = emails
        guard !receipts.isEmpty else { return [] }

        let clusters = layoutClusters(in: receipts)
        guard clusters.count > 1 else {
            return [
                Template(
                    emails: receipts,
                    discriminators: [],
                    amountVariance: amountVariance(of: receipts)
                )
            ]
        }

        return clusters.map { cluster in
            Template(
                emails: cluster,
                discriminators: discriminators(of: cluster, among: clusters),
                amountVariance: amountVariance(of: cluster)
            )
        }
    }

    /// See `Template.amountVariance`.
    ///
    /// Reads the head of each email rather than all of it: a footer can carry a
    /// fixed fee or a price list, and those are the same in every email by
    /// definition — counting them drags a real receipt's score down toward a
    /// brochure's.
    static func amountVariance(of emails: [CapturedEmail]) -> Double {
        guard !emails.isEmpty else { return 0 }
        let fingerprints = emails.map { email in
            Set(IndonesianMoney.all(in: String(email.flatText.prefix(amountScanLength))))
        }
        return Double(Set(fingerprints).count) / Double(emails.count)
    }

    private static let amountScanLength = 1500

    // MARK: - Layout clustering

    /// Groups by body shape: the set of BOILERPLATE words an email contains.
    ///
    /// "Boilerplate" is the load-bearing word. A receipt's own words — the
    /// merchant, the driver, the street — appear once in the whole corpus and
    /// would make every email its own cluster. So the vocabulary is restricted
    /// to words that recur across the sender first, and similarity is measured
    /// only over those. What survives is the template's furniture.
    private static func layoutClusters(in emails: [CapturedEmail]) -> [[CapturedEmail]] {
        var documentFrequency: [String: Int] = [:]
        var signatures: [String: Set<String>] = [:]

        for email in emails {
            let words = tokens(in: email, limit: signatureLength)
            signatures[email.id] = words
            for word in words { documentFrequency[word, default: 0] += 1 }
        }

        let floor = max(2, emails.count / 4)
        let vocabulary = Set(documentFrequency.filter { $0.value >= floor }.keys)
        for (id, words) in signatures { signatures[id] = words.intersection(vocabulary) }

        // Greedy single pass, in the caller's order. Deterministic, O(n·k), and
        // the alternative — real agglomerative clustering — buys nothing on the
        // two-to-three layouts a sender actually has.
        var clusters: [(signature: Set<String>, members: [CapturedEmail])] = []
        for email in emails {
            let signature = signatures[email.id] ?? []
            var bestIndex: Int?
            var bestScore = 0.0

            for (index, cluster) in clusters.enumerated() {
                let score = jaccard(signature, cluster.signature)
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            if let bestIndex, bestScore >= similarityThreshold {
                clusters[bestIndex].members.append(email)
                // Intersect, so the cluster's signature stays what its members
                // AGREE on rather than drifting toward whatever joined last.
                clusters[bestIndex].signature.formIntersection(signature)
            } else {
                clusters.append((signature, [email]))
            }
        }

        return clusters
            .sorted { $0.members.count > $1.members.count }
            .map(\.members)
    }

    /// The words that identify one layout: in all of its emails, in none of the
    /// others'.
    ///
    /// Drawn from the HEAD of the text on purpose. A footer word can be just as
    /// unique — Grab's food receipts all end with "Baca selengkapnya" — but a
    /// marketing footer is the part of an email a sender rewrites, and anchoring
    /// runtime matching to it is asking to break on the next campaign.
    ///
    /// ONE word, not several. Every additional required word is another way for
    /// a real future receipt to fall out of its own template. Measured over all
    /// 128 Grab emails, one word is already exact: `compliments` selects 11/11
    /// rides and nothing else, `diterbitkan` selects 10/10 food orders and
    /// nothing else — promos included.
    private static func discriminators(
        of cluster: [CapturedEmail],
        among clusters: [[CapturedEmail]]
    ) -> [String] {
        guard let first = cluster.first else { return [] }

        var shared = tokens(in: first, limit: discriminatorLength)
        for email in cluster.dropFirst() {
            shared.formIntersection(tokens(in: email, limit: discriminatorLength))
        }

        for other in clusters where !isSame(other, cluster) {
            for email in other {
                shared.subtract(tokens(in: email, limit: discriminatorLength))
            }
        }

        // Longest first: a long word is likelier to be a structural label than
        // a preposition that happened to fall on the right side of the split.
        return shared
            .sorted { ($0.count, $1) > ($1.count, $0) }
            .prefix(1)
            .map { $0 }
    }

    private static func isSame(_ lhs: [CapturedEmail], _ rhs: [CapturedEmail]) -> Bool {
        lhs.first?.id == rhs.first?.id && lhs.count == rhs.count
    }

    // MARK: - Tokens

    /// Letters only, three or more, lowercased. Digits are dropped for the same
    /// reason `normalize` collapses them: an amount and a booking ID are the
    /// email's content, and content is what we are trying to look past.
    private static func tokens(in email: CapturedEmail, limit: Int) -> Set<String> {
        let head = email.flatText.prefix(limit)
        var words: Set<String> = []
        var current = ""
        for character in head {
            if character.isLetter {
                current.append(character)
            } else {
                if current.count >= 3 { words.insert(current.lowercased()) }
                current = ""
            }
        }
        if current.count >= 3 { words.insert(current.lowercased()) }
        return words
    }

    private static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union)
    }

    /// Enough text to carry the template's structure, short enough to stay clear
    /// of the marketing tail that varies per campaign.
    private static let signatureLength = 2000
    private static let discriminatorLength = 300
    /// Grab's two layouts share almost no boilerplate and score far below this;
    /// two receipts of one layout score far above. There is no close call in the
    /// real corpus, which is why a single fixed threshold is honest here.
    private static let similarityThreshold = 0.6
}
