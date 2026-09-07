//
//  BluReceiptParser.swift
//  FTL — services/Pipeline
//
//  blu by BCA — the largest receipt source in the corpus (116 of 1000 emails,
//  95 of them with a byte-identical subject).
//
//  Reads the Gmail snippet, not the body: blu sends HTML-only, so there is no
//  plain body to parse, and the ~200-character preview happens to carry the whole
//  transaction. Every one of the 112 transaction emails yields an amount from the
//  snippet alone.
//
//  Two shapes:
//    purchase  Total Rp18.000,00 … bluAccount KEMBANG TAHU MUSTOPA SURABAYA Amount …
//    transfer  Amount Rp400.000,00 … HENDRIK NICOLAS… BCA 5271 9632 39 Admin Fee …
//
//  The second is money moving between the user's own accounts. Labelled
//  non-spend, kept, and excluded from every ceiling (Invariant 5).
//

import Foundation

struct BluReceiptParser: ReceiptParser {
    let id = RuleID(rawValue: "blu-receipt")

    private static let domain = "blubybcadigital.id"

    func canParse(_ email: CapturedEmail) -> Bool {
        email.senderDomain.hasSuffix(Self.domain)
    }

    func parse(_ email: CapturedEmail) -> ReceiptParseResult {
        guard canParse(email) else { return .notApplicable }

        let subject = email.subject.lowercased()
        // blu also sends promos and fraud warnings from the same address.
        guard subject.contains("transaction") || subject.contains("refund") else {
            return .notAPurchase
        }

        let text = email.searchText
        guard let counterparty = Self.counterparty(in: text) else {
            return .incomplete(missing: "counterparty")
        }
        guard let amount = IndonesianMoney.labelled("Total", in: text)
                ?? IndonesianMoney.labelled("Amount", in: text)
        else {
            return .incomplete(missing: "amount")
        }

        let isTransfer = Self.looksLikeAccountTransfer(counterparty: counterparty, text: text)
        let isRefund = subject.contains("refund")

        return .parsed(
            ParsedReceipt(
                // The snippet truncates before the transaction date, so the
                // email's own timestamp stands in. Same day in practice; worth
                // revisiting once bodies are exported.
                date: email.date,
                amount: amount,
                merchantRaw: counterparty,
                kind: (isTransfer || isRefund) ? .nonSpend : .spend,
                nonSpendType: isRefund ? .refund : (isTransfer ? .transfer : nil),
                flags: []
            )
        )
    }

    // MARK: - Extraction

    /// The text between "bluAccount" and whatever terminates it: a merchant name
    /// on a purchase, an account holder plus bank on a transfer.
    static func counterparty(in text: String) -> String? {
        guard let start = text.range(of: "bluAccount", options: .caseInsensitive) else { return nil }
        let tail = text[start.upperBound...]

        let terminators = ["Amount", "bluVirtual", "Admin Fee", "Transaction Date", "Transaction ID"]
        var end = tail.endIndex
        for terminator in terminators {
            if let found = tail.range(of: terminator, options: .caseInsensitive), found.lowerBound < end {
                end = found.lowerBound
            }
        }

        let value = tail[tail.startIndex..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// A transfer names a bank and an account number where a purchase names a
    /// shop. "Admin Fee" only ever appears on a transfer.
    static func looksLikeAccountTransfer(counterparty: String, text: String) -> Bool {
        if text.range(of: "Admin Fee", options: .caseInsensitive) != nil { return true }
        let banks = ["BCA", "BNI", "BRI", "MANDIRI", "PERMATA", "CIMB", "blu"]
        let namesBank = banks.contains { counterparty.range(of: $0, options: .caseInsensitive) != nil }
        // Four or more consecutive digits reads as an account number, not a shop.
        let hasAccountNumber = counterparty.range(of: #"\d{4}"#, options: .regularExpression) != nil
        return namesBank && hasAccountNumber
    }
}
