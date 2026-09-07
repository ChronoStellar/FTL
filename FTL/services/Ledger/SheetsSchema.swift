//
//  SheetsSchema.swift
//  FTL — services/Ledger
//
//  The wire format between LedgerTransaction and the spreadsheet. One place, so a
//  column added here can't drift from the code that reads it back.
//
//  Everything is written with valueInputOption=RAW: USER_ENTERED would let Sheets
//  reinterpret "2026-09-07" as a date serial and hand it back locale-formatted,
//  and amounts as floats. Strings in, same strings out.
//
//  Amounts are stored as integer minor units (34500, not "Rp 34.500") — Invariant
//  4 all the way to the sheet. The cell is less pretty; the arithmetic is exact.
//

import Foundation

enum SheetsSchema {

    // MARK: - Tabs

    enum Tab {
        static let transactions = "transactions"
        static let budgets = "budgets"
    }

    static let transactionColumns = [
        "id", "date", "amount", "currency", "merchant_raw", "merchant",
        "category", "kind", "non_spend_type", "source", "provenance",
        "confidence", "flags", "captured_at", "approved_at", "notes",
    ]

    static let budgetColumns = ["category_id", "name", "parent_id", "ceiling", "month"]

    /// Widest column letter for each tab, for A1 ranges.
    static let transactionRange = "A:P"
    static let budgetRange = "A:E"

    // MARK: - Transactions

    static func row(from tx: LedgerTransaction) -> [String] {
        [
            tx.id.uuidString,
            dayFormatter.string(from: tx.date),
            String(tx.amount.minorUnits),
            tx.amount.currency.rawValue,
            tx.merchantRaw,
            tx.merchant ?? "",
            tx.categoryID?.rawValue ?? "",
            tx.kind.rawValue,
            tx.nonSpendType?.rawValue ?? "",
            tx.source.rawValue,
            provenanceString(tx.provenance),
            confidenceString(tx.provenance),
            tx.flags.map(\.reason.rawValue).joined(separator: "|"),
            stampFormatter.string(from: tx.capturedAt),
            stampFormatter.string(from: tx.approvedAt),
            tx.notes ?? "",
        ]
    }

    /// Returns nil for a row that can't be read as a transaction. A malformed row
    /// is skipped and reported, never guessed at — the sheet is user-editable and
    /// half-typed rows are normal.
    static func transaction(from row: [String]) -> LedgerTransaction? {
        func cell(_ index: Int) -> String {
            index < row.count ? row[index].trimmingCharacters(in: .whitespaces) : ""
        }
        guard let id = UUID(uuidString: cell(0)),
              let date = dayFormatter.date(from: cell(1)),
              let minorUnits = Int(cell(2))
        else { return nil }

        let currency = cell(3).isEmpty ? CurrencyCode.idr : CurrencyCode(rawValue: cell(3))
        let category = cell(6).isEmpty ? nil : CategoryID(rawValue: cell(6))
        let flags = cell(12)
            .split(separator: "|")
            .compactMap { ReviewFlag.Reason(rawValue: String($0)) }
            .map { ReviewFlag(reason: $0, detail: nil) }

        return LedgerTransaction(
            id: id,
            date: date,
            amount: Money(minorUnits: minorUnits, currency: currency),
            merchantRaw: cell(4),
            merchant: cell(5).isEmpty ? nil : cell(5),
            categoryID: category,
            kind: TransactionKind(rawValue: cell(7)) ?? .spend,
            nonSpendType: NonSpendType(rawValue: cell(8)),
            source: CaptureSource(rawValue: cell(9)) ?? .manual,
            sourcesMerged: [],
            splits: [],
            lineItems: [],
            provenance: provenance(from: cell(10), confidence: cell(11)),
            flags: flags,
            capturedAt: stampFormatter.date(from: cell(13)) ?? date,
            approvedAt: stampFormatter.date(from: cell(14)) ?? date,
            notes: cell(15).isEmpty ? nil : cell(15)
        )
    }

    // MARK: - Budgets

    static func row(categoryID: CategoryID, name: String, parentID: CategoryID?, ceiling: Money, month: String) -> [String] {
        [categoryID.rawValue, name, parentID?.rawValue ?? "", String(ceiling.minorUnits), month]
    }

    /// `month` is "2026-09", or blank meaning "applies to every month".
    static func monthKey(for interval: DateInterval) -> String {
        monthFormatter.string(from: interval.start)
    }

    // MARK: - Provenance

    private static func provenanceString(_ p: ProvisionalEntry.Provenance) -> String {
        switch p {
        case .rule(let id): return "rule:\(id.rawValue)"
        case .model: return "model"
        case .manual: return "manual"
        }
    }

    private static func confidenceString(_ p: ProvisionalEntry.Provenance) -> String {
        if case .model(let confidence) = p { return String(format: "%.2f", confidence) }
        return ""
    }

    private static func provenance(from raw: String, confidence: String) -> ProvisionalEntry.Provenance {
        if raw == "model" { return .model(confidence: Double(confidence) ?? 0) }
        if raw.hasPrefix("rule:") { return .rule(RuleID(rawValue: String(raw.dropFirst(5)))) }
        return .manual
    }

    // MARK: - Formatters
    //
    // Fixed locale and UTC. A ledger that reformats itself when the phone's region
    // changes is a ledger that stops parsing.

    private static let dayFormatter: DateFormatter = formatter("yyyy-MM-dd")
    private static let stampFormatter: DateFormatter = formatter("yyyy-MM-dd'T'HH:mm:ss'Z'")
    private static let monthFormatter: DateFormatter = formatter("yyyy-MM")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }
}
