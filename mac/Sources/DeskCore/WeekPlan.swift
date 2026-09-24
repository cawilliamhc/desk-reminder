import Foundation

/// A weekly goal put on a day.
///
/// The day is the commitment; the time is a preference. Carl clicks a slot in
/// Week because that's how a week is read, but a day laid out three mornings
/// later may have a session where that slot was - so the planner honours the
/// start if it still fits and moves it if it doesn't, saying which.
public struct GoalSlot: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(goalID)@\(Int(day.timeIntervalSince1970))" }
    public var goalID: String
    /// Start of the day it's on.
    public var day: Date
    /// The slot he picked, if he picked one.
    public var preferredStart: Date?
    /// Set only when he says so by hand: it overrides what the log says,
    /// either way. Nil means "work it out".
    public var markedDone: Bool?

    public init(goalID: String, day: Date, preferredStart: Date? = nil, markedDone: Bool? = nil) {
        self.goalID = goalID
        self.day = day
        self.preferredStart = preferredStart
        self.markedDone = markedDone
    }
}

/// One week's worth of goal placements, Monday to Sunday.
public struct WeekPlan: Codable, Equatable, Sendable {
    public var weekStart: Date
    public var slots: [GoalSlot] = []

    public init(weekStart: Date) { self.weekStart = weekStart }

    public func slots(on day: Date, calendar: Calendar = .current) -> [GoalSlot] {
        slots.filter { calendar.isDate($0.day, inSameDayAs: day) }
    }

    public func slot(for goalID: String, on day: Date, calendar: Calendar = .current) -> GoalSlot? {
        slots.first { $0.goalID == goalID && calendar.isDate($0.day, inSameDayAs: day) }
    }

    public func placed(_ goalID: String) -> Int {
        slots.count { $0.goalID == goalID }
    }

    /// Puts a goal on a day, replacing its slot if it already has one there.
    public mutating func place(_ goalID: String, on day: Date, at start: Date? = nil, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: day)
        slots.removeAll { $0.goalID == goalID && calendar.isDate($0.day, inSameDayAs: dayStart) }
        slots.append(GoalSlot(goalID: goalID, day: dayStart, preferredStart: start))
        slots.sort { ($0.preferredStart ?? $0.day) < ($1.preferredStart ?? $1.day) }
    }

    public mutating func remove(_ goalID: String, on day: Date, calendar: Calendar = .current) {
        slots.removeAll { $0.goalID == goalID && calendar.isDate($0.day, inSameDayAs: day) }
    }

    public mutating func mark(_ goalID: String, on day: Date, done: Bool?, calendar: Calendar = .current) {
        guard let index = slots.firstIndex(where: {
            $0.goalID == goalID && calendar.isDate($0.day, inSameDayAs: day)
        }) else { return }
        slots[index].markedDone = done
    }

    /// Monday of the week a date falls in.
    public static func weekStart(of date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: start)) else { return start }
        return calendar.date(byAdding: .day, value: -weekday.weekIndex, to: start) ?? start
    }
}

/// Most of the time it was planned for - not all of it, since a forty-five
/// minute stretch of writing rarely starts on the minute.
public let goalCountsAsDone = 0.6

/// Whether a goal on a day actually happened.
///
/// Detected the way breaks already are - he was away from the computer for
/// most of the time it was planned for - with a hand-set answer winning over
/// the log, because writing at the desk is still writing and the log can't
/// know that.
public func goalWasDone(
    slot: GoalSlot,
    planned: DateInterval?,
    computer: ComputerLog,
    now: Date
) -> Bool {
    if let marked = slot.markedDone { return marked }
    guard let planned, planned.end <= now else { return false }
    let away = computer.segments
        .filter { !$0.isOnComputer }
        .reduce(0.0) { total, segment in
            let from = max(segment.start, planned.start)
            let to = min(segment.end ?? now, planned.end)
            return total + max(0, to.timeIntervalSince(from))
        }
    return away >= planned.duration * goalCountsAsDone
}

/// Saved week plans, kept for a month.
public struct WeekPlanStore: Sendable {
    private var weeks: [Date: WeekPlan] = [:]
    private let url: URL
    private let calendar: Calendar

    public init(url: URL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder.deskDecoder.decode([WeekPlan].self, from: data) {
            weeks = Dictionary(uniqueKeysWithValues: saved.map { (calendar.startOfDay(for: $0.weekStart), $0) })
        }
    }

    public subscript(date: Date) -> WeekPlan {
        get {
            let start = WeekPlan.weekStart(of: date, calendar: calendar)
            return weeks[start] ?? WeekPlan(weekStart: start)
        }
        set { weeks[WeekPlan.weekStart(of: date, calendar: calendar)] = newValue }
    }

    public mutating func save() {
        let cutoff = calendar.date(byAdding: .day, value: -28, to: Date()) ?? Date.distantPast
        weeks = weeks.filter { $0.key >= calendar.startOfDay(for: cutoff) }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let sorted = weeks.values.sorted { $0.weekStart < $1.weekStart }
        try? JSONEncoder.deskEncoder.encode(sorted).write(to: url, options: .atomic)
    }
}

/// Where something of this length would go in an empty stretch.
///
/// Its start, or the next five-minute mark when the stretch has already
/// begun - and nowhere at all once the stretch is over. Offering "writing at
/// 9:00" at twenty to four is a suggestion nobody can take, and this morning's
/// empty hour is not somewhere to put this afternoon's reading.
public func placeableStart(
    length: TimeInterval,
    in stretch: DateInterval,
    now: Date,
    calendar: Calendar = .current
) -> Date? {
    guard stretch.end > now else { return nil }
    // The next five-minute mark, taken from the minute rather than from the
    // clock: rounding a time that still has seconds on it lands on 3:46.
    let minute = calendar.component(.minute, from: now)
    let onTheMinute = calendar.date(
        from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
    ) ?? now
    let bump = (5 - minute % 5) % 5
    let soon = onTheMinute.addingTimeInterval(TimeInterval((bump == 0 ? 5 : bump) * 60))
    let earliest = max(stretch.start, min(soon, stretch.end))
    guard stretch.end.timeIntervalSince(earliest) >= length else { return nil }
    return earliest
}
