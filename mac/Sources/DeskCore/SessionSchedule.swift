import Foundation

/// The day's sessions, as Practice Studio publishes them:
///
///     ~/Library/Application Support/com.carlwilliamson.practicestudio/desk-reminder/sessions.json
///     {"sessions": [{"start": "...", "end": "...", "mode": "in-person"}], "ends": [...]}
///
/// Times and modality only - no names, ids or status. This app never reads
/// Practice Studio's appointments file, and nothing here writes anything back.
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

public struct SessionSchedule: Sendable {
    public private(set) var sessions: [PublishedSession] = []
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
            return true
        }
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

    private struct File: Codable {
        let sessions: [PublishedSession]?
        let ends: [Date]?
    }
}
