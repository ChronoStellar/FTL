import Foundation

let file = "FTL/view/Home/HomeCards.swift"
var content = try String(contentsOfFile: file)

let search = """
                        HStack(alignment: .firstTextBaseline) {
                            Text(position.node.name)
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(isEmergency ? .red : isUnallocated ? FTLColor.textSecondary : FTLColor.textPrimary)
                            Spacer(minLength: FTLSpacing.sm)
                            Text(MoneyFormatter.standing(remaining: position.remaining))
                                .font(FTLTypography.amountSmall)
                                .foregroundStyle(
                                    position.standing == .overCeiling
                                        ? FTLColor.budgetOverCeiling
                                        : FTLColor.textQuaternary
                                )
                        }
"""
let replace = """
                        HStack(alignment: .firstTextBaseline) {
                            Text(position.node.name)
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(isEmergency ? .red : isUnallocated ? FTLColor.textSecondary : FTLColor.textPrimary)
                            Spacer(minLength: FTLSpacing.sm)
                            Text(isEmergency ? MoneyFormatter.grouped(position.actual) : MoneyFormatter.standing(remaining: position.remaining))
                                .font(FTLTypography.amountSmall)
                                .foregroundStyle(
                                    isEmergency ? .red :
                                    (position.standing == .overCeiling
                                        ? FTLColor.budgetOverCeiling
                                        : FTLColor.textQuaternary)
                                )
                        }
"""
content = content.replacingOccurrences(of: search, with: replace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
