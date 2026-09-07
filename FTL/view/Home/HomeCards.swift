//
//  HomeCards.swift
//  FTL — view/Home
//
//  The home screen's cards and rows.
//

import SwiftUI

// MARK: - Hero

/// Total spend against the month's ceiling. The screen's one large figure.
///
/// Not a card. The most important number on the screen doesn't need a container
/// to say so — the type size already does, and boxing it just adds an edge to
/// look at. It sits on the ground with a thin rule under it.
struct SpendHeroCard: View {
    let spent: Money
    let ceiling: Money
    let fraction: Double
    let isOverCeiling: Bool
    let percentLabel: String
    let remainingLabel: String
    let perDayLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Spent of \(MoneyFormatter.rp(ceiling))")

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(MoneyFormatter.grouped(spent))
                    .font(FTLTypography.display)
                    .tracking(FTLTypography.displayTracking)
                    .foregroundStyle(FTLColor.textPrimary)
                Text(percentLabel)
                    .font(FTLTypography.amountSmall)
                    .foregroundStyle(FTLColor.textQuaternary)
            }
            .padding(.top, FTLSpacing.sm)

            MeterBar(
                fraction: fraction,
                height: FTLMeter.heroHeight,
                fill: isOverCeiling ? FTLColor.budgetOverCeiling : FTLColor.textPrimary
            )
            .padding(.top, FTLSpacing.lg)
            .padding(.bottom, FTLSpacing.md)

            // Both lines are long in IDR. Shrink rather than wrap: a wrapped
            // "left over N days" pushes the per-day figure out of alignment
            // with the hero above it.
            HStack(alignment: .firstTextBaseline) {
                Text(remainingLabel)
                    .font(FTLTypography.caption)
                    .foregroundStyle(FTLColor.textSecondary)
                Spacer(minLength: FTLSpacing.sm)
                Text(perDayLabel)
                    .font(FTLTypography.amountSmall)
                    .foregroundStyle(FTLColor.textPrimary)
                    .layoutPriority(1)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(MoneyFormatter.rp(spent)) spent of \(MoneyFormatter.rp(ceiling)). \(remainingLabel).")
    }
}

// MARK: - Queue

/// Entry point to the approval sheet. States the value sitting outside the
/// totals, not just the count — Invariant 7 made visible on the main screen.
struct QueueCard: View {
    let count: Int
    let title: String
    let total: Money
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FTLSpacing.md) {
                Text("\(count)")
                    .font(FTLTypography.amountSmall)
                    .foregroundStyle(FTLColor.textPrimary)
                    .frame(minWidth: 26, minHeight: 26)
                    .padding(.horizontal, 7)
                    .background(FTLColor.controlFill, in: Capsule())
                    .overlay { Capsule().strokeBorder(FTLColor.controlBorder, lineWidth: 0.5) }

                VStack(alignment: .leading, spacing: FTLSpacing.xxs) {
                    Text(title)
                        .font(FTLTypography.body)
                        .foregroundStyle(FTLColor.textPrimary)
                    Text("\(MoneyFormatter.rp(total)) not counted yet")
                        .font(FTLTypography.captionSmall)
                        .foregroundStyle(FTLColor.textSecondary)
                }

                Spacer(minLength: FTLSpacing.sm)
                Chevron()
            }
            .padding(.horizontal, FTLSpacing.rowPadding)
            .padding(.vertical, FTLSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FTLColor.panel, in: RoundedRectangle(cornerRadius: FTLRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FTLRadius.panel, style: .continuous)
                    .strokeBorder(FTLColor.hairline, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bucket

struct BucketRow: View {
    let position: BudgetPosition
    var showsDivider: Bool = true
    let action: () -> Void

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
                            Spacer(minLength: FTLSpacing.sm)
                            Text(MoneyFormatter.standing(remaining: position.remaining))
                                .font(FTLTypography.amountSmall)
                                .foregroundStyle(
                                    position.standing == .overCeiling
                                        ? FTLColor.budgetOverCeiling
                                        : FTLColor.textQuaternary
                                )
                        }
                        MeterBar(fraction: fractionOfCeiling, fill: fill)
                    }
                    Chevron()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var fractionOfCeiling: Double {
        guard position.node.ceiling.minorUnits > 0 else { return 0 }
        return Double(position.actual.minorUnits) / Double(position.node.ceiling.minorUnits)
    }
}

// MARK: - Goal

struct GoalCard: View {
    let goal: SavingsGoal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PanelCard {
                PanelRow(showsDivider: false) {
                    HStack(spacing: FTLSpacing.md) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(goal.name)
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Text("\(MoneyFormatter.perDay(goal.dailyRate())) · \(MoneyFormatter.grouped(goal.remaining)) to go")
                                .font(FTLTypography.captionSmall)
                                .foregroundStyle(FTLColor.textQuaternary)
                                .padding(.top, 3)
                            MeterBar(fraction: goal.fraction, fill: FTLColor.textTertiary)
                                .padding(.top, 10)
                        }
                        Chevron()
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ledger

struct LedgerRow: View {
    let transaction: LedgerTransaction
    var showsAccent: Bool = false
    var showsDivider: Bool = true
    var onDelete: (() -> Void)? = nil

    @State private var showingDeleteConfirmation = false

    var body: some View {
        PanelRow(showsDivider: showsDivider) {
            HStack(spacing: FTLSpacing.md) {
                if showsAccent {
                    Capsule()
                        .fill(FTLColor.forKind(transaction.kind))
                        .frame(width: 3, height: 32)
                }
                VStack(alignment: .leading, spacing: FTLSpacing.xxs) {
                    Text(transaction.merchant ?? transaction.merchantRaw)
                        .font(FTLTypography.rowTitleTight)
                        .foregroundStyle(FTLColor.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(FTLTypography.captionSmall)
                        .foregroundStyle(FTLColor.textQuaternary)
                        .lineLimit(1)
                }
                Spacer(minLength: FTLSpacing.sm)
                Text(MoneyFormatter.grouped(transaction.amount))
                    .font(FTLTypography.amount)
                    .foregroundStyle(FTLColor.forKind(transaction.kind))

                if onDelete != nil {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(FTLColor.textDisabled)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                if onDelete != nil {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Transaction", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog(
                "Delete Transaction?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove \"\(transaction.merchant ?? transaction.merchantRaw)\" (\(MoneyFormatter.rp(transaction.amount))) from your Google Sheet.")
            }
        }
    }

    /// "Food · email · today" — bucket, rail, and when.
    private var subtitle: String {
        var parts: [String] = []
        if let category = transaction.categoryID { parts.append(category.rawValue.capitalized) }
        parts.append(transaction.source.rawValue)
        parts.append(transaction.date.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Shared

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(FTLColor.textDisabled)
    }
}
