import Foundation

/// Something to do off the computer, and the rule for where it goes in a day.
public struct IntermissionKind: Codable, Equatable, Identifiable, Sendable {
    public enum Cadence: Codable, Equatable, Sendable {
        case daily
        case twiceDaily
        case weekly(Weekday)
    }

    /// Where in the day it wants to sit.
    public enum Preference: Codable, Equatable, Sendable {
        /// Minutes from midnight: the usual time, e.g. 12:30 = 750.
        case around(Int)
        case afternoon
        case lateAfternoon
        /// The gap just before a seated (virtual) session.
        case beforeSeated
    }

    /// What the desk should be doing during it.
    public enum DeskRule: String, Codable, Sendable {
        case up, down, any, unchanged
    }

    public var id: String
    public var name: String
    public var minutes: Int
    /// The shortest this is still worth doing. A lunch squeezed to 35 minutes
    /// is still lunch; one squeezed to 10 isn't.
    public var minimumMinutes: Int?
    public var cadence: Cadence
    public var preference: Preference
    public var deskRule: DeskRule
    /// The one-line explanation shown in Settings.
    public var rule: String
    public var enabled: Bool = true
    /// A token from the app's chart palette, so Carl can tell two
    /// intermissions apart at a glance.
    public var colorToken: String = "chart-1"

    /// Spelled out because a public struct's memberwise initialiser is
    /// internal, and the app target builds Carl's own intermissions.
    public init(
        id: String,
        name: String,
        minutes: Int,
        minimumMinutes: Int? = nil,
        cadence: Cadence,
        preference: Preference,
        deskRule: DeskRule,
        rule: String,
        enabled: Bool = true,
        colorToken: String = "chart-1"
    ) {
        self.id = id
        self.name = name
        self.minutes = minutes
        self.minimumMinutes = minimumMinutes
        self.cadence = cadence
        self.preference = preference
        self.deskRule = deskRule
        self.rule = rule
        self.enabled = enabled
        self.colorToken = colorToken
    }

    public var length: TimeInterval { TimeInterval(minutes * 60) }
    /// The shortest acceptable stretch; the full length when none is set.
    public var shortestLength: TimeInterval { TimeInterval((minimumMinutes ?? minutes) * 60) }
}

extension IntermissionKind {
    public static let defaults: [IntermissionKind] = [
        IntermissionKind(
            id: "lunch", name: "Lunch", minutes: 50, minimumMinutes: 25, cadence: .daily,
            preference: .around(12 * 60 + 30), deskRule: .any,
            rule: "First gap of 45 min or more after the target time. Nudge if it slips.",
            colorToken: "chart-5"
        ),
        IntermissionKind(
            id: "reading", name: "Reading", minutes: 30, cadence: .daily,
            preference: .afternoon, deskRule: .down,
            rule: "Largest remaining gap of the day.",
            colorToken: "chart-3"
        ),
        IntermissionKind(
            id: "stretch", name: "Stretch", minutes: 10, cadence: .twiceDaily,
            preference: .beforeSeated, deskRule: .unchanged,
            rule: "Short gap before a seated session, or after 90 min sitting.",
            colorToken: "chart-6"
        ),
        IntermissionKind(
            id: "call", name: "Call a friend", minutes: 20, cadence: .weekly(.thursday),
            preference: .lateAfternoon, deskRule: .any,
            rule: "Any gap of 20 min or more. Skips days with a personal call already booked.",
            colorToken: "chart-7"
        ),
    ]
}
