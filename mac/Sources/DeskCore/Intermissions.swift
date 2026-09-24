import Foundation

/// Something to do away from the work, and the rule for where it goes in a day.
///
/// Two sorts, and the difference is who decides when it happens:
///
/// - A **daily break** keeps the body on a rhythm, so the planner places it.
///   Lunch, a stretch, a call.
/// - A **weekly goal** is about getting something done, so the planner never
///   places it. It waits until Carl puts it on a day. Writing, reading.
///
/// The old model had only the first sort, which is why every enabled
/// intermission was dropped into the day whether or not he'd asked for it.
public struct IntermissionKind: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable {
        case dailyBreak, weeklyGoal
    }

    /// How often a daily break happens. Goals count by the week instead, in
    /// `perWeek`.
    public enum Cadence: Equatable, Sendable {
        case daily
        case twiceDaily
        case days(Set<Weekday>)
    }

    /// Where in the day it wants to sit.
    public enum Preference: Codable, Equatable, Sendable {
        /// Minutes from midnight: the usual time, e.g. 12:00 = 720. The first
        /// gap from then on that fits.
        case around(Int)
        case morning
        case afternoon
        case lateAfternoon
        /// The gap just before a seated (virtual) session.
        case beforeSeated
        /// Once he's been sitting this long.
        case afterSitting(minutes: Int)
    }

    /// What the desk should be doing during it.
    public enum DeskRule: String, Codable, Sendable {
        case up, down, any, unchanged
    }

    public var id: String
    public var name: String
    public var role: Role = .dailyBreak
    public var minutes: Int
    /// The shortest this is still worth doing. A lunch squeezed to 35 minutes
    /// is still lunch; one squeezed to 10 isn't.
    public var minimumMinutes: Int?
    public var cadence: Cadence
    /// How many times a week a goal is meant to happen. Ignored for breaks.
    public var perWeek: Int = 3
    public var preference: Preference
    public var deskRule: DeskRule
    public var enabled: Bool = true
    /// A token from the app's palette, so Carl can tell two intermissions
    /// apart at a glance.
    public var colorToken: String = "chart-1"

    /// Spelled out because a public struct's memberwise initialiser is
    /// internal, and the app target builds Carl's own intermissions.
    public init(
        id: String,
        name: String,
        role: Role = .dailyBreak,
        minutes: Int,
        minimumMinutes: Int? = nil,
        cadence: Cadence = .daily,
        perWeek: Int = 3,
        preference: Preference,
        deskRule: DeskRule,
        enabled: Bool = true,
        colorToken: String = "chart-1"
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.minutes = minutes
        self.minimumMinutes = minimumMinutes
        self.cadence = cadence
        self.perWeek = perWeek
        self.preference = preference
        self.deskRule = deskRule
        self.enabled = enabled
        self.colorToken = colorToken
    }

    /// Every key optional on the way in, and a built-in's own default when
    /// one is missing: a file written before roles existed knows that
    /// reading is a goal only because the built-in list says so.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A local copy, because a closure can't read a property of a struct
        // that isn't fully initialised yet.
        let storedID = try c.decode(String.self, forKey: .id)
        let original = Self.defaults.first { $0.id == storedID }
        id = storedID
        name = c.value(.name, or: original?.name ?? storedID)
        role = c.value(.role, or: original?.role ?? .dailyBreak)
        minutes = c.value(.minutes, or: original?.minutes ?? 15)
        minimumMinutes = (try? c.decodeIfPresent(Int.self, forKey: .minimumMinutes)) ?? nil
        cadence = c.value(.cadence, or: original?.cadence ?? .daily)
        perWeek = c.value(.perWeek, or: original?.perWeek ?? 3)
        preference = c.value(.preference, or: original?.preference ?? .afternoon)
        deskRule = c.value(.deskRule, or: original?.deskRule ?? .any)
        enabled = c.value(.enabled, or: true)
        colorToken = c.value(.colorToken, or: original?.colorToken ?? "chart-1")
    }

    public var isGoal: Bool { role == .weeklyGoal }
    public var length: TimeInterval { TimeInterval(minutes * 60) }
    /// The shortest acceptable stretch; the full length when none is set.
    public var shortestLength: TimeInterval { TimeInterval((minimumMinutes ?? minutes) * 60) }
}

// MARK: - The rule, in a sentence

extension IntermissionKind {
    /// The one-line explanation shown in Settings.
    ///
    /// It used to be a stored string, which meant it could say whatever the
    /// author last typed: Stretch claimed "or after 90 min sitting" when the
    /// planner had no such rule, and every intermission Carl added said
    /// "Yours. Placed in a gap that fits it." Built from the fields, it can't
    /// drift from what the planner actually does.
    public var rule: String {
        isGoal
            ? "\(minutes) min, \(times(perWeek)) a week. Never placed for you. "
                + "When you put it on a day, it goes \(where_). \(desk)"
            : "\(lengthPhrase), \(cadencePhrase), \(where_). \(desk)"
    }

