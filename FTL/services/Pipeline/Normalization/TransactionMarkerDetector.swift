//
//  TransactionMarkerDetector.swift
//  FTL — services/Pipeline/Normalization
//
//  Fast, deterministic scanner for transaction evidence (currency, success phrasing,
//  and payment keywords) in Indonesian and English.
//

import Foundation

nonisolated enum TransactionMarkerDetector: Sendable {

    /// Core currency markers.
    static let currencyMarkers = [
        "Rp", "IDR", "Rp."
    ]

    private static let currencyRegex: NSRegularExpression = {
        // Matches:
        // 1. Standalone currency codes/symbols: \b(rp|idr)\b
        // 2. Currency symbol followed by optional punctuation/space and numbers: \b(rp|idr)\.?\s*[:.]?\s*\d
        // 3. Numbers followed by IDR: \d\s*idr\b
        let pattern = #"(?i)\b(?:(?:rp\.?|idr)\s*[:.-]?\s*\d[\d.,]*(?:\s*(?:k|rb|ribu|jt|juta|m|miliar|perak))?|\d[\d.,]*\s*(?:k|rb|ribu|jt|juta|m|miliar)?\s*(?:rp\.?|idr|rupiah|perak))\b"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Returns true if the text contains an Indonesian currency marker ("Rp", "Rp.", "IDR").
    /// Uses word boundary and digit proximity checking so words like "berpikir", "enterprise",
    /// "description", "surprise" do NOT falsely trigger currency detection.
    static func hasCurrencyMarker(in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return currencyRegex.firstMatch(in: text, range: range) != nil
    }

    /// High-confidence success and completion phrases.
    static let successPhrases = [
        // Indonesian
        "transaksi berhasil",
        "pembayaran berhasil",
        "berhasil dibayar",
        "berhasil ditransfer",
        "total bayar",
        "bukti pembayaran",
        "bukti transaksi",
        "rincian pembayaran",
        "pesanan selesai",
        "struk pembayaran",
        "tagihan lunas",
        // English
        "transaction successful",
        "payment successful",
        "order confirmed",
        "order confirmation",
        "payment receipt",
        "receipt for your",
        "e-receipt",
        "billing receipt",
        "invoice paid"
    ]

    struct Evidence: Sendable {
        let hasCurrency: Bool
        let matchedCurrencies: [String]
        let hasSuccessPhrase: Bool
        let matchedPhrases: [String]

        var isLikelyTransaction: Bool {
            hasCurrency && hasSuccessPhrase
        }
    }

    /// Scans a text for transaction evidence.
    static func detect(in text: String) -> Evidence {
        var matchedCurrencies: [String] = []
        if !text.isEmpty {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            currencyRegex.enumerateMatches(in: text, range: nsRange) { match, _, stop in
                if let match, let r = Range(match.range, in: text) {
                    let token = String(text[r])
                    if !matchedCurrencies.contains(token) {
                        matchedCurrencies.append(token)
                    }
                    if matchedCurrencies.count >= 5 { stop.pointee = true }
                }
            }
        }

        var matchedPhrases: [String] = []
        for phrase in successPhrases {
            if text.range(of: phrase, options: .caseInsensitive) != nil {
                matchedPhrases.append(phrase)
            }
        }

        return Evidence(
            hasCurrency: !matchedCurrencies.isEmpty,
            matchedCurrencies: matchedCurrencies,
            hasSuccessPhrase: !matchedPhrases.isEmpty,
            matchedPhrases: matchedPhrases
        )
    }
}
