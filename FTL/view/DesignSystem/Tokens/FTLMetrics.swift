//
//  FTLMetrics.swift
//  FTL — view/DesignSystem/Tokens
//
//  Spacing, radius and type. Same rule as colour: no magic numbers in view/.
//  If a value is needed that isn't here, add a named token rather than inlining it.
//
//  Sizes, weights and tracking come from the v0.6 design canvas. The canvas
//  specifies Instrument Sans and IBM Plex Mono; we render with the system faces
//  (SF Pro / SF Mono) at the same metrics, so nothing needs bundling. Swapping in
//  the real faces later is a change to this file alone.
//

import SwiftUI

enum FTLSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
    static let xxl: CGFloat = 32

    static let screenMargin: CGFloat = 20
    /// Gap between a section label and the panel under it.
    static let labelGap: CGFloat = 8
    /// Gap above a new section label.
    static let sectionGap: CGFloat = 26
    static let cardPadding: CGFloat = 22
    static let rowPadding: CGFloat = 14
    /// Apple's minimum comfortable hit target; the canvas honours it throughout.
    static let minTapTarget: CGFloat = 44
}

enum FTLRadius {
    static let chip: CGFloat = 99
    static let control: CGFloat = 13
    static let panel: CGFloat = 16
    static let card: CGFloat = 18
    static let hero: CGFloat = 26
    static let sheet: CGFloat = 28
}

enum FTLMeter {
    /// The hero meter.
    static let heroHeight: CGFloat = 14
    /// The per-bucket meter.
    static let rowHeight: CGFloat = 6
    static let monthHeight: CGFloat = 7
}

enum FTLTypography {
    // MARK: Numbers — always monospaced, so columns align and a changing figure
    // never reflows the row around it.

    /// The hero figure: 40pt, tight tracking.
    static let display = Font.system(size: 40, weight: .semibold, design: .monospaced)
    /// The bucket-detail figure.
    static let displaySmall = Font.system(size: 38, weight: .semibold, design: .monospaced)
    /// The add-spend amount.
    static let displayLarge = Font.system(size: 44, weight: .semibold, design: .monospaced)
    /// Ledger amounts in a row.
    static let amount = Font.system(size: 15.5, weight: .medium, design: .monospaced)
    static let amountEmphasis = Font.system(size: 16, weight: .semibold, design: .monospaced)
    /// Bucket status: "622.000 left".
    static let amountSmall = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let keypad = Font.system(size: 24, weight: .medium, design: .monospaced)

    /// Section headers: "BUCKETS", "RECENT". Uppercased with wide tracking.
    static let sectionLabel = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// The FTL wordmark.
    static let wordmark = Font.system(size: 15, weight: .semibold, design: .monospaced)

    // MARK: Text

    static let navTitle = Font.system(size: 17, weight: .semibold)
    static let sheetTitle = Font.system(size: 19, weight: .semibold)
    static let rowTitle = Font.system(size: 16, weight: .medium)
    static let rowTitleTight = Font.system(size: 15.5, weight: .medium)
    static let body = Font.system(size: 15, weight: .medium)
    static let bodyRegular = Font.system(size: 15)
    static let caption = Font.system(size: 12.5)
    static let captionSmall = Font.system(size: 12)
    static let chip = Font.system(size: 15, weight: .medium)
    static let chipSmall = Font.system(size: 13.5, weight: .medium)

    /// Tracking for the uppercase section labels.
    static let sectionTracking: CGFloat = 0.66
    /// Negative tracking on the big monospaced figures.
    static let displayTracking: CGFloat = -1.4
    static let wordmarkTracking: CGFloat = 3.0
}
