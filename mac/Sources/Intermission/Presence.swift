import AppKit
import Foundation

/// Whether Carl is at the Mac: unlocked, awake, and not idle.
///
/// This is how a shared desk stays honest. The subletter uses the desk when
/// he isn't here, and her standing is not his standing, so time only counts
/// while the Mac is in use.
@MainActor
final class Presence {
    /// Idle for longer than this counts as away. Settings will own it later.
    var idleThreshold: TimeInterval = 6 * 60

    private(set) var isLocked = false
    private var isAsleep = false

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(wake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(lock), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(unlock), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    /// Seconds since the last keyboard or mouse event anywhere on the system.
    var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .init(rawValue: ~0)!)
    }

    var isPresent: Bool {
        !isLocked && !isAsleep && idleSeconds < idleThreshold
    }

    @objc private func sleep() { isAsleep = true }
    @objc private func wake() { isAsleep = false }
    @objc private func lock() { isLocked = true }
    @objc private func unlock() { isLocked = false }
}
