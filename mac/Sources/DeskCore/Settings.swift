import Foundation

public enum Tone: String, Codable, CaseIterable, Sendable {
    case dry, warm, playful
}

public enum Weekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

/// Everything the Settings view writes. Stage 1 covers Desk, Notes and Coach;
/// intermissions and calendars join in later stages.
public struct Settings: Codable, Equatable, Sendable {
    public var standingThreshold: Double = 40
    /// Share of at-desk time (sessions excluded) to aim for.
    public var standingGoal: Double = 0.20
    public var remindForNotes: Bool = true
    public var sound: Bool = true
    public var tone: Tone = .playful
    public var deskDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .friday]
    public var pausedUntil: Date?
    /// Idle for longer than this counts as off the computer; a lock counts at once.
    public var idleMinutes: Int = 6
    /// Ask what an unlabelled break was, when it was long enough to matter.
    public var askWhatABreakWas: Bool = true
    public var intermissions: [IntermissionKind] = IntermissionKind.defaults
    /// EventKit calendar identifiers Carl has chosen to read.
    public var calendarIDs: Set<String> = []
    public var morningPlan: Bool = true
    /// Offer to plan tomorrow when the last session is done.
    public var eveningPlan: Bool = true
    /// How the day went, once the last session is behind him.
    public var endOfDaySummary: Bool = true

    public init() {}

    public func paused(at now: Date) -> Bool {
        guard let until = pausedUntil else { return false }
        return now < until
    }

    public func isDeskDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let day = Weekday(rawValue: calendar.component(.weekday, from: date)) else { return false }
        return deskDays.contains(day)
    }
}

/// Reads and writes settings.json. A missing or unreadable file means defaults:
/// the app must start even if the file is damaged.
public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder.deskDecoder.decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func save(_ settings: Settings) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? JSONEncoder.deskEncoder.encode(settings).write(to: url, options: .atomic)
    }
}

extension JSONDecoder {
    public static var deskDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    public static var deskEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
