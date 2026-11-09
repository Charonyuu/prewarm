import Foundation
import UserNotifications

enum NotificationService {
    private static var canPost: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorizationIfNeeded() {
        guard canPost else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts now, or at `date` when given (for quiet hours and reset reminders).
    static func post(id: String, title: String, body: String, at date: Date? = nil) {
        guard canPost else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        var trigger: UNNotificationTrigger?
        if let date {
            let interval = date.timeIntervalSinceNow
            if interval > 1 { trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false) }
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(_ ids: [String]) {
        guard canPost else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
