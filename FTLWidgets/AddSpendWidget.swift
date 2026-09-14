//
//  AddSpendWidget.swift
//  FTLWidgets
//
//  Widget for quickly adding spending with shortcut amounts and direct keypad access.
//

import WidgetKit
import SwiftUI

struct AddSpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> AddSpendEntry {
        AddSpendEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (AddSpendEntry) -> Void) {
        let snapshot = WidgetDataManager.shared.loadSnapshot()
        completion(AddSpendEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AddSpendEntry>) -> Void) {
        let snapshot = WidgetDataManager.shared.loadSnapshot()
        let entry = AddSpendEntry(date: .now, snapshot: snapshot)

        // Refresh periodically
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now.addingTimeInterval(7200)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct AddSpendEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDataSnapshot
}

struct AddSpendWidgetView: View {
    var entry: AddSpendProvider.Entry
    @Environment(\.widgetFamily) var family

    private var s: WidgetDataSnapshot { entry.snapshot }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .accessoryCircular:
                accessoryCircularView
            case .accessoryRectangular:
                accessoryRectangularView
            default:
                smallView
            }
        }
        .containerBackground(WidgetPalette.ground, for: .widget)
    }

    // MARK: - Small Widget

    private var smallView: some View {
        Link(destination: URL(string: "ftl://add")!) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("FTL")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(WidgetPalette.textTertiary)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white)
                }

                Spacer(minLength: 4)

                // Large center action button
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(WidgetPalette.panelRaised)
                            .frame(width: 48, height: 48)
                            .overlay {
                                Circle().strokeBorder(WidgetPalette.border, lineWidth: 1)
                            }
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }

                    Text("Add Spend")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(WidgetPalette.textPrimary)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 6)

                // Footer showing remaining context
                HStack {
                    Text("\(WidgetFormatter.compactRp(s.todayRemaining)) left today")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(WidgetPalette.textTertiary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .padding(14)
        }
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        HStack(spacing: 12) {
            // Left column: Direct Add button
            Link(destination: URL(string: "ftl://add")!) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("FTL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(WidgetPalette.textTertiary)
                        Spacer()
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 40, height: 40)
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.black)
                    }

                    Text("Add Spend")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)

                    Text("Tap to open keypad")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(WidgetPalette.textSecondary)

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(WidgetPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(WidgetPalette.border, lineWidth: 0.5)
                }
            }

            // Right column: Quick amount presets
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK PRESETS")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(WidgetPalette.textTertiary)

                // Quick buttons
                VStack(spacing: 6) {
                    presetButton(amount: 25000, label: "+ Rp 25.000")
                    presetButton(amount: 50000, label: "+ Rp 50.000")
                    presetButton(amount: 100000, label: "+ Rp 100.000")
                }

                Spacer(minLength: 0)

                HStack {
                    Text("Today:")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(WidgetPalette.textTertiary)
                    Text("\(WidgetFormatter.compactRp(s.todayRemaining)) left")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(s.isOverDailyBudget ? WidgetPalette.signal : WidgetPalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WidgetPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(WidgetPalette.border, lineWidth: 0.5)
            }
        }
        .padding(10)
    }

    private func presetButton(amount: Int, label: String) -> some View {
        Link(destination: URL(string: "ftl://add?amount=\(amount)")!) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WidgetPalette.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(WidgetPalette.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(WidgetPalette.border, lineWidth: 0.5)
            }
        }
    }

    // MARK: - Lock Screen Accessories

    private var accessoryCircularView: some View {
        Link(destination: URL(string: "ftl://add")!) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
            }
        }
    }

    private var accessoryRectangularView: some View {
        Link(destination: URL(string: "ftl://add")!) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text("ADD SPEND")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("Open keypad")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AddSpendWidget: Widget {
    let kind: String = "FTLAddSpendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AddSpendProvider()) { entry in
            AddSpendWidgetView(entry: entry)
        }
        .configurationDisplayName("Add Spending")
        .description("Quickly log a new transaction with presets or open the keypad.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
