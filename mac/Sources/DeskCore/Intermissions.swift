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
    public var cadence: Cadence
    public var preference: Preference
    public var deskRule: DeskRule
    /// The one-line explanation shown in Settings.
    public var rule: String
    public var enabled: Bool = true

    public var length: TimeInterval { TimeInterval(minutes * 60) }
}

extension IntermissionKind {
    public static let defaults: [IntermissionKind] = [
        IntermissionKind(
            id: "lunch", name: "Lunch", minutes: 50, cadence: .daily,
            preference: .around(12 * 60 + 30), deskRule: .any,
            rule: "First gap of 45 min or more after the target time. Nudge if it slips."
        ),
        IntermissionKind(
            id: "reading", name: "Reading", minutes: 30, cadence: .daily,
            preference: .afternoon, deskRule: .down,
            rule: "Largest remaining gap of the day."
        ),
        IntermissionKind(
            id: "stretch", name: "Stretch", minutes: 10, cadence: .twiceDaily,
            preference: .beforeSeated, deskRule: .unchanged,
            rule: "Short gap before a seated session, or after 90 min sitting."
        ),
        IntermissionKind(
            id: "call", name: "Call a friend", minutes: 20, cadence: .weekly(.thursday),
            preference: .lateAfternoon, deskRule: .any,
            rule: "Any gap of 20 min or more. Skips days with a personal call already booked."
        ),
    ]
}
