//
//  SampleLedger.swift
//  FTL — services/Preview
//
//  ⚠️ Fixture data for the placeholder stores. Delete with InMemoryStores.swift.
//
//  Figures and merchants come from the v0.6 design canvas so the built app can be
//  compared against the mockup directly. The queue rows are shaped after the
//  cases in tech-feasibility/reports/feasibility-report.md — a new merchant, a
//  split receipt, and a promo with no amount the gate could not read.
//

import Foundation

enum SampleLedger {

    // MARK: - Categories

    static let food = CategoryID(rawValue: "food")
    static let transport = CategoryID(rawValue: "transport")
    static let shopping = CategoryID(rawValue: "shopping")
    static let subscriptions = CategoryID(rawValue: "subscriptions")
    static let total = CategoryID(rawValue: "total")

    static var categories: [SpendCategory] {
        [
            SpendCategory(id: food, name: "Food", parentID: total),
            SpendCategory(id: transport, name: "Transport", parentID: total),
            SpendCategory(id: shopping, name: "Shopping", parentID: total),
            SpendCategory(id: subscriptions, name: "Subscriptions", parentID: total),
        ]
    }

    /// One root ceiling partitioned into named buckets. Whatever the named
    /// children don't claim is the implicit unallocated child.
    static var budgetTree: [BudgetNode] {
        [
            BudgetNode(
                id: total,
                name: "Total",
                ceiling: .idr(6_500_000),
                children: [
                    BudgetNode(id: food, name: "Food", ceiling: .idr(2_400_000), children: []),
                    BudgetNode(id: transport, name: "Transport", ceiling: .idr(900_000), children: []),
                    BudgetNode(id: shopping, name: "Shopping", ceiling: .idr(1_200_000), children: []),
                    BudgetNode(id: subscriptions, name: "Subscriptions", ceiling: .idr(350_000), children: []),
                ]
            )
        ]
    }
    // MARK: - Ledger

    /// Three months: two closed, the current one in progress.
    static var transactions: [LedgerTransaction] {
        currentMonth + previousMonth(offset: 1) + previousMonth(offset: 2)
    }

    private static var currentMonth: [LedgerTransaction] {
        [
            row(day: 1, amount: 34_500, raw: "GOJEK", category: transport, source: .email),
            row(day: 1, amount: 28_000, raw: "KOPI KENANGAN", category: food, source: .email),
            row(day: 2, amount: 42_000, raw: "WARUNG BU TINI", category: food, source: .photo),
            row(day: 2, amount: 65_000, raw: "NETFLIX.COM", category: subscriptions, source: .statement),
            row(day: 4, amount: 67_500, raw: "GOFOOD*SATE PADANG", category: food, source: .email),
            row(day: 5, amount: 449_000, raw: "UNIQLO PACIFIC PLACE", category: shopping, source: .email),
            row(day: 5, amount: 3_500, raw: "TRANSJAKARTA", category: transport, source: .email),
            row(day: 7, amount: 961_000, raw: "TOKOPEDIA", category: shopping, source: .email),
            row(day: 8, amount: 1_707_500, raw: "SUPERINDO", category: food, source: .statement),
            row(day: 9, amount: 574_000, raw: "GRAB", category: transport, source: .email),
            row(day: 9, amount: 285_000, raw: "SUBSCRIPTION BUNDLE", category: subscriptions, source: .statement),
            // No bucket at all — surfaces under Unallocated.
            row(day: 6, amount: 165_000, raw: "ATM TARIK TUNAI", category: nil, source: .statement),
            // Excluded from every ceiling (Invariant 5), kept for audit.
            row(day: 3, amount: 1_000_000, raw: "TOPUP GOPAY", category: nil,
                source: .statement, kind: .nonSpend, nonSpendType: .topup),
        ]
    }

    private static func previousMonth(offset: Int) -> [LedgerTransaction] {
        [
            row(day: 4, amount: 2_050_000, raw: "GROCERIES", category: food, source: .statement, monthsAgo: offset),
            row(day: 9, amount: 590_000, raw: "TRANSPORT", category: transport, source: .statement, monthsAgo: offset),
            row(day: 14, amount: 890_000, raw: "RETAIL", category: shopping, source: .statement, monthsAgo: offset),
            row(day: 19, amount: 350_000, raw: "SUBSCRIPTIONS", category: subscriptions, source: .statement, monthsAgo: offset),
            row(day: 24, amount: 1_380_000, raw: "UNCATEGORIZED", category: nil, source: .statement, monthsAgo: offset),
        ]
    }

