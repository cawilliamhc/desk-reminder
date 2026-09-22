import Foundation

/// Decides when to nudge, and what about.
///
/// After a session ends: already standing counts and says nothing; otherwise
/// nudge, nudge once more after 5 minutes, and give up after 20. Reaching
/// standing height at any point in that window counts.
///
/// Silent while paused, on a rest day, or inside a session - a nudge during
/// somebody's hour is the one thing this must never do.
public struct Coach: Sendable {
    public static let remindAgain: TimeInterval = 5 * 60
    public static let giveUp: TimeInterval = 20 * 60

    public struct Outcome: Equatable, Sendable {
        public let stood: Bool
        public let at: Date
    }

    public var settings: Settings
    public private(set) var height: Double?
    private var windowStarted: Date?
    private var remindedAgain = false
    private var goalAnnounced = false

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public var isWaiting: Bool { windowStarted != nil }
    public var isStanding: Bool? { height.map { $0 >= settings.standingThreshold } }

    /// A session ended. Returns what to say, and records the outcome when
    /// there's nothing to wait for.
    public mutating func sessionEnded(
        at now: Date, inSession: Bool = false
    ) -> (message: CoachMessage?, outcome: Outcome?) {
        guard settings.remindForNotes,
              !settings.paused(at: now),
              settings.isDeskDay(now),
              !inSession,
              !isWaiting
        else { return (nil, nil) }

        if isStanding == true {
            return (nil, Outcome(stood: true, at: now))
        }
        windowStarted = now
        remindedAgain = false
        return (.noteWindow, nil)
    }

    public mutating func heightChanged(_ newHeight: Double, at now: Date) -> Outcome? {
        height = newHeight
        guard isWaiting, newHeight >= settings.standingThreshold else { return nil }
        windowStarted = nil
        return Outcome(stood: true, at: now)
    }

    /// Called about once a second. Returns a nudge, an outcome, or neither.
    public mutating func tick(at now: Date) -> (message: CoachMessage?, outcome: Outcome?) {
        guard let started = windowStarted else { return (nil, nil) }
        if settings.paused(at: now) {
            windowStarted = nil          // paused mid-window: drop it, count nothing
            return (nil, nil)
        }
        let elapsed = now.timeIntervalSince(started)
        if elapsed >= Self.giveUp {
            windowStarted = nil
            return (nil, Outcome(stood: false, at: now))
        }
        if elapsed >= Self.remindAgain, !remindedAgain {
            remindedAgain = true
            return (.stillSitting, nil)
        }
        return (nil, nil)
    }

    /// Announced once a day, the first time standing share passes the goal.
    public mutating func goalCrossed(share: Double, at now: Date) -> CoachMessage? {
        guard !goalAnnounced, share >= settings.standingGoal,
              !settings.paused(at: now), settings.isDeskDay(now)
        else { return nil }
        goalAnnounced = true
        return .goalReached(percent: Int((share * 100).rounded()))
    }

    public mutating func newDay() {
        goalAnnounced = false
        windowStarted = nil
    }

    /// Drops a reminder in progress without counting it either way (pausing).
    public mutating func cancel() { windowStarted = nil }
}
