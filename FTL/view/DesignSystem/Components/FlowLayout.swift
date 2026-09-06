//
//  FlowLayout.swift
//  FTL — view/DesignSystem/Components
//
//  Wrapping row of chips. SwiftUI has no built-in flow container, and an HStack
//  either overflows or truncates — neither is acceptable for the tag rows, where
//  every option has to stay reachable.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } +
            lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: maxWidth == .infinity ? rows.map(\.width).max() ?? 0 : maxWidth,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.append(index, size: size)
            } else {
                current.append(index, size: size, spacing: current.indices.isEmpty ? 0 : spacing)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    private struct Row {
        var indices: [Subviews.Index] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(_ index: Subviews.Index, size: CGSize, spacing: CGFloat = 0) {
            indices.append(index)
            width += spacing + size.width
            height = max(height, size.height)
        }
    }
}
