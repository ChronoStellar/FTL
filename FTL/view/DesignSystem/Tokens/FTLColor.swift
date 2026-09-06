//
//  FTLColor.swift
//  FTL — view/DesignSystem/Tokens
//
//  The only sanctioned source of colour. No `Color.red`, no `Color(hex:)`, no
//  `.blue` anywhere in view/. Every token is an asset-catalog colour set in
//  Assets.xcassets/Colors, addressed through Xcode's generated symbols so a
//  missing token fails the build instead of rendering nothing.
//
//  Values come from the v0.6 design canvas (Ideation/FTL App.dc.html). The app is
//  a committed dark theme; both appearance slots carry the same value so a light
//  theme can be added by editing the catalog alone.
//
//  Tokens are named for ROLE, never for hue and never for the one screen that
//  first needed them: `textSecondary`, not `indigo60` and not `heroSubtitle`.
//

import SwiftUI

enum FTLColor {

    // MARK: - Surfaces

    static let ground = Color(.ground)
    static let panel = Color(.panel)
    static let panelRaised = Color(.panelRaised)

    // MARK: - Glass
    //
    // The hero, goal and queue cards are translucent over `ground`: a gradient
    // from glassHigh to glassLow, a glassBorder hairline, and an inset highlight.
    // Use `GlassCard` rather than assembling these by hand.

    static let glassHigh = Color(.glassHigh)
    static let glassLow = Color(.glassLow)
    static let glassBorder = Color(.glassBorder)
    static let glassFill = Color(.glassFill)
    static let hairline = Color(.hairline)
    static let separator = Color(.separator)
    /// The unfilled remainder of every meter.
    static let track = Color(.track)
    static let controlFill = Color(.controlFill)
    static let controlBorder = Color(.controlBorder)

    // MARK: - Chrome

    static let navBackground = Color(.navBackground)
    static let sheetBackground = Color(.sheetBackground)
    static let scrim = Color(.scrim)
    static let glowTop = Color(.glowTop)
    static let glowBottom = Color(.glowBottom)

    // MARK: - Text

    static let textPrimary = Color(.textPrimary)
    static let textSecondary = Color(.textSecondary)
    static let textTertiary = Color(.textTertiary)
    static let textQuaternary = Color(.textQuaternary)
    static let textDisabled = Color(.textDisabled)

    // MARK: - Interaction

    static let accent = Color(.accent)
    /// Text and icons sitting on `accent`.
    static let accentContrast = Color(.accentContrast)
    /// Text on the white primary button (the Approve action).
    static let onLight = Color(.onLight)

    // MARK: - Ledger semantics

    static let spend = Color(.spend)
    static let nonSpend = Color(.nonSpend)
    /// In the cache, not yet approved.
    static let provisional = Color(.provisional)
    /// Needs a human look. Attention, not alarm.
    static let flagged = Color(.flagged)

    // MARK: - Budget standing
    //
    // Invariant 8 is a visual rule as much as a copy rule: the app reports
    // position against a ceiling the user set, and never judges them for it.
    //
    // The design resolves this differently than the first palette did. It uses one
    // warm coral for over-ceiling, for destructive actions and for errors, and
    // keeps the invariant through RESTRAINT instead of hue separation — coral
    // appears only as a thin meter fill and a small figure, never as a filled
    // banner, never with a warning glyph, never enlarged. Keep it that way.
    //
    // The three tokens stay separate despite sharing a value so `error` can
    // diverge later without touching call sites.

    static let budgetUnderCeiling = Color(.budgetUnderCeiling)
    static let budgetAtCeiling = Color(.budgetAtCeiling)
    static let budgetOverCeiling = Color(.budgetOverCeiling)

    /// Destructive actions — Drop, Reject, Sign out.
    static let destructive = Color(.destructive)
    /// Genuine system failure: a sync error, a parse failure, an expired token.
    static let error = Color(.error)

    /// The implicit child bucket — mystery spend, deliberately visible.
    static let unallocated = Color(.unallocated)

    // MARK: - Mapping

    static func forStanding(_ standing: BudgetPosition.Standing) -> Color {
        switch standing {
        case .underCeiling: return budgetUnderCeiling
        case .atCeiling: return budgetAtCeiling
        case .overCeiling: return budgetOverCeiling
        }
    }

    static func forKind(_ kind: TransactionKind) -> Color {
        switch kind {
        case .spend: return spend
        case .nonSpend: return nonSpend
        }
    }
}
