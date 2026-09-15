//
//  Saucer.swift
//  FTL — view/DesignSystem/Components
//
//  The app icon is a flying saucer. This is that saucer as a line drawing, and
//  it is the only piece of iconography the app has.
//
//  Drawn, not bundled. A PNG would need one asset per size and would carry its
//  own colour into a palette that has exactly one hue in it; a `Shape` takes an
//  `FTLColor` token like everything else and keeps a hairline stroke at 16pt and
//  at 80pt alike.
//
//  Used in four places and deliberately nowhere else — the wordmark, the sign-in
//  hero, the loading indicator, and the queue's empty state. Three of those are
//  spots the app already spent a mark on or had nothing in at all, which is the
//  test: the saucer is never added ON TOP of information.
//
//  The exception, and the reason this file is more than a glyph: `BeamActivity`.
//  What the app does is lift rows out of a mailbox nobody opened, so the beam is
//  the literal description of the wait, not a mascot for it. It replaces a
//  spinner — same job, same restraint, one fewer generic control.
//

import SwiftUI

// MARK: - Geometry

/// One 24-unit design box, shared by every mark in this file, so the saucer, the
/// beam and the rungs climbing it always line up when stacked.
///
/// `nonisolated` for the same reason everything in `model/` is: the target
/// defaults to `MainActor`, and `Shape.path(in:)` is a nonisolated requirement,
/// so a main-actor box read from a nonisolated path builder is a warning here
/// and an error under Swift 6.
private nonisolated enum Saucer {

    // The rim seen edge-on, and the dome sitting in it.
    static let rim = CGRect(x: 1.5, y: 7, width: 21, height: 6)
    static let centre = CGPoint(x: 12, y: 10)
    static let domeRadius: CGFloat = 5.5

    /// Radial divisions on the near half of the rim — the icon's segmented
    /// underside, reduced to four ticks. Dropped below `FTLMark.panelThreshold`,
    /// where they close into a smudge.
    static let panelOffsets: [CGFloat] = [-7.6, -3.2, 3.2, 7.6]

    static let beamTop: CGFloat = 13.6
    static let beamBottom: CGFloat = 23
    static let beamTopHalfWidth: CGFloat = 3.2
    /// Splayed hard on purpose. At the first, narrower angle the two sides read
    /// as landing legs rather than as light — a tripod under a saucer, which is
    /// a different picture entirely.
    static let beamBottomHalfWidth: CGFloat = 9.6

    /// The INKED extent, which is not the design box: the box has slack above
    /// the dome and below the beam, and a mark that doesn't fill its frame
    /// floats inside it.
    static func bounds(showsBeam: Bool) -> CGRect {
        CGRect(x: 1.5, y: 4.5, width: 21, height: showsBeam ? 18.5 : 8.5)
    }

    /// Aspect-fit the inked box into `rect`, centred.
    static func transform(into rect: CGRect, showsBeam: Bool) -> CGAffineTransform {
        let box = bounds(showsBeam: showsBeam)
        let scale = min(rect.width / box.width, rect.height / box.height)
        let drawn = CGSize(width: box.width * scale, height: box.height * scale)
        return CGAffineTransform(
            translationX: rect.minX + (rect.width - drawn.width) / 2,
            y: rect.minY + (rect.height - drawn.height) / 2
        )
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -box.minX, y: -box.minY)
    }

    /// Where the dome meets the rim, so the arc has no ends dangling inside the
    /// ellipse. Solved rather than eyeballed, so changing a radius above doesn't
    /// quietly open a gap.
    static var domeSweep: (start: Angle, end: Angle) {
        let rx = rim.width / 2, ry = rim.height / 2, r = domeRadius
        let ySquared = (1 - (r * r) / (rx * rx)) / (1 / (ry * ry) - 1 / (rx * rx))
        let y = -sqrt(max(0, ySquared))                       // the upper crossing
        let x = sqrt(max(0, r * r - y * y))
        return (.radians(atan2(y, -x)), .radians(atan2(y, x)))
    }

    static func beamY(at t: CGFloat) -> CGFloat { beamTop + (beamBottom - beamTop) * t }

    /// Half the beam's width at `t` — 0 at the saucer, 1 at the floor.
    static func beamHalfWidth(at t: CGFloat) -> CGFloat {
        beamTopHalfWidth + (beamBottomHalfWidth - beamTopHalfWidth) * t
    }
}

// MARK: - Shapes

/// The saucer itself: dome, rim, optional rim panels, optional beam.
nonisolated struct SaucerShape: Shape {
    var showsPanels = true
    var showsBeam = false

    /// Width ÷ height of the inked extent, so a caller sizes a frame the mark
    /// fills exactly instead of one it floats in.
    static func aspectRatio(showsBeam: Bool) -> CGFloat {
        let box = Saucer.bounds(showsBeam: showsBeam)
        return box.width / box.height
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let sweep = Saucer.domeSweep
        path.addArc(
            center: Saucer.centre,
            radius: Saucer.domeRadius,
            startAngle: sweep.start,
            endAngle: sweep.end,
            clockwise: false
        )
        path.addEllipse(in: Saucer.rim)

        if showsPanels {
            let rx = Saucer.rim.width / 2, ry = Saucer.rim.height / 2
            for dx in Saucer.panelOffsets {
                let drop = ry * sqrt(max(0, 1 - (dx / rx) * (dx / rx)))
                path.move(to: CGPoint(x: Saucer.centre.x + dx, y: Saucer.centre.y))
                path.addLine(to: CGPoint(x: Saucer.centre.x + dx, y: Saucer.centre.y + drop))
            }
        }

        if showsBeam {
            for side in [CGFloat(-1), 1] {
                path.move(to: CGPoint(
                    x: Saucer.centre.x + side * Saucer.beamTopHalfWidth,
                    y: Saucer.beamTop
                ))
                path.addLine(to: CGPoint(
                    x: Saucer.centre.x + side * Saucer.beamBottomHalfWidth,
                    y: Saucer.beamBottom
                ))
            }
        }

        return path.applying(Saucer.transform(into: rect, showsBeam: showsBeam))
    }
}

