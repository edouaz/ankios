// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import UserNotifications

/// A single repeating daily "time to review" local notification.
///
/// ponytail: the body is static text, not the live due count — a live count
/// would need a BGTaskScheduler background refresh to recompute the queue
/// (roadmap UX backlog #14). Add that if the plain reminder isn't enough.
enum Notifications {
    private static let reminderID = "anki-daily-reminder"

    /// Reschedules (or cancels) the daily reminder. Returns whether a
    /// notification is now scheduled — false if the user is signed off it or
    /// denied permission, so the caller can flip its toggle back.
    @discardableResult
    static func update(enabled: Bool, at time: DateComponents) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        guard enabled else { return false }

        let granted =
            (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Time to review"
        content.body = "Your Anki cards are waiting."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(
            identifier: reminderID, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
