import Foundation

let file = "FTL/view/Home/HomeCards.swift"
var content = try String(contentsOfFile: file)

let search = """
    private var isUnallocated: Bool { position.id == .unallocated }

    private var fill: Color {
        if isUnallocated { return FTLColor.unallocated }
        return position.standing == .overCeiling ? FTLColor.budgetOverCeiling : FTLColor.textPrimary
    }

    var body: some View {
        Button(action: action) {
            PanelRow(showsDivider: showsDivider) {
                HStack(spacing: FTLSpacing.md) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(position.node.name)
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(isUnallocated ? FTLColor.textSecondary : FTLColor.textPrimary)
"""

let replace = """
    private var isUnallocated: Bool { position.id == .unallocated }
    private var isEmergency: Bool { position.id == .emergency }

    private var fill: Color {
        if isEmergency { return .red }
        if isUnallocated { return FTLColor.unallocated }
        return position.standing == .overCeiling ? FTLColor.budgetOverCeiling : FTLColor.textPrimary
    }

    var body: some View {
        Button(action: action) {
            PanelRow(showsDivider: showsDivider) {
                HStack(spacing: FTLSpacing.md) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(position.node.name)
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(isEmergency ? .red : isUnallocated ? FTLColor.textSecondary : FTLColor.textPrimary)
"""
content = content.replacingOccurrences(of: search, with: replace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
