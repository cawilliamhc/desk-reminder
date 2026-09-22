import AppKit
import UserNotifications

/// Native notifications, with buttons - the reason the app needed to become a
/// real bundle rather than a script calling osascript.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    enum Action: String {
        case snooze = "SNOOZE"
        case pauseToday = "PAUSE_TODAY"
    }

    static let category = "NOTE_WINDOW"
    /// Called on the main actor when Carl taps a button.
    var onAction: ((Action) -> Void)?

    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [
                    UNNotificationAction(identifier: Action.snooze.rawValue, title: "Snooze 10 min"),
                    UNNotificationAction(identifier: Action.pauseToday.rawValue, title: "Pause for today"),
                ],
                intentIdentifiers: []
            )
        ])
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Notification authorization failed: \(error)") }
        }
    }

    func post(_ body: String, sound: Bool, category: String? = Notifier.category) {
        let content = UNMutableNotificationContent()
        content.title = "Intermission"
        content.body = body
        if sound { content.sound = .default }
        if let category { content.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // Show the banner even when Intermission is the front app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let action = Action(rawValue: response.actionIdentifier) else { return }
        await MainActor.run { self.onAction?(action) }
    }
}
