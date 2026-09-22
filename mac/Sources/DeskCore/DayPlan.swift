import Foundation

/// What Carl changed about a day's plan. The suggestions are the app's; these
/// are his, and they outlive a reshuffle.
public struct PlanEdit: Codable, Equatable, Sendable {
    public enum Change: Codable, Equatable, Sendable {
        case moved(to: Date)
        case skipped
        /// Use a different intermission in this one's slot.
        case swapped(for: String)
        /// A one-off that isn't in the regular list.
        case added(name: String, minutes: Int, at: Date)
    }

    public var intermissionID: String
    public var change: Change

    public init(intermissionID: String, change: Change) {
        self.intermissionID = intermissionID
        self.change = change
    }
}

/// A day's plan as saved: the edits, when it was committed, and what the
/// schedule looked like at the time.
public struct DayPlan: Codable, Equatable, Sendable {
    public var day: Date
    public var edits: [PlanEdit] = []
    public var committedAt: Date?
    /// When the evening prompt for this day's plan went out, so it goes once.
    public var promptedAt: Date?
    /// The sessions as they were when this was planned. A mismatch later is
    /// how the app knows to say "this was made before the 2:00 moved".
    public var scheduleSignature: String = ""

    public init(day: Date) { self.day = day }

    public mutating func apply(_ edit: PlanEdit) {
        var kept = edits.filter {
            !($0.intermissionID == edit.intermissionID && sameSort($0.change, edit.change))
        }
        kept.append(edit)
        edits = kept
    }

    public mutating func clearEdits(for intermissionID: String) {
        edits.removeAll { $0.intermissionID == intermissionID }
    }

    private func sameSort(_ a: PlanEdit.Change, _ b: PlanEdit.Change) -> Bool {
        switch (a, b) {
        case (.moved, .moved), (.skipped, .skipped), (.swapped, .swapped), (.added, .added): true
        default: false
        }
    }
}

extension Array where Element == PublishedSession {
    /// Start, end and modality of each session, so a change to any of them
    /// shows up. Times only - nothing about who.
    public var signature: String {
        map { "\(Int($0.start.timeIntervalSince1970))-\(Int($0.end.timeIntervalSince1970))-\($0.mode.rawValue)" }
            .sorted()
            .joined(separator: ",")
    }
}

/// Saved plans, one per day, kept for a fortnight.
public struct PlanStore: Sendable {
    private var plans: [Date: DayPlan] = [:]
    private let url: URL
    private let calendar: Calendar

    public init(url: URL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder.deskDecoder.decode([DayPlan].self, from: data) {
            plans = Dictionary(uniqueKeysWithValues: saved.map { (calendar.startOfDay(for: $0.day), $0) })
        }
    }

    public subscript(day: Date) -> DayPlan {
        get { plans[calendar.startOfDay(for: day)] ?? DayPlan(day: calendar.startOfDay(for: day)) }
        set { plans[calendar.startOfDay(for: day)] = newValue }
    }

    public func isPlanned(_ day: Date) -> Bool {
        self[day].committedAt != nil
    }

    public mutating func save() {
        let cutoff = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date.distantPast
        plans = plans.filter { $0.key >= calendar.startOfDay(for: cutoff) }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let sorted = plans.values.sorted { $0.day < $1.day }
        try? JSONEncoder.deskEncoder.encode(sorted).write(to: url, options: .atomic)
    }
}