/// One horizontal rule inside the beam. `t` is 0 at the saucer, 1 at the floor.
///
/// Deliberately NOT `Animatable`. `TimelineView(.animation)` hands every redraw
/// an implicit animation, so a `t` that SwiftUI is allowed to interpolate gets
/// eased — and overshot — between frames: rungs drew above the beam's mouth at
/// a width belonging to a different position entirely, since `path` reads the
/// interpolated `t` for both. The timeline already supplies a value per frame.
/// There is nothing here for an animation curve to add.
nonisolated struct BeamRung: Shape {
    var t: CGFloat

    func path(in rect: CGRect) -> Path {
        let half = max(0, Saucer.beamHalfWidth(at: t) - 0.9)   // clear of the beam's edges
        let y = Saucer.beamY(at: t)
        var path = Path()
        path.move(to: CGPoint(x: Saucer.centre.x - half, y: y))
        path.addLine(to: CGPoint(x: Saucer.centre.x + half, y: y))
        return path.applying(Saucer.transform(into: rect, showsBeam: true))
    }
}

// MARK: - The mark

/// The saucer, sized and tinted. Still — see `BeamActivity` for the one that moves.
struct FTLMark: View {
    var width: CGFloat = FTLMarkSize.wordmark
    var tint: Color = FTLColor.textTertiary
    var showsBeam = false
    var lineWidth: CGFloat = 1.1

    /// Two faint rules inside the beam. Without them the sides are just two
    /// lines and the eye takes them for legs; with them the shape is lit.
    private static let stillRungs: [CGFloat] = [0.42, 0.78]

    /// Below this the four rim panels stop being four lines and start being a
    /// thicker rim, so they come off.
    static let panelThreshold: CGFloat = 34

    var body: some View {
        ZStack {
            SaucerShape(showsPanels: width >= Self.panelThreshold, showsBeam: showsBeam)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            if showsBeam {
                ForEach(Self.stillRungs, id: \.self) { t in
                    BeamRung(t: t)
                        .stroke(tint.opacity(0.55), lineWidth: lineWidth)
                }
            }
        }
        .frame(width: width, height: width / SaucerShape.aspectRatio(showsBeam: showsBeam))
        .accessibilityHidden(true)
    }
}

// MARK: - Loading

/// The app's loading indicator on any screen that has nothing else on it yet.
///
/// A spinner says "waiting". This says what the wait is FOR: rungs climb the
/// beam because the thing happening is mail being lifted out of a mailbox the
/// user never opened. It is the only animation in the app, it is monochrome and
/// made of the same thin rules as every meter, and it stops the moment there is
/// real content to look at.
///
/// It respects Reduce Motion by holding the rungs still rather than by falling
/// back to a spinner — the picture is the same either way.
struct BeamActivity: View {
    var width: CGFloat = FTLMarkSize.activity
    var tint: Color = FTLColor.textTertiary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rungCount = 3
    /// Seconds for one rung to travel the beam.
    private static let period: Double = 1.8

    var body: some View {
        // The timeline wraps the WHOLE stack rather than sitting inside it.
        // Inverted, it proposes an unspecified size to its content, and a
        // `Shape` handed no proposal falls back to its 10×10 ideal — so the
        // rungs drew into a tiny box at the centre while the saucer around
        // them filled the frame, and nothing lined up with anything.
        Group {
            if reduceMotion {
                marks(phase: 0)
            } else {
                TimelineView(.animation) { context in
                    marks(phase: context.date.timeIntervalSinceReferenceDate / Self.period)
                }
            }
        }
        .frame(width: width, height: width / SaucerShape.aspectRatio(showsBeam: true))
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    private func marks(phase: Double) -> some View {
        ZStack {
            SaucerShape(showsPanels: width >= FTLMark.panelThreshold, showsBeam: true)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            rungs(phase: phase)
        }
    }

    private func rungs(phase: Double) -> some View {
        ForEach(0..<Self.rungCount, id: \.self) { index in
            // 0 as the rung leaves the floor, 1 as it reaches the saucer.
            let offset = phase + Double(index) / Double(Self.rungCount)
            let climbed = offset - offset.rounded(.down)
            BeamRung(t: CGFloat(1 - climbed))
                // Fades in off the floor and out under the rim, so nothing
                // pops into or out of existence mid-beam.
                .stroke(tint.opacity(sin(.pi * climbed) * 0.75), lineWidth: 1.2)
        }
    }
}