    private var lengthPhrase: String {
        guard let least = minimumMinutes, least < minutes else { return "\(minutes) min" }
        return "\(minutes) min (\(least) if the day is tight)"
    }

    private var cadencePhrase: String {
        switch cadence {
        case .daily: "every desk day"
        case .twiceDaily: "up to twice a desk day"
        case .days(let days):
            days.isEmpty
                ? "on no days"
                : "on " + days.sorted { $0.weekIndex < $1.weekIndex }.map(\.shortName).joined(separator: ", ")
        }
    }

    private var where_: String {
        switch preference {
        case .around(let minutes): "in the first gap from \(clockTime(minutes))"
        case .morning: "in the biggest morning gap"
        case .afternoon: "in the biggest afternoon gap"
        case .lateAfternoon: "in a gap after 3:00"
        case .beforeSeated: "just before a seated session"
        case .afterSitting(let minutes): "once you've sat for \(minutes) minutes"
        }
    }

    private var desk: String {
        switch deskRule {
        case .up: "Desk up."
        case .down: "Desk can come down."
        case .unchanged: "Desk stays where it is."
        case .any: "Desk: your call."
        }
    }

    private func times(_ count: Int) -> String {
        count == 1 ? "once" : "\(count)×"
    }

    private func clockTime(_ minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", hour12, minute)
    }
}

// MARK: - Cadence, and the shape it used to have

extension IntermissionKind.Cadence: Codable {
    private enum CodingKeys: String, CodingKey {
        case daily, twiceDaily, days, weekly
    }

    private struct Associated<T: Codable>: Codable {
        // Swift's synthesised enum encoding names the payload "_0"; matching
        // it is what lets a settings.json written by the old model be read.
        let _0: T
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.days) {
            self = .days(try container.decode(Associated<Set<Weekday>>.self, forKey: .days)._0)
        } else if container.contains(.weekly) {
            // The old "one day a week" cadence, widened to a set of days.
            self = .days([try container.decode(Associated<Weekday>.self, forKey: .weekly)._0])
        } else if container.contains(.twiceDaily) {
            self = .twiceDaily
        } else {
            self = .daily
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily: try container.encode([String: String](), forKey: .daily)
        case .twiceDaily: try container.encode([String: String](), forKey: .twiceDaily)
        case .days(let days): try container.encode(Associated(_0: days), forKey: .days)
        }
    }
}

extension IntermissionKind {
    /// How many blocks of this the planner may place in one day.
    public var placementsPerDay: Int {
        guard !isGoal else { return 0 }
        if case .twiceDaily = cadence { return 2 }
        return 1
    }

    public func runs(on day: Date, calendar: Calendar = .current) -> Bool {
        guard !isGoal else { return false }
        switch cadence {
        case .daily, .twiceDaily: return true
        case .days(let days):
            guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { return false }
            return days.contains(weekday)
        }
    }
}

extension IntermissionKind {
    /// The built-ins, as v4 has them: three breaks the planner places, two
    /// goals it never does.
    public static let defaults: [IntermissionKind] = [
        IntermissionKind(
            id: "lunch", name: "Lunch", minutes: 50, minimumMinutes: 25, cadence: .daily,
            preference: .around(12 * 60), deskRule: .any, colorToken: "chart-8"
        ),
        IntermissionKind(
            id: "stretch", name: "Stretch", minutes: 10, cadence: .twiceDaily,
            preference: .beforeSeated, deskRule: .unchanged, colorToken: "desk-1"
        ),
        IntermissionKind(
            id: "call", name: "Call a friend", minutes: 20,
            cadence: .days([.monday, .wednesday, .friday]),
            preference: .lateAfternoon, deskRule: .any, colorToken: "chart-7"
        ),
        IntermissionKind(
            id: "writing", name: "Writing", role: .weeklyGoal, minutes: 45,
            perWeek: 3, preference: .morning, deskRule: .any, colorToken: "desk-3"
        ),
        IntermissionKind(
            id: "reading", name: "Reading", role: .weeklyGoal, minutes: 30,
            perWeek: 3, preference: .afternoon, deskRule: .down, colorToken: "chart-3"
        ),
    ]

    /// What a card starts as when Carl adds one.
    public static func blank(role: Role, id: String = UUID().uuidString) -> IntermissionKind {
        role == .weeklyGoal
            ? IntermissionKind(
                id: id, name: "New goal", role: .weeklyGoal, minutes: 30, perWeek: 2,
                preference: .morning, deskRule: .any, colorToken: "desk-11"
            )
            : IntermissionKind(
                id: id, name: "New break", minutes: 15, cadence: .daily,
                preference: .afternoon, deskRule: .any, colorToken: "desk-9"
            )
    }

    /// The built-in this one started as, for "Reset to default".
    public var builtIn: IntermissionKind? {
        Self.defaults.first { $0.id == id }
    }
}
