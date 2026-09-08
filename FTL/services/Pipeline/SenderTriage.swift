//
//  SenderTriage.swift
//  FTL — services/Pipeline · Stage 4 #10
//
//  How many LAYOUTS a sender's mail comes in, and which emails share each one.
//
//  A layout is the thing a pattern can be written against: one document shape,
//  reused. Senders have several, and the count is not guessable from outside.
//
//  Two passes, cheap one first — subjects, then bodies.
//
//  ONE SUBJECT IS NOT ONE LAYOUT, which is why the second pass exists. It broke
//  the first Grab run, and it was this file's fault rather than the model's. All
//  21 of Grab's receipts share the subject "Your Grab E-Receipt" and are two
//  different documents underneath:
//
//      food (10)   TOTAL Rp 44300 … Pesanan Dari: Rasapi - Sambikerep …
//      ride (11)   Total Paid Rp9.000 … Receipt issued by the driver …
//
//  Handing the learner all 21 as one template produced a perfectly good RIDE
//  pattern scored against a holdout that was half food: 0.52 coverage, under
//  the bar, rejected. The same pattern scores 1.00 against rides alone.
//
//  ONE LAYOUT IS NOT ONE SUBJECT either — the mirror case, found later and NOT
//  fixed here. The subject pass keeps only the dominant cluster, so a sender
//  using two subjects loses the smaller one unseen. See `templates(from:)` for
//  what that costs, what removing the pass would fix, and what it would cost in
//  turn. It is a live trade-off, deliberately left as one.
//
//  Measured on the real export, no model, no labels, no network:
//
//      grab.com            21 templated → 11 ride + 10 food, 0 promos
//      blubybcadigital.id  95 templated → 55 + 40, 0 promos
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

    /// One email, read ONCE.
    ///
    /// `CapturedEmail.flatText` is a computed property that strips the whole
    /// HTML body through several regexes on every access. Clustering touched it
    /// once per email per cluster, which was tolerable while a subject pre-pass
    /// cut each sender to one or two clusters and became an out-of-memory crash
    /// the moment that pre-pass was removed: thousands of full-body strips,
    /// each allocating a large transient string.
    ///
    /// So the text is read once, everything derived from it is derived here,
    /// and nothing downstream touches `flatText` again.
    private struct Prepared {
        let email: CapturedEmail
        /// Tokens over `signatureLength`, for similarity.
        var signature: Set<String>
        /// Tokens over `discriminatorLength`, for the layout's identifying word.
        let head: Set<String>
        /// Rp figures in the head of the text, for `amountVariance`.
        let amounts: Set<Money>

        init(_ email: CapturedEmail) {
            let text = email.flatText
            self.email = email
            self.signature = SenderTriage.tokens(in: text, limit: signatureLength)
            self.head = SenderTriage.tokens(in: text, limit: discriminatorLength)
            self.amounts = Set(IndonesianMoney.all(in: String(text.prefix(amountScanLength))))
        }
    }

    /// The sender's receipt layouts, largest first, each newest-first inside.
    ///
    /// Two passes, and the order matters for cost as well as correctness: the
    /// subject pass reads only `subject`, so it cuts the sender down before
    /// anything touches a body.
    ///
    /// 1. Keep the dominant SUBJECT cluster — a repeating subject is a
    ///    template, and marketing is written fresh each time.
    /// 2. Cluster THOSE by body shape, because one subject is not one layout:
    ///    all 21 Grab receipts share "Your Grab E-Receipt" and are two
    ///    different documents underneath.
    ///
    /// KNOWN LIMITATION, measured and deliberately left in place: a sender that
    /// uses two subjects has the smaller one discarded here, unseen. blu has a
    /// third layout of 12 real receipts that never reaches the loop for exactly
    /// this reason, and the fixture's `swiftpay` reproduces it on purpose.
    ///
    /// Dropping the subject pass fixes that — `Template.amountVariance` refuses
    /// marketing on its own, so the pass is no longer load-bearing for
    /// correctness. Measured over the full corpora without it:
    ///
    ///     grab  11 @ 0.91 ✓   10 @ 1.00 ✓   promos 0.41, 0.30, 0.11, 0.29 ✗
    ///     blu   70 @ 0.86 ✓   34 @ 0.91 ✓   12 @ 0.75 ✓   warnings ✗
    ///
    /// It also takes Grab from 2 clusters to 24, and two margins narrow with
    /// it: the promo/receipt variance gap goes from 0.04–0.12 vs 0.88 down to
    /// 0.41 vs 0.75, and `discriminators` walks every other cluster's mail.
    /// Worth doing on its own merits and its own measurement, not as a side
    /// effect of a fixture.
    static func templates(from emails: [CapturedEmail]) -> [Template] {
        let receipts = templatedEmails(from: emails)
        guard !receipts.isEmpty else { return [] }

        let prepared = receipts.map(Prepared.init)
        let clusters = layoutClusters(in: prepared)

        guard clusters.count > 1 else {
            return [
                Template(
                    emails: prepared.map(\.email),
                    discriminators: [],
                    amountVariance: variance(of: prepared)
                )
            ]
        }

        return clusters.map { cluster in
            Template(
                emails: cluster.map(\.email),
                discriminators: discriminators(of: cluster, among: clusters),
                amountVariance: variance(of: cluster)
            )
        }
    }

    /// Share of the layout's emails whose set of Rp figures is unique.
    ///
    /// The one question that separates a receipt template from a brochure, and
    /// it needs no model, no labels and no vocabulary: a receipt's numbers move,
    /// an advertisement's do not.
    ///
    /// Reads the head of each email rather than all of it — a footer can carry
    /// a fixed fee or a price list, and those are identical in every email by
    /// definition, which drags a real receipt's score toward a brochure's.
    private static func variance(of prepared: [Prepared]) -> Double {
        guard !prepared.isEmpty else { return 0 }
        return Double(Set(prepared.map(\.amounts)).count) / Double(prepared.count)
    }

    /// See `variance` — this is the same measure for callers holding emails.
    /// Reads each email once; do not call it in a loop over clusters.
    static func amountVariance(of emails: [CapturedEmail]) -> Double {
        variance(of: emails.map(Prepared.init))
    }

    /// The sender's templated emails, newest first.
    ///
    /// Returns everything when no subject repeats: a sender whose subjects are
    /// all unique has no template to learn, and saying so by returning the lot
    /// lets the caller's evidence bar reject it rather than this guessing.
    ///
    /// Reads `subject` only — never a body — so it is the cheap pass and
    /// belongs first.
    static func templatedEmails(from emails: [CapturedEmail]) -> [CapturedEmail] {
        guard !emails.isEmpty else { return [] }

        let clusters = Dictionary(grouping: emails) { normalize($0.subject) }
        guard let dominant = clusters.max(by: { $0.value.count < $1.value.count }) else {
            return emails
        }
        guard dominant.value.count > 1 else { return emails }

        return dominant.value.sorted { $0.date > $1.date }
    }

    /// Digits and emoji collapsed, so "Order #123" and "Order #456" are one
    /// template rather than two. Case folded for the same reason `CategoryID`
    /// is: the same subject typed twice shouldn't be two things.
    static func normalize(_ subject: String) -> String {
        subject
            .replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            .replacingOccurrences(of: #"[\p{Emoji_Presentation}\p{Extended_Pictographic}]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: - Layout clustering

    /// Groups by body shape: the set of BOILERPLATE words an email contains.
    ///
    /// "Boilerplate" is the load-bearing word. A receipt's own words — the
    /// merchant, the driver, the street — appear once in the whole corpus and
    /// would make every email its own cluster. So the vocabulary is restricted
    /// to words that recur across the sender first, and similarity is measured
    /// only over those. What survives is the template's furniture.
    private static func layoutClusters(in prepared: [Prepared]) -> [[Prepared]] {
        var documentFrequency: [String: Int] = [:]
        for item in prepared {
            for word in item.signature { documentFrequency[word, default: 0] += 1 }
        }

        let floor = max(2, prepared.count / 4)
        let vocabulary = Set(documentFrequency.filter { $0.value >= floor }.keys)
        let narrowed = prepared.map { item -> Prepared in
            var copy = item
            copy.signature = item.signature.intersection(vocabulary)
            return copy
        }

        // Greedy single pass, in the caller's order. Deterministic, O(n·k), and
        // the alternative — real agglomerative clustering — buys nothing on the
        // two-to-three layouts a sender actually has.
        var clusters: [(signature: Set<String>, members: [Prepared])] = []
        for item in narrowed {
            var bestIndex: Int?
            var bestScore = 0.0

            for (index, cluster) in clusters.enumerated() {
                let score = jaccard(item.signature, cluster.signature)
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            if let bestIndex, bestScore >= similarityThreshold {
                clusters[bestIndex].members.append(item)
                // Intersect, so the cluster's signature stays what its members
                // AGREE on rather than drifting toward whatever joined last.
                clusters[bestIndex].signature.formIntersection(item.signature)
            } else {
                clusters.append((item.signature, [item]))
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
        of cluster: [Prepared],
        among clusters: [[Prepared]]
    ) -> [String] {
        guard let first = cluster.first else { return [] }

        var shared = first.head
        for item in cluster.dropFirst() { shared.formIntersection(item.head) }
        guard !shared.isEmpty else { return [] }

        for other in clusters where other.first?.email.id != first.email.id {
            for item in other {
                shared.subtract(item.head)
                if shared.isEmpty { return [] }
            }
        }

        // Longest first: a long word is likelier to be a structural label than
        // a preposition that happened to fall on the right side of the split.
        return shared
            .sorted { ($0.count, $1) > ($1.count, $0) }
            .prefix(1)
            .map { $0 }
    }

    // MARK: - Tokens

    /// Letters only, three or more, lowercased. Digits are dropped because an
    /// amount and a booking ID are the email's content, and content is exactly
    /// what this is trying to look past.
    private static func tokens(in text: String, limit: Int) -> Set<String> {
        var words: Set<String> = []
        var current = ""
        for character in text.prefix(limit) {
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
    /// How far into an email to look for figures when scoring variance.
    private static let amountScanLength = 1500
    /// Grab's two layouts share almost no boilerplate and score far below this;
    /// two receipts of one layout score far above. There is no close call in the
    /// real corpus, which is why a single fixed threshold is honest here.
    private static let similarityThreshold = 0.6
}
