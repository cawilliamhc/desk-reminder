import Foundation

/// Turns height reports into how long the desk spent up versus down.
///
/// Three things shape this:
///
/// * The box only speaks while the desk moves, so a height holds until the
///   next report. Time is accumulated on `tick`, not on reports.
/// * The desk is shared, so time only counts while `isPresent` - the Mac is
///   unlocked and in use. Someone else's standing is not Carl's standing.
/// * A day boundary splits an interval, so totals per day stay honest when
///   the desk stays up past midnight.
public struct DayTotals: Equatable, Sendable {
    public var standing: TimeInterval = 0
    public var sitting: TimeInterval = 0

    public var atDesk: TimeInterval { standing + sitting }
    public var standingShare: Double { atDesk > 0 ? standing / atDesk : 0 }
}

public struct DeskTimeline: Sendable {
    public private(set) var height: Double?
    /// True when `height` came from a previous run rather than a live report.
    public private(set) var heightIsAssumed: Bool
    public private(set) var isPresent: Bool = false
    public private(set) var totals: [Date: DayTotals] = [:]   // keyed by start of day

    public var standingThreshold: Double
    private var lastTick: Date?
    private var calendar: Calendar

    public init(
        standingThreshold: Double = 40,
        assumedHeight: Double? = nil,
        calendar: Calendar = .current
    ) {
        self.standingThreshold = standingThreshold
        self.height = assumedHeight
        self.heightIsAssumed = assumedHeight != nil
        self.calendar = calendar
    }

    public var isStanding: Bool? {
        height.map { $0 >= standingThreshold }
    }

    public mutating func report(height: Double, at now: Date) {
        accumulate(until: now)
        self.height = height
        heightIsAssumed = false
    }

    public mutating func setPresent(_ present: Bool, at now: Date) {
        accumulate(until: now)
        isPresent = present
    }

    public mutating func tick(_ now: Date) {
        accumulate(until: now)
    }

    public func totals(for day: Date) -> DayTotals {
        totals[calendar.startOfDay(for: day)] ?? DayTotals()
    }

    /// Credit the time since the last tick to whichever bucket applies,
    /// splitting at midnight so a day's totals only hold that day's time.
    private mutating func accumulate(until now: Date) {
        defer { lastTick = now }
        guard let from = lastTick, now > from, isPresent, let standing = isStanding else { return }

        var cursor = from
        while cursor < now {
            let dayStart = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
            let sliceEnd = min(now, nextDay)
            var day = totals[dayStart] ?? DayTotals()
            if standing {
                day.standing += sliceEnd.timeIntervalSince(cursor)
            } else {
                day.sitting += sliceEnd.timeIntervalSince(cursor)
            }
            totals[dayStart] = day
            cursor = sliceEnd
        }
    }
}
