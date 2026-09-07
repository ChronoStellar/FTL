//
//  TransactionMarkerDetector.swift
//  FTL — services/Pipeline/Normalization
//
//  Fast, deterministic scanner for transaction evidence (currency, success phrasing,
//  and payment keywords) in Indonesian and English.
//

import Foundation

enum TransactionMarkerDetector: Sendable {

    /// Core currency markers.
    static let currencyMarkers = [
        "Rp", "IDR", "Rp."
    ]

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
        for marker in currencyMarkers {
            if text.range(of: marker, options: .caseInsensitive) != nil {
                matchedCurrencies.append(marker)
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
