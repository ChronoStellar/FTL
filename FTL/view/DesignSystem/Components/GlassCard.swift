//
//  GlassCard.swift
//  FTL — view/DesignSystem/Components
//
//  Flat surfaces. The gradient fill, the inset bevel highlight and the drop
//  shadow are gone: three layers of decoration on every card made the app look
//  busier than the data in it, and none of them carried information.
//
//  A card is a fill and a hairline. That is the whole recipe.
//

import SwiftUI

struct SurfaceCard<Content: View>: View {
    var cornerRadius: CGFloat = FTLRadius.card
    var padding: CGFloat = FTLSpacing.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FTLColor.panel,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FTLColor.hairline, lineWidth: 0.5)
            }
    }
}

/// A grouped list surface: bucket lists, ledger rows, settings rows.
struct PanelCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                FTLColor.panel,
                in: RoundedRectangle(cornerRadius: FTLRadius.panel, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FTLRadius.panel, style: .continuous)
                    .strokeBorder(FTLColor.hairline, lineWidth: 0.5)
            }
    }
}
