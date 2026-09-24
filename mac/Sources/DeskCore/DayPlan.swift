import Foundation

/// What Carl changed about a day's plan. The suggestions are the app's; these
/// are his, and they outlive a reshuffle.
public struct PlanEdit: Equatable, Sendable {
    /// What the edit is about.
    ///
    /// It used to be an intermission id and nothing else, which is why a
    /// session that didn't happen had no way of being said: the only editable
    /// things on the plan were the ones the app had suggested.
    public enum Target: Codable, Equatable, Hashable, Sendable {
        case intermission(String)
        /// Keyed on the start time, because that's what Practice Studio
        /// publishes and what survives a re-read of sessions.json. If the
        /// session moves, the edit stops matching - which is right: the day
        /// has changed, and the rebalance banner says so.
        case session(start: Date)
        case event(start: Date, title: String)
    }

    public enum Change: Codable, Equatable, Sendable {
        // Intermissions
        case moved(to: Date)
        /// Where the planner put it when the day was committed. Not Carl's
        /// choice, but his agreement: from then on the block stays there
        /// rather than being laid out again every time the day changes.
        case pinned(to: Date)
        case skipped
        /// Use a different intermission in this one's slot.
        case swapped(for: String)
        /// A one-off that isn't in the regular list.
        case added(name: String, minutes: Int, at: Date)
        /// Longer or shorter than usual, just for this day.
        case resized(minutes: Int)

        // Sessions and calendar events, today only
        case didNotHappen
        case endedEarly(minutes: Int)
        /// In person or virtual, when the published modality is wrong.
        case mode(String)
        /// No note window after this one.
        case skipNote
        /// Whether he's at the computer during a calendar event.
        case presence(onComputer: Bool)
    }

    public var target: Target
    public var change: Change

    public init(target: Target, change: Change) {
        self.target = target
        self.change = change
    }

    public init(intermissionID: String, change: Change) {
        self.init(target: .intermission(intermissionID), change: change)
    }

    /// The intermission this is about, when it is about one.
    public var intermissionID: String? {
        if case .intermission(let id) = target { return id }
        return nil
    }

    public var isAboutFixedBlock: Bool { intermissionID == nil }
}

extension PlanEdit: Codable {
    private enum CodingKeys: String, CodingKey {
        case target, change, intermissionID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        change = try container.decode(Change.self, forKey: .change)
        if let target = try container.decodeIfPresent(Target.self, forKey: .target) {
            self.target = target
        } else {
            // A plan saved before fixed blocks could be edited.
            self.target = .intermission(try container.decode(String.self, forKey: .intermissionID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(change, forKey: .change)
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
    /// Rebalances already offered for this day, by what opened the time, so
    /// the same banner doesn't come back every tick.
    public var settledRebalances: Set<String> = []

    public init(day: Date) { self.day = day }

    /// Forgiving, like Settings: a plans.json written before rebalances were
    /// remembered is still a file full of Carl's edits, and dropping it
    /// because of one missing key would throw those away.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(Date.self, forKey: .day)
        edits = c.value(.edits, or: [])
        committedAt = try? c.decodeIfPresent(Date.self, forKey: .committedAt)
        promptedAt = try? c.decodeIfPresent(Date.self, forKey: .promptedAt)
        scheduleSignature = c.value(.scheduleSignature, or: "")
        settledRebalances = c.value(.settledRebalances, or: [])
    }

    /// Records a change, dropping any it contradicts.
    ///
    /// Moving something you'd skipped means you want it after all, and
    /// skipping something you'd moved means you don't - keeping both is how
    /// a plan ends up with two of one thing, one of them at a time nobody
    /// chose.
    public mutating func apply(_ edit: PlanEdit) {
        var kept = edits.filter { existing in
            guard existing.target == edit.target else { return true }
            return !(sameSort(existing.change, edit.change) || contradicts(existing.change, edit.change))
        }
        kept.append(edit)
        edits = kept
    }

    public mutating func clearEdits(for target: PlanEdit.Target) {
        edits.removeAll { $0.target == target }
    }

    public mutating func clearEdits(for intermissionID: String) {
        clearEdits(for: .intermission(intermissionID))
    }

    public mutating func remove(_ edits: [PlanEdit]) {
        self.edits.removeAll { edit in edits.contains(edit) }
    }

    public func edits(for target: PlanEdit.Target) -> [PlanEdit] {
        edits.filter { $0.target == target }
    }

    private func contradicts(_ a: PlanEdit.Change, _ b: PlanEdit.Change) -> Bool {
        switch (a, b) {
        case (.skipped, .moved), (.moved, .skipped),
             (.skipped, .swapped), (.swapped, .skipped),
             (.moved, .swapped), (.swapped, .moved),
             (.skipped, .resized), (.resized, .skipped),
             (.pinned, .moved), (.moved, .pinned),
             (.pinned, .skipped), (.skipped, .pinned),
             (.pinned, .swapped), (.swapped, .pinned),
             // A session either didn't happen or ended early. Not both.
             (.didNotHappen, .endedEarly), (.endedEarly, .didNotHappen): true
        default: false
        }
    }

    private func sameSort(_ a: PlanEdit.Change, _ b: PlanEdit.Change) -> Bool {
        switch (a, b) {
        case (.moved, .moved), (.pinned, .pinned), (.skipped, .skipped), (.swapped, .swapped),
             (.added, .added), (.resized, .resized),
             (.didNotHappen, .didNotHappen), (.endedEarly, .endedEarly),
             (.mode, .mode), (.skipNote, .skipNote), (.presence, .presence): true
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
