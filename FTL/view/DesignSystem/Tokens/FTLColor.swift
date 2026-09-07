//
//  FTLColor.swift
//  FTL — view/DesignSystem/Tokens
//
//  The only sanctioned source of colour. No `Color.red`, no `Color(hex:)`, no
//  `.blue` anywhere in view/. Every token is an asset-catalog colour set in
//  Assets.xcassets/Colors, addressed through Xcode's generated symbols so a
//  missing token fails the build instead of rendering nothing.
//
//  NEUTRAL GREYSCALE PLUS ONE SIGNAL COLOUR. There is no accent hue and no
//  gradient anywhere in the app. Hierarchy comes from type size and value;
//  colour is spent only on the thing that needs pointing at.
//
//  Tokens are named for ROLE, never for hue and never for the one screen that
//  first needed them: `textSecondary`, not `grey60` and not `heroSubtitle`.
//

import SwiftUI

enum FTLColor {

    // MARK: - Surfaces
    //
    // Flat and opaque. No translucency, no gradient, no shadow.

    static let ground = Color(.ground)
    static let panel = Color(.panel)
    static let panelRaised = Color(.panelRaised)

    // MARK: - Lines and fills

    static let hairline = Color(.hairline)
    static let separator = Color(.separator)
    /// The unfilled remainder of every meter.
    static let track = Color(.track)
    static let controlFill = Color(.controlFill)
    static let controlBorder = Color(.controlBorder)
    /// Queue cards and unselected chips.
    static let glassFill = Color(.glassFill)
    static let scrim = Color(.scrim)

    // MARK: - Chrome

    static let navBackground = Color(.navBackground)
    static let sheetBackground = Color(.sheetBackground)

    // MARK: - Text

    static let textPrimary = Color(.textPrimary)
    static let textSecondary = Color(.textSecondary)
    static let textTertiary = Color(.textTertiary)
    static let textQuaternary = Color(.textQuaternary)
    static let textDisabled = Color(.textDisabled)

    // MARK: - Interaction
    //
    // Emphasis is white on the dark ground. There is deliberately no accent hue:
    // a tinted button in a ledger competes with the one colour that means
    // something.

    static let accent = Color(.accent)
    static let accentContrast = Color(.accentContrast)
    /// Text on the white primary button.
    static let onLight = Color(.onLight)

    // MARK: - Ledger semantics

    static let spend = Color(.spend)
    static let nonSpend = Color(.nonSpend)
    /// In the cache, not yet approved. Distinguished by placement and copy, not
    /// by hue — provisional rows live in their own sheet and say what they are.
    static let provisional = Color(.provisional)

    // MARK: - The signal
    //
    // One colour, used for three things that all mean "look here": over a
    // ceiling, flagged for review, and destructive. They stay separate tokens so
    // any one can diverge later without touching call sites.
    //
    // Invariant 8 is carried by RESTRAINT, not by hue separation. The signal
    // appears as a thin meter fill and a small figure — never a filled banner,
    // never a warning glyph, never enlarged. A row over its ceiling says
    // "210.000 over" and stops: no verb, no adjective, no icon.

    static let budgetOverCeiling = Color(.budgetOverCeiling)
    static let flagged = Color(.flagged)
    static let destructive = Color(.destructive)
    /// Genuine system failure: a sync error, a parse failure, an expired token.
    static let error = Color(.error)

    // MARK: - Budget standing

    static let budgetUnderCeiling = Color(.budgetUnderCeiling)
    static let budgetAtCeiling = Color(.budgetAtCeiling)
    /// The implicit child bucket — mystery spend, deliberately visible but quiet.
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
