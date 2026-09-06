//
//  GlassCard.swift
//  FTL — view/DesignSystem/Components
//
//  The design's signature surface: a translucent gradient over the ground, a
//  hairline border, and a one-pixel inset highlight along the top edge that reads
//  as light catching a bevel.
//
//  Assembled once here so the recipe can't drift between screens.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = FTLRadius.hero
    var padding: CGFloat = FTLSpacing.cardPadding
    var isElevated: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // The canvas's backdrop-filter over a dark ground reads as a
                // subtly lighter indigo. SwiftUI's `.ultraThinMaterial` is much
                // lighter than that and turns the card grey, so the gradient sits
                // directly on the ground instead — the glows behind it still show
                // through the translucent fill.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [FTLColor.glassHigh, FTLColor.glassLow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FTLColor.glassBorder, lineWidth: 0.5)
            }
            .overlay(alignment: .top) {
                // The inset highlight. Inset so it follows the corner curve
                // instead of running flat across the top.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [FTLColor.glassBorder, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: isElevated ? Color.black.opacity(0.5) : .clear,
                radius: 22, x: 0, y: 14
            )
    }
}

/// The opaque grouped-list surface: bucket lists, ledger rows, settings rows.
struct PanelCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(FTLColor.panel, in: RoundedRectangle(cornerRadius: FTLRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FTLRadius.panel, style: .continuous)
                    .strokeBorder(FTLColor.hairline, lineWidth: 0.5)
            }
    }
}
