//
//  DailyBudgetWidget.swift
//  FTLWidgets
//
//  Widget showing budget of the day — daily allowance, today's spending, and remaining balance.
//

import WidgetKit
import SwiftUI

struct DailyBudgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyBudgetEntry {
        DailyBudgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyBudgetEntry) -> Void) {
        let snapshot = WidgetDataManager.shared.loadSnapshot()
        completion(DailyBudgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyBudgetEntry>) -> Void) {
        let snapshot = WidgetDataManager.shared.loadSnapshot()
        let entry = DailyBudgetEntry(date: .now, snapshot: snapshot)

        // Refresh at top of next hour or midnight
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct DailyBudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDataSnapshot
}

struct DailyBudgetWidgetView: View {
    var entry: DailyBudgetProvider.Entry
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
        .widgetURL(URL(string: "ftl://home"))
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("TODAY'S BUDGET")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(WidgetPalette.textTertiary)

                Spacer()

                if s.isOverDailyBudget {
                    Text("OVER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(WidgetPalette.signal)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WidgetPalette.signal.opacity(0.15), in: Capsule())
                } else {
                    Circle()
                        .fill(Color(white: 0.8))
                        .frame(width: 5, height: 5)
                }
            }

            Spacer(minLength: 4)

            // Main figure: Left Today
            Text(WidgetFormatter.rp(s.todayRemaining))
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(s.isOverDailyBudget ? WidgetPalette.signal : WidgetPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(s.isOverDailyBudget ? "over daily allowance" : "left today")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(WidgetPalette.textSecondary)

            Spacer(minLength: 8)

            // Progress Meter
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(WidgetPalette.track)
                        .frame(height: 5)

                    Capsule()
                        .fill(s.isOverDailyBudget ? WidgetPalette.signal : WidgetPalette.textPrimary)
                        .frame(width: max(4, geo.size.width * CGFloat(s.dailyProgress)), height: 5)
                }
            }
            .frame(height: 5)

            Spacer(minLength: 6)

            // Footer
            HStack {
                Text("Spent \(WidgetFormatter.compactRp(s.todaySpent))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(WidgetPalette.textTertiary)

                Spacer()

                Text("of \(WidgetFormatter.compactRp(s.dailyAllowance))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(WidgetPalette.textTertiary)
            }
        }
        .padding(14)
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        HStack(spacing: 12) {
            // Left Column: Today's Budget
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(s.isOverDailyBudget ? WidgetPalette.signal : Color.white)
                        .frame(width: 6, height: 6)
                    Text("BUDGET OF THE DAY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(WidgetPalette.textTertiary)
                }

                Spacer(minLength: 4)

                Text(WidgetFormatter.rp(s.todayRemaining))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(s.isOverDailyBudget ? WidgetPalette.signal : WidgetPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(s.isOverDailyBudget ? "over allowance" : "remaining today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.textSecondary)

                Spacer(minLength: 6)

                // Today's Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WidgetPalette.track).frame(height: 5)
                        Capsule()
                            .fill(s.isOverDailyBudget ? WidgetPalette.signal : WidgetPalette.textPrimary)
                            .frame(width: max(4, geo.size.width * CGFloat(s.dailyProgress)), height: 5)
                    }
                }
                .frame(height: 5)

                Spacer(minLength: 6)

                HStack {
                    Text("Spent: \(WidgetFormatter.compactRp(s.todaySpent))")
                    Spacer()
                    Text("Limit: \(WidgetFormatter.compactRp(s.dailyAllowance))")
                }
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WidgetPalette.textTertiary)
            }
            .padding(13)
            .background(WidgetPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(WidgetPalette.border, lineWidth: 0.5)
            }

            // Right Column: Month Standing
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(s.monthTitle.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(WidgetPalette.textTertiary)
                    Spacer()
                    Text("\(s.daysRemaining)d left")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(WidgetPalette.textSecondary)
                }

                Spacer(minLength: 4)

                Text(WidgetFormatter.compactRp(s.monthRemaining))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(s.isOverMonthCeiling ? WidgetPalette.signal : WidgetPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("month remaining")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.textSecondary)

                Spacer(minLength: 6)

                // Month progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WidgetPalette.track).frame(height: 5)
                        Capsule()
                            .fill(s.isOverMonthCeiling ? WidgetPalette.signal : Color(white: 0.7))
                            .frame(width: max(4, geo.size.width * CGFloat(s.monthProgress)), height: 5)
                    }
                }
                .frame(height: 5)

                Spacer(minLength: 6)

                HStack {
                    Text("Ceiling:")
                    Spacer()
                    Text(WidgetFormatter.compactRp(s.monthCeiling))
                }
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WidgetPalette.textTertiary)
            }
            .padding(13)
            .background(WidgetPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(WidgetPalette.border, lineWidth: 0.5)
            }
        }
        .padding(10)
    }

    // MARK: - Lock Screen Accessories

    private var accessoryCircularView: some View {
        Gauge(value: s.dailyProgress, in: 0...1) {
            Image(systemName: "banknote")
        } currentValueLabel: {
            Text(WidgetFormatter.compactRp(s.todayRemaining))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                Text("TODAY'S BUDGET")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }

            Text("\(WidgetFormatter.rp(s.todayRemaining)) left")
                .font(.system(size: 14, weight: .bold, design: .monospaced))

            Text("Spent \(WidgetFormatter.compactRp(s.todaySpent)) of \(WidgetFormatter.compactRp(s.dailyAllowance))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

struct DailyBudgetWidget: Widget {
    let kind: String = "FTLDailyBudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyBudgetProvider()) { entry in
            DailyBudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("Budget of the Day")
        .description("Keep track of your daily spending allowance and remaining budget.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

// MARK: - Shared Palette

enum WidgetPalette {
    static let ground = Color(red: 10/255, green: 11/255, blue: 14/255)
    static let panel = Color(red: 18/255, green: 20/255, blue: 26/255)
    static let panelRaised = Color(red: 26/255, green: 28/255, blue: 36/255)
    static let border = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.12)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let textTertiary = Color(white: 0.42)
    static let signal = Color(red: 255/255, green: 84/255, blue: 73/255)
}