    /// Rows waiting on the human gate. Not counted anywhere yet (Invariant 7).
    static var provisionalEntries: [ProvisionalEntry] {
        [
            entry(daysAgo: 0, amount: 289_000, raw: "TOKOPEDIA", category: shopping, source: .email,
                  provenance: .model(confidence: 0.74),
                  flags: [ReviewFlag(reason: .unknownMerchant, detail: "no category matched")]),
            entry(daysAgo: 1, amount: 88_000, raw: "INDOMARET", category: food, source: .photo,
                  provenance: .model(confidence: 0.71),
                  flags: [ReviewFlag(reason: .needsSplit, detail: "two buckets on one receipt")]),
            entry(daysAgo: 0, amount: 0, raw: "SHOPEE", category: nil, source: .email,
                  provenance: .rule(RuleID(rawValue: "no-amount")),
                  kind: .nonSpend,
                  flags: [ReviewFlag(reason: .unparseable, detail: "promo, no amount found")]),
            // Never reaches the stack — the rail dropped it at capture. Here so
            // the queue's "dropped as duplicates" section has something to show
            // without a live sync, which is the only other way to produce one.
            entry(daysAgo: 0, amount: 289_000, raw: "TOKOPEDIA", category: shopping, source: .email,
                  provenance: .rule(RuleID(rawValue: "tokopedia-receipt")),
                  flags: [ReviewFlag(
                      reason: .possibleDuplicate,
                      detail: "Same amount and merchant as a row already in the queue, dated today"
                  )],
                  status: .autoDropped),
        ]
    }

    // MARK: - Builders

    /// `day` counts back from the most recent day the month has reached — today
    /// for the live month, the last day for a closed one. Anchoring forward from
    /// the 1st puts fixture rows in the future early in a month, and a ledger
    /// showing "in 5 days" reads as a bug rather than as sample data.
    private static func date(day: Int, monthsAgo: Int = 0) -> Date {
        let calendar = Calendar.current
        let now = Date.now
        let base = calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
        guard let monthStart = calendar.dateInterval(of: .month, for: base)?.start,
              let lastDay = calendar.range(of: .day, in: .month, for: base)?.count
        else { return base }

        // Wrap rather than clamp: clamping piles every row past today onto the
        // 1st, which both looks wrong and lands them on the month boundary.
        let latestDay = monthsAgo == 0 ? calendar.component(.day, from: now) : lastDay
        let offset = latestDay > 1 ? (latestDay - 1) - ((day - 1) % latestDay) : 0
        return calendar.date(byAdding: .day, value: max(0, offset), to: monthStart) ?? base
    }

    private static func row(
        day: Int,
        amount: Int,
        raw: String,
        category: CategoryID?,
        source: CaptureSource,
        monthsAgo: Int = 0,
        kind: TransactionKind = .spend,
        nonSpendType: NonSpendType? = nil
    ) -> LedgerTransaction {
        let when = date(day: day, monthsAgo: monthsAgo)
        return LedgerTransaction(
            id: UUID(),
            date: when,
            amount: .idr(amount),
            merchantRaw: raw,
            merchant: raw.capitalized,
            categoryID: category,
            kind: kind,
            nonSpendType: nonSpendType,
            source: source,
            sourcesMerged: [],
            splits: [],
            lineItems: [],
            provenance: .rule(RuleID(rawValue: "known-merchant")),
            flags: [],
            capturedAt: when,
            approvedAt: when,
            notes: nil
        )
    }

    private static func entry(
        daysAgo: Int,
        amount: Int,
        raw: String,
        category: CategoryID?,
        source: CaptureSource,
        provenance: ProvisionalEntry.Provenance,
        kind: TransactionKind = .spend,
        flags: [ReviewFlag] = [],
        status: ProvisionalEntry.Status = .pending
    ) -> ProvisionalEntry {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let money = Money.idr(amount)
        let transaction = NormalizedTransaction(
            id: UUID(),
            documentID: UUID(),
            source: source,
            date: when,
            amount: money,
            merchantRaw: raw,
            merchant: nil,
            lineItems: [],
            fingerprint: Fingerprint(amount: money, date: when)
        )
        return ProvisionalEntry(
            id: UUID(),
            transaction: transaction,
            resolution: ProvisionalEntry.Resolution(
                kind: kind,
                nonSpendType: nil,
                categoryID: category,
                merchantID: nil,
                splits: [],
                mergedFrom: []
            ),
            provenance: provenance,
            flags: flags,
            status: status,
            createdAt: when
        )
    }
}
