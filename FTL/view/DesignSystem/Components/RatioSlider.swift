//
//  RatioSlider.swift
//  FTL — view/DesignSystem/Components
//
//  A percentage, dragged. Used by the income split, where every row is a share
//  of one number.
//
//  Not `Slider`. The system control brings its own track, its own knob and its
//  own idea of a tint, and sat next to the 3pt hairline meters this app is made
//  of it read as a component borrowed from a different program. This is
//  `MeterBar` with somewhere to put your thumb: same track token, same fill,
//  same height. The bar a row shows you and the bar you drag are the same bar.
//
//  The knob is the fill's own colour rather than a contrasting one — there is
//  no second hue to reach for, and a lollipop end reads as a handle without
//  needing one.
//

import SwiftUI

struct RatioSlider: View {
    /// 0...100. Clamping belongs to the caller's model, which has to keep the
    /// whole split summing to 100 anyway — this only reports where the thumb is.
    let value: Int
    var tint: Color = FTLColor.textPrimary
    var label: String = ""
    let onChange: (Int) -> Void

    private static let knob: CGFloat = 16
    /// One VoiceOver swipe. Larger than a pixel of drag, because an adjustable
    /// action that moves 1% needs forty swipes to cross the control.
    private static let adjustStep = 5

    var body: some View {
        GeometryReader { geometry in
            // The knob's centre travels between its own edges, never past
            // them, so 0% and 100% sit flush with the ends of the track
            // instead of half a knob outside it.
            let travel = max(1, geometry.size.width - Self.knob)
            let offset = travel * CGFloat(min(max(value, 0), 100)) / 100

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(FTLColor.track)
                    .frame(height: FTLMeter.heroHeight)
                Capsule()
                    .fill(tint)
                    .frame(width: offset + Self.knob / 2, height: FTLMeter.heroHeight)
                Circle()
                    .fill(tint)
                    .frame(width: Self.knob, height: Self.knob)
                    .offset(x: offset)
            }
            .frame(maxHeight: .infinity)
            // The whole strip, not the knob: a 16pt target is half of Apple's
            // minimum, and a tap anywhere on the track should jump to it.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let position = (drag.location.x - Self.knob / 2) / travel
                        onChange(Int((position * 100).rounded()))
                    }
            )
        }
        .frame(height: FTLSpacing.minTapTarget)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(value) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(value + Self.adjustStep)
            case .decrement: onChange(value - Self.adjustStep)
            @unknown default: break
            }
        }
    }
}
