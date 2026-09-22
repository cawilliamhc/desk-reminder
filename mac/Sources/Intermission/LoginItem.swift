import Foundation
import ServiceManagement

/// Open at login, through the system's own login-items list - the app appears
/// under General > Login Items, where Carl can turn it off without the app.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns what the status actually is afterwards, so a refused register
    /// (an unapproved app, say) doesn't leave the toggle lying.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Intermission: login item change failed: %@", String(describing: error))
        }
        return isEnabled
    }
}
