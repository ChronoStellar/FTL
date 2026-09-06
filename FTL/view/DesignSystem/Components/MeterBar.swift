//
//  MeterBar.swift
//  FTL — view/DesignSystem/Components
//
//  Position against a ceiling, as a bar. Every meter in the app is this view.
//
//  Invariant 8 lives here as much as anywhere: the bar fills, it clamps at full,
//  and when spending passes the ceiling the fill changes colour and nothing else.
//  No pulse, no stripe, no overflow spilling past the track — the bar reports,
//  it does not react.
//

import SwiftUI

struct MeterBar: View {
    /// 0...1. Values above 1 are clamped by the caller's `fraction`.
    let fraction: Double
    var height: CGFloat = FTLMeter.rowHeight
    var fill: Color = FTLColor.textPrimary
    var showsBorder: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(FTLColor.track)
                Capsule()
                    .fill(fill)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .overlay {
            if showsBorder {
                Capsule().strokeBorder(FTLColor.hairline, lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }
}
