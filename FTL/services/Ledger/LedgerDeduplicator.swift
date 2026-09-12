//
//  LedgerDeduplicator.swift
//  FTL — services/Ledger
//
//  Single source of truth for transaction deduplication across:
//  - SheetsLedgerStore (before writing to Google Sheets)
//  - InMemoryLedgerStore (test/preview parity)
//  - DefaultApprovalService (human gate approval check)
//  - ApprovalQueueViewModel (queue loading & cleanup)
//  - GmailRail (capture gate check against ledger)
//

import Foundation

nonisolated enum LedgerDeduplicator {

    /// Exact idempotency match, or a 3-part semantic match:
    /// 1. ID match (exact UUID)
    /// 2. Amount match (exact minor units AND currency)
    /// 3. Merchant match (normalized name, or a cross-rail alias)
    /// 4. Same calendar day
    static func isDuplicate(_ lhs: LedgerTransaction, _ rhs: LedgerTransaction) -> Bool {
        if lhs.id == rhs.id { return true }
        return isSemanticMatch(
            amount1: lhs.amount,
            merchantRaw1: lhs.merchantRaw,
            date1: lhs.date,
            source1: lhs.source,
            provenance1: lhs.provenance,
            amount2: rhs.amount,
            merchantRaw2: rhs.merchantRaw,
            date2: rhs.date,
            source2: rhs.source,
            provenance2: rhs.provenance
        )
    }

    /// Match a provisional entry against an existing ledger transaction.
    static func isDuplicate(_ entry: ProvisionalEntry, as tx: LedgerTransaction) -> Bool {
        if entry.id == tx.id { return true }
        return isSemanticMatch(
            amount1: entry.transaction.amount,
            merchantRaw1: entry.transaction.merchantRaw,
            date1: entry.transaction.date,
            source1: entry.transaction.source,
            provenance1: entry.provenance,
            amount2: tx.amount,
            merchantRaw2: tx.merchantRaw,
            date2: tx.date,
            source2: tx.source,
            provenance2: tx.provenance
        )
    }

    /// Exact amount, matching merchant, same calendar day. Nothing finer, and
    /// the reason is a hard limit rather than a preference.
    ///
    /// **There is no transaction time to compare.** `SheetsSchema` writes the
    /// date with `dayFormatter` ("yyyy-MM-dd", fixed UTC), so a purchase's time
    /// of day does not survive the write and is gone on read-back — every row
    /// `LedgerStore.all()` returns is at midnight. The first version of this
    /// file reached for `capturedAt` to fill that gap, and `capturedAt` is the
    /// time the SYNC ran, not the time anything was bought. Measured on the
    /// real 137-row ledger, where 130 rows share one `capturedAt` second:
    ///
    /// - **Duplicates passed straight through.** A fresh entry carries a real
    ///   time from the email (19:58), the stored row fell back to its sync
    ///   stamp (08:47), the 15-minute proximity test saw an 11-hour gap on the
    ///   same day and concluded "two distinct charges" — so the duplicate was
    ///   appended again. The window was comparing a purchase against a sync.
    /// - **Real spending was swallowed.** For two rows both already stored,
    ///   both stamps resolved to nil and the rule fell through to `true`, while
    ///   `capturedSameDay` made the day gate pass for any pair from the same
    ///   sync. 29 of 137 rows matched, **9 of them provably wrong** — including
    ///   `Google YouTubePremium` Rp 76,590 matched against itself 31 days
    ///   apart, which is a monthly subscription, plus transfers 22 and 53 days
    ///   apart and a daily-habit warung 8 days apart.
    ///
    /// Same data, this rule: **21 matches, every one a genuine cross-rail
    /// duplicate** — blu's card notification (`Grab* A-9MVBRDUGW7GDAV`)
    /// against Grab's own receipt (`Pengemudi Royke Hentje Paat Diterbitkan…`)
    /// — and all 9 false positives gone.
    ///
    /// ⚠️ One case is unresolvable by construction and no threshold changes
    /// it: two `Grab* 9879131c5fa5de5d` rows, Rp 24,000, same day, identical
    /// merchant string. One ride counted twice and two identical rides are the
    /// same bytes. Without a stored transaction time the data cannot say, so
    /// whichever way this rule answers, it is guessing on that one.
    static func isSemanticMatch(
        amount1: Money,
        merchantRaw1: String,
        date1: Date,
        source1: CaptureSource?,
        provenance1: ProvisionalEntry.Provenance?,
        amount2: Money,
        merchantRaw2: String,
        date2: Date,
        source2: CaptureSource?,
        provenance2: ProvisionalEntry.Provenance?
    ) -> Bool {
        // 1. Amount — exact, including currency. Invariant 4: never a tolerance.
        guard amount1 == amount2 else { return false }

        // 2. Merchant — unless exactly one side was typed by hand.
        //
        // A hand-typed label and a bank descriptor have no reason on earth to
        // resemble each other, and requiring them to is requiring something
        // that is essentially never true. Real pairs out of the live sheet,
        // every one of them one purchase recorded twice:
        //
        //     "glazed donut"       ↔ MIDNIGHT DONUTCITRALAND SURABAYA
        //     "MMBN Legacy Vol2"   ↔ WL *STEAM PURCHASE
        //     "salad"              ↔ HOKKY SUPERMARKET SURABAYA
        //
        // No string rule bridges those, and none should try — you cannot
        // derive "Steam" from "MMBN Legacy Vol2" without knowing what the game
        // is. What DOES identify them is arithmetic: same amount, same day,
        // one typed and one parsed. So when the pair crosses the manual
        // boundary the merchant test is skipped rather than loosened, because
        // a test that can only ever answer "no" is not evidence.
        //
        // Only when EXACTLY one side is manual. Two hand-typed rows should
        // still resemble each other, and two parsed rows always describe the
        // merchant in the merchant's own words.
        let manual1 = isManualEntry(source: source1, provenance: provenance1)
        let manual2 = isManualEntry(source: source2, provenance: provenance2)
        if manual1 == manual2 {
            guard isMerchantMatch(
                lhsRaw: merchantRaw1,
                rhsRaw: merchantRaw2,
                lhsRule: provenanceRuleName(provenance1),
                rhsRule: provenanceRuleName(provenance2)
            ) else { return false }
        }

        // 3. Same calendar day — the finest the ledger can still answer.
        //
        // Both calendars, because the stored date is UTC midnight while a
        // fresh entry carries a real local timestamp: an evening purchase in
        // WIB lands on the previous UTC day, and one comparison or the other
        // has to cover that seam. Measured on the real ledger, adding the
        // local-calendar arm changes nothing (21 matches either way) — it is
        // there for the boundary, not for reach.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.isDate(date1, inSameDayAs: date2)
            || Calendar.current.isDate(date1, inSameDayAs: date2)
    }

    static func isMerchantMatch(
        lhsRaw: String,
        rhsRaw: String,
        lhsRule: String? = nil,
        rhsRule: String? = nil
    ) -> Bool {
        let norm1 = MerchantID(normalizing: lhsRaw).rawValue
        let norm2 = MerchantID(normalizing: rhsRaw).rawValue

        // If either is empty or manual entry
        if (norm1.isEmpty && (lhsRule == "another source" || lhsRaw.localizedCaseInsensitiveContains("manual"))) ||
           (norm2.isEmpty && (rhsRule == "another source" || rhsRaw.localizedCaseInsensitiveContains("manual"))) {
            return true
        }

        // Exact normalized match
        if !norm1.isEmpty && !norm2.isEmpty && norm1 == norm2 {
            return true
        }

        // Substring / containment (e.g. "Starbucks" vs "Starbucks Indonesia")
        if !norm1.isEmpty && !norm2.isEmpty && (norm1.contains(norm2) || norm2.contains(norm1)) {
            return true
        }

        // Cross-rail: the bank names the PLATFORM, the merchant names the ITEM.
        //
        // This was hardcoded to Grab, and the hardcode was hiding the general
        // shape. Every bank card descriptor embeds the platform it paid, while
        // the platform's own receipt describes what you actually bought:
        //
        //     WL *STEAM PURCHASE      ↔ steampowered.com  "Mega Man Battle Network…"
        //     Grab* A-9MVBRDUGW7GDAV  ↔ grab.com/…        "Pengemudi Royke Hentje…"
        //     GOOGLE *ANDROID TEMP    ↔ google.com
        //     SHOPEE                  ↔ mail.shopee.co.id
        //
        // So the bridge is: does a platform-shaped token on one side appear in
        // the OTHER side's rule id, which is its sender domain? That is the
        // same test the Grab hardcode was doing, with the merchant name read
        // from the data instead of written into the source.
        //
        // Tokens must be ≥4 characters and not generic payment vocabulary, or
        // "purchase" and "temp" start bridging unrelated senders. Measured on
        // the 137-row ledger: reproduces all 20 Grab pairs the hardcode caught
        // (the other 2 it caught are an identical-string triple, which the
        // exact arm above already matches), and finds no new pair — there is
        // no commerce-side row in that corpus to find.
        if bridgesPlatform(raw: lhsRaw, toRule: rhsRule) || bridgesPlatform(raw: rhsRaw, toRule: lhsRule) {
            return true
        }

        return false
    }

    /// Generic payment vocabulary — present in descriptors, meaningless as an
    /// identity. `receipt` is here because `blu-receipt` is itself a rule id.
    private static let descriptorNoise: Set<String> = [
        "purchase", "payment", "temp", "temporary", "hold", "transaction",
        "online", "debit", "credit", "card", "pending", "store", "receipt",
        "mail", "info", "com", "www",
    ]

    /// Does this merchant string name a platform that the other side's rule id
    /// (its sender domain) belongs to?
    private static func bridgesPlatform(raw: String, toRule rule: String?) -> Bool {
        guard let rule, !rule.isEmpty else { return false }
        let haystack = rule.lowercased()
        return MerchantID(normalizing: raw).rawValue
            .split(separator: " ")
            .contains { token in
                token.count >= 4 && !descriptorNoise.contains(String(token)) && haystack.contains(token)
            }
    }

    private static func provenanceRuleName(_ p: ProvisionalEntry.Provenance?) -> String? {
        guard let p else { return nil }
        if case .rule(let id) = p { return id.rawValue }
        return nil
    }

    /// Typed by a person rather than read off a document. Both signals,
    /// because `ManualEntry` sets both and a row that carries either one is
    /// not something a parser produced.
    static func isManualEntry(source: CaptureSource?, provenance: ProvisionalEntry.Provenance?) -> Bool {
        if source == .manual { return true }
        if case .manual = provenance { return true }
        return false
    }
}
