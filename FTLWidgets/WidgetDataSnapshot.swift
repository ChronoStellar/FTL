//
//  WidgetDataSnapshot.swift
//  FTLWidgets
//
//  Shared data snapshot and storage manager for FTL widgets.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public struct WidgetDataSnapshot: Codable, Sendable {
    public let updatedAt: Date
    public let dailyAllowance: Int         // e.g. 230000 (Rp 230.000 / day)
    public let todaySpent: Int             // e.g. 45000 (Rp 45.000 spent today)
    public let todayRemaining: Int         // e.g. 185000 (Rp 185.000 left today)
    public let monthRemaining: Int         // e.g. 2068000 (Rp 2.068.000 left)
    public let monthCeiling: Int           // e.g. 3000000 (Rp 3.000.000)
    public let daysRemaining: Int          // e.g. 9 days
    public let monthTitle: String          // e.g. "September"
    public let currencyCode: String        // "IDR"
    public let isOverDailyBudget: Bool     // true if todaySpent > dailyAllowance
    public let isOverMonthCeiling: Bool    // true if monthRemaining <= 0
    public let pendingApprovalCount: Int   // charges waiting in approval queue
    public let topBuckets: [WidgetBucket]  // top buckets for quick logging

    public init(
        updatedAt: Date = .now,
        dailyAllowance: Int,
        todaySpent: Int,
        todayRemaining: Int,
        monthRemaining: Int,
        monthCeiling: Int,
        daysRemaining: Int,
        monthTitle: String,
        currencyCode: String = "IDR",
        isOverDailyBudget: Bool = false,
        isOverMonthCeiling: Bool = false,
        pendingApprovalCount: Int = 0,
        topBuckets: [WidgetBucket] = []
    ) {
        self.updatedAt = updatedAt
        self.dailyAllowance = dailyAllowance
        self.todaySpent = todaySpent
        self.todayRemaining = todayRemaining
        self.monthRemaining = monthRemaining
        self.monthCeiling = monthCeiling
        self.daysRemaining = daysRemaining
        self.monthTitle = monthTitle
        self.currencyCode = currencyCode
        self.isOverDailyBudget = isOverDailyBudget
        self.isOverMonthCeiling = isOverMonthCeiling
        self.pendingApprovalCount = pendingApprovalCount
        self.topBuckets = topBuckets
    }

    public var dailyProgress: Double {
        guard dailyAllowance > 0 else { return 0 }
        return min(1.0, max(0.0, Double(todaySpent) / Double(dailyAllowance)))
    }

    public var monthProgress: Double {
        guard monthCeiling > 0 else { return 0 }
        let spent = max(0, monthCeiling - monthRemaining)
        return min(1.0, max(0.0, Double(spent) / Double(monthCeiling)))
    }

    public static var placeholder: WidgetDataSnapshot {
        WidgetDataSnapshot(
            updatedAt: .now,
            dailyAllowance: 250000,
            todaySpent: 45000,
            todayRemaining: 205000,
            monthRemaining: 2150000,
            monthCeiling: 3500000,
            daysRemaining: 12,
            monthTitle: "September",
            currencyCode: "IDR",
            isOverDailyBudget: false,
            isOverMonthCeiling: false,
            pendingApprovalCount: 2,
            topBuckets: [
                WidgetBucket(id: "food", name: "Food"),
                WidgetBucket(id: "coffee", name: "Coffee"),
                WidgetBucket(id: "transport", name: "Transport")
            ]
        )
    }
}

public struct WidgetBucket: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum WidgetFormatter {
    public static func rp(_ minorUnits: Int) -> String {
        let absVal = abs(minorUnits)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        let formatted = formatter.string(from: NSNumber(value: absVal)) ?? "\(absVal)"
        let sign = minorUnits < 0 ? "-" : ""
        return "\(sign)Rp \(formatted)"
    }

    public static func compactRp(_ minorUnits: Int) -> String {
        let absVal = abs(minorUnits)
        if absVal >= 1_000_000 {
            let millions = Double(absVal) / 1_000_000.0
            let formatted = String(format: "%.1fM", millions).replacingOccurrences(of: ".0M", with: "M")
            let sign = minorUnits < 0 ? "-" : ""
            return "\(sign)Rp \(formatted)"
        } else if absVal >= 1_000 {
            let thousands = absVal / 1_000
            let sign = minorUnits < 0 ? "-" : ""
            return "\(sign)Rp \(thousands)k"
        }
        return rp(minorUnits)
    }
}

public final class WidgetDataManager: Sendable {
    public static let shared = WidgetDataManager()
    public static let appGroupID = "group.hend-aml.FTL"
    private static let snapshotKey = "ftl_widget_snapshot_data"

    private init() {}

    /// Nil when the App Group is missing from the target's entitlements.
    ///
    /// This used to be `?? .standard`, and that fallback is what kept the
    /// widgets showing `placeholder` for their whole existence: the app wrote a
    /// real snapshot into its OWN standard defaults, the widget extension — a
    /// separate process with a separate container — read its own and found
    /// nothing, and every screen involved looked like it was working. A shared
    /// store that silently stops being shared is worse than one that fails.
    ///
    /// Now nil, so `loadSnapshot` still degrades to the placeholder (a widget
    /// must render something) but `saveSnapshot` reports rather than pretending.
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupID)
    }

    /// True when the App Group is wired up. Surfaced in Settings → Home Screen
    /// Widgets so a broken group is visible somewhere other than a stale widget.
    public var isSharedStoreAvailable: Bool { sharedDefaults != nil }

    public func loadSnapshot() -> WidgetDataSnapshot {
        if let data = sharedDefaults?.data(forKey: Self.snapshotKey),
           let snapshot = try? JSONDecoder().decode(WidgetDataSnapshot.self, from: data) {
            return snapshot
        }
        return .placeholder
    }

    @discardableResult
    public func saveSnapshot(_ snapshot: WidgetDataSnapshot) -> Bool {
        guard let sharedDefaults, let data = try? JSONEncoder().encode(snapshot) else {
            return false
        }
        sharedDefaults.set(data, forKey: Self.snapshotKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return true
    }
}
