import AppKit
import UserNotifications

/// Native notifications, with buttons - the reason the app needed to become a
/// real bundle rather than a script calling osascript.
///
/// A Focus silently queues these rather than showing them, and breaking
/// through needs the time-sensitive entitlement, which needs a provisioning
/// profile a paid developer account issues: signed ad hoc with it, the app is
/// refused at launch. So Intermission is added to the Focus's allowed apps
/// instead. interruptionLevel is set anyway, and starts working if that ever
/// changes.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    enum Action: String {
        case snooze = "SNOOZE"
        case pauseToday = "PAUSE_TODAY"
        case planTomorrow = "PLAN_TOMORROW"
    }

    nonisolated static let category = "NOTE_WINDOW"
    nonisolated static let planCategory = "PLAN_TOMORROW_OFFER"
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
            ),
            UNNotificationCategory(
                identifier: Self.planCategory,
                actions: [
                    UNNotificationAction(
                        identifier: Action.planTomorrow.rawValue,
                        title: "Plan tomorrow",
                        options: .foreground
                    )
                ],
                intentIdentifiers: []
            )
        ])
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("Intermission: notification authorization failed: %@", String(describing: error)) }
            else if !granted { NSLog("Intermission: notifications not granted") }
        }
    }

    func post(_ body: String, sound: Bool, category: String? = Notifier.category) {
        let content = UNMutableNotificationContent()
        content.title = "Intermission"
        content.body = body
        if sound { content.sound = .default }
        // Time-sensitive so a note nudge arrives during a Focus. The app is
        // already silent in session, on rest days and while paused.
        content.interruptionLevel = .timeSensitive
        if let category { content.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        ) { error in
            if let error { NSLog("Intermission: posting failed: %@", String(describing: error)) }
        }
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
        // Clicking the notification itself, not a button, opens the plan too.
        let action = Action(rawValue: response.actionIdentifier)
            ?? (response.actionIdentifier == UNNotificationDefaultActionIdentifier
                && response.notification.request.content.categoryIdentifier == Self.planCategory
                ? .planTomorrow : nil)
        guard let action else { return }
        await MainActor.run { self.onAction?(action) }
    }
}
