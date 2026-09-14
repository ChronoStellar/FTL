//
//  NotificationSchedule.swift
//  FTL — services/Capture
//
//  A reminder at an hour you pick, saying what is actually waiting.
//
//  `BackgroundRefresh` notifies when a fetch happens to land something, which is
//  whenever iOS felt like running it. This is the other half: a `UNCalendar`
//  trigger fires at a time you chose, every day, and unlike a background task
//  that is a promise the OS keeps.
//
//  ## The catch, and what is done about it
//
//  A calendar notification's text is fixed when it is SCHEDULED, not when it
//  fires. A reminder that hard-codes "3 waiting" would go on saying 3 after you
//  cleared the queue. So the digest is rescheduled every time the app learns the
//  count has changed — a queue settle, a sync, a background fetch, backgrounding
//  the app — and cancelled outright when the queue is empty, because the worst
//  version of this feature is one that pings you daily about nothing.
//
//  That leaves one honest gap: approve everything on another device, or let the
//  queue drain in a way the app never observes, and tomorrow's reminder quotes a
//  number that was true when it was written. It says "as of" nothing and stays
//  vague enough not to lie about it.
//

import Foundation
import UserNotifications

@MainActor
enum NotificationSchedule {

    /// Distinct from the fetch notification's ids so rescheduling this one never
    /// cancels a "just landed" alert, and vice versa.
    private static let digestID = "ftl.digest.daily"

    private static let enabledKey = "dailyDigestEnabled"
    private static let hourKey = "dailyDigestHour"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 24-hour. Defaults to 20:00 — the end of a spending day, when there is
    /// something to review and time to review it.
    static var hour: Int {
        get {
            guard UserDefaults.standard.object(forKey: hourKey) != nil else { return 20 }
            return UserDefaults.standard.integer(forKey: hourKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: hourKey) }
    }

    /// Hours offered. A quarter-hourly picker for a daily nudge is precision
    /// nobody needs and a longer list to scroll.
    static let selectableHours = [7, 8, 9, 12, 17, 18, 19, 20, 21, 22]

    static func label(forHour hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }

    // MARK: - Scheduling

    /// Re-points the daily reminder at the current queue. Safe to call often —
    /// adding a request with an existing identifier replaces it.
    static func refreshDigest(pendingCount: Int) async {
        let centre = UNUserNotificationCenter.current()
        centre.removePendingNotificationRequests(withIdentifiers: [digestID])

        // Nothing waiting means nothing to say. A daily reminder that fires on
        // an empty queue teaches people to ignore it, and then it is not there
        // on the day it matters.
        guard isEnabled, pendingCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = pendingCount == 1 ? "1 charge to approve" : "\(pendingCount) charges to approve"
        // Same restraint as the fetch notification: a count, never an amount or
        // a merchant. This is a lock screen.
        content.body = "Nothing counts against a bucket until you approve it."
        content.sound = .default

        var when = DateComponents()
        when.hour = hour
        when.minute = 0

        let request = UNNotificationRequest(
            identifier: digestID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        )
        try? await centre.add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [digestID])
    }
}
