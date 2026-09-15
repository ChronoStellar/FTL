//
//  SplitBar.swift
//  FTL — view/DesignSystem/Components
//
//  A single bar divided into proportional segments — the income-split chart.
//  No hue distinguishes a segment: FTLColor is neutral greyscale plus exactly
//  one signal colour, and a segment isn't a warning or a signal, so it doesn't
//  get one either. Segments read apart the same way everything else in this
//  design system separates — an opacity ramp on one colour — matched to the
//  row order they're listed in underneath.
//

import SwiftUI

struct SplitBar: View {
    struct Segment: Identifiable {
        let id: CategoryID
        /// 0...1 of the bar's width.
        let fraction: Double
    }

    let segments: [Segment]
    var height: CGFloat = FTLMeter.heroHeight
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let gapWidth = spacing * CGFloat(max(0, segments.count - 1))
            let available = max(0, geometry.size.width - gapWidth)

            HStack(spacing: spacing) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Self.tone(index: index, of: segments.count))
                        .frame(width: available * max(0, segment.fraction))
                }
            }
        }
        .frame(height: height)
        .background(FTLColor.track, in: Capsule())
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    /// Full opacity for the first row, stepping down to ~0.3 for the last —
    /// distinguishable without ever reaching for a second hue.
    static func tone(index: Int, of count: Int) -> Color {
        guard count > 1 else { return FTLColor.textPrimary }
        let minOpacity = 0.3
        let step = (1.0 - minOpacity) / Double(count - 1)
        return FTLColor.textPrimary.opacity(1.0 - Double(index) * step)
    }
}
