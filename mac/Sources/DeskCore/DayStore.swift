import Foundation

/// One day's tally. Written to days.json in the app-support folder; small
/// enough (a few hundred bytes a day) that the whole history stays in memory.
public struct DayRecord: Codable, Equatable, Sendable {
    public var day: Date              // start of day, local
    public var standing: TimeInterval = 0
    public var sitting: TimeInterval = 0
    public var inSession: TimeInterval = 0
    public var notesStanding: Int = 0
    public var notesTotal: Int = 0
    /// False on a rest day: it neither breaks a streak nor extends one.
    public var isDeskDay: Bool = true

    public init(day: Date) { self.day = day }

    public var atDesk: TimeInterval { standing + sitting }
    /// Sessions are excluded from the denominator: the desk is down for them
    /// by definition, and counting them would drown the number Carl is moving.
    public var standingShare: Double { atDesk > 0 ? standing / atDesk : 0 }
}

public struct DayStore: Sendable {
    public private(set) var days: [Date: DayRecord] = [:]
    private let url: URL
    private let calendar: Calendar

    public init(url: URL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        load()
    }

    public subscript(day: Date) -> DayRecord {
        get { days[calendar.startOfDay(for: day)] ?? DayRecord(day: calendar.startOfDay(for: day)) }
        set { days[calendar.startOfDay(for: day)] = newValue }
    }

    public mutating func update(_ day: Date, _ change: (inout DayRecord) -> Void) {
        var record = self[day]
        change(&record)
        self[day] = record
    }

    /// Most recent `count` days, oldest first, including days with no record.
    public func recent(_ count: Int, endingOn day: Date) -> [DayRecord] {
        let end = calendar.startOfDay(for: day)
        return (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: end).map { self[$0] }
        }
    }

    /// Consecutive desk days at or over the goal, counting back from `day`.
    /// Rest days are skipped rather than counted or treated as a break.
    public func streak(endingOn day: Date, goal: Double) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: day)
        for _ in 0..<365 {
            let record = self[cursor]
            if record.isDeskDay && record.atDesk > 0 {
                guard record.standingShare >= goal else { return streak }
                streak += 1
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    public func bestStreak(goal: Double) -> Int {
        days.keys.sorted().reduce(into: 0) { best, day in
            best = max(best, streak(endingOn: day, goal: goal))
        }
    }

    public mutating func save() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let sorted = days.values.sorted { $0.day < $1.day }
        try? JSONEncoder.deskEncoder.encode(sorted).write(to: url, options: .atomic)
    }

    private mutating func load() {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder.deskDecoder.decode([DayRecord].self, from: data)
        else { return }
        days = Dictionary(uniqueKeysWithValues: records.map { (calendar.startOfDay(for: $0.day), $0) })
    }
}
