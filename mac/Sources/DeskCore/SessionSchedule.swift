import Foundation

/// The day's sessions, as Practice Studio publishes them:
///
///     ~/Library/Application Support/com.carlwilliamson.practicestudio/desk-reminder/sessions.json
///     {"sessions": [{"start": "...", "end": "...", "mode": "in-person"}],
///      "hours": [{"day": 0, "startMinutes": 570, "endMinutes": 1020}],
///      "daysOff": ["2026-11-26"], "ends": [...]}
///
/// Times, modality, working hours and dates off - no names, ids, status or
/// labels. This app never reads Practice Studio's appointments file, and
/// nothing here writes anything back.
public struct PublishedSession: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case virtual, unknown
        case inPerson = "in-person"

        /// A session we treat as seated. Unknown counts as in person, so a
        /// session with no location still gets its standing note window.
        public var isSeated: Bool { self == .virtual }
    }

    public let start: Date
    public let end: Date
    public let mode: Mode

    public init(start: Date, end: Date, mode: Mode) {
        self.start = start
        self.end = end
        self.mode = mode
    }
}

/// A working-hours window, as the Availability editor has it. day: 0=Mon..6=Sun.
public struct WorkingHours: Codable, Equatable, Sendable {
    public let day: Int
    public let startMinutes: Int
    public let endMinutes: Int

    public init(day: Int, startMinutes: Int, endMinutes: Int) {
        self.day = day
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    /// Practice Studio counts days 0=Mon..6=Sun; Foundation counts 1=Sun..7=Sat.
    public var weekday: Int { day == 6 ? 1 : day + 2 }
}

public struct SessionSchedule: Sendable {
    public private(set) var sessions: [PublishedSession] = []
    public private(set) var hours: [WorkingHours] = []
    /// "YYYY-MM-DD" for every day off: time off, and holidays not worked through.
    public private(set) var daysOff: Set<String> = []
    private let url: URL
    private var modified: Date?

    public init(url: URL) { self.url = url }

    /// Re-reads the file when it has changed on disk. Cheap enough to call often.
    @discardableResult
    public mutating func reload() -> Bool {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        guard stamp != modified else { return false }
        modified = stamp
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder.deskDecoder.decode(File.self, from: data)
        else {
            sessions = []
            hours = []
            daysOff = []
            return true
        }
        hours = file.hours ?? []
        daysOff = Set(file.daysOff ?? [])
        sessions = file.sessions ?? (file.ends ?? []).map {
            // Older file: end times only. Treated as in person, which is what
            // the Python app assumed too.
            PublishedSession(start: $0, end: $0, mode: .inPerson)
        }
        return true
    }

    /// Sessions ending in (after, until]. Used to fire the note reminder.
    public func endings(after: Date, until: Date) -> [PublishedSession] {
        sessions.filter { $0.end > after && $0.end <= until }
    }

    public func session(covering instant: Date) -> PublishedSession? {
        sessions.first { $0.start <= instant && instant < $0.end }
    }

    public func sessions(on day: Date, calendar: Calendar = .current) -> [PublishedSession] {
        sessions.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    /// The working windows for a weekday, in order.
    ///
    /// A day can have more than one - Carl's Thursday is 9:00-10:30 and then
    /// 13:30-17:00 - and the gap between them is not his to fill. So the
    /// windows are kept apart rather than flattened into open-to-close.
    /// Empty when availability isn't set up, or the day has none: a day with
    /// no window is a day he doesn't work.
    public func workingWindows(on day: Date, calendar: Calendar = .current) -> [DateInterval] {
        guard !hours.isEmpty else { return [] }
        let weekday = calendar.component(.weekday, from: day)
        return hours
            .filter { $0.weekday == weekday && $0.endMinutes > $0.startMinutes }
            .compactMap { window in
                guard let start = calendar.date(
                        bySettingHour: window.startMinutes / 60,
                        minute: window.startMinutes % 60, second: 0, of: day),
                      let end = calendar.date(
                        bySettingHour: window.endMinutes / 60,
                        minute: window.endMinutes % 60, second: 0, of: day)
                else { return nil }
                return DateInterval(start: start, end: end)
            }
            .sorted { $0.start < $1.start }
    }

    /// Open to close for a weekday, gaps included. For the plan's outer
    /// bounds; `workingWindows` is what says where things may be placed.
    public func workingHours(on day: Date, calendar: Calendar = .current) -> DateInterval? {
        let windows = workingWindows(on: day, calendar: calendar)
        guard let first = windows.first, let last = windows.last else { return nil }
        return DateInterval(start: first.start, end: last.end)
    }

    public func isDayOff(_ day: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = parts.year, let month = parts.month, let date = parts.day else { return false }
        return daysOff.contains(String(format: "%04d-%02d-%02d", year, month, date))
    }

    private struct File: Codable {
        let sessions: [PublishedSession]?
        let hours: [WorkingHours]?
        let daysOff: [String]?
        let ends: [Date]?
    }
}
