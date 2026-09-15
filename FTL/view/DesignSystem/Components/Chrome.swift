//
//  Chrome.swift
//  FTL — view/DesignSystem/Components
//
//  Background glows, section labels, chips and steppers — the small recurring
//  pieces of the design canvas.
//

import SwiftUI

/// The app background. Formerly two radial glows — removed: they were the single
/// loudest thing on screen and carried no information.
struct GlowBackground: View {
    var body: some View {
        FTLColor.ground.ignoresSafeArea()
    }
}

/// "BUCKETS", "RECENT", "CEILING" — uppercase monospaced with wide tracking.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(FTLTypography.sectionLabel)
            .tracking(FTLTypography.sectionTracking)
            .foregroundStyle(FTLColor.textQuaternary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A selectable pill. Selected inverts to a light fill, matching the canvas.
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    var isCompact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isCompact ? FTLTypography.chipSmall : FTLTypography.chip)
                .foregroundStyle(isSelected ? FTLColor.onLight : FTLColor.textPrimary)
                .padding(.horizontal, isCompact ? 13 : FTLSpacing.lg)
                .frame(minHeight: isCompact ? 38 : FTLSpacing.minTapTarget)
                .background(
                    isSelected ? FTLColor.textPrimary : FTLColor.glassFill,
                    in: Capsule()
                )
                .overlay {
                    Capsule().strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The −/+ pair used to adjust a ceiling or a goal.
struct StepperPair: View {
    let label: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            stepButton("minus", label: "Decrease \(label)", action: onDecrement)
            stepButton("plus", label: "Increase \(label)", action: onIncrement)
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(FTLColor.textPrimary)
                .frame(width: FTLSpacing.minTapTarget, height: FTLSpacing.minTapTarget)
                .background(FTLColor.controlFill, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous)
                        .strokeBorder(FTLColor.controlBorder, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A row in one of the opaque panels, with the design's hairline divider.
struct PanelRow<Content: View>: View {
    var showsDivider: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, FTLSpacing.rowPadding)
                .padding(.vertical, FTLSpacing.md)
                .frame(minHeight: 58)
            if showsDivider {
                Rectangle()
                    .fill(FTLColor.separator)
                    .frame(height: 0.5)
                    .padding(.leading, FTLSpacing.rowPadding)
            }
        }
    }
}
