import Foundation

/// What the Now card is showing: the one thing to be doing, and what the desk
/// should be doing with you.
public enum Phase: Equatable, Sendable {
    case session(until: Date, virtual: Bool)
    case note(until: Date, seated: Bool)
    case upcoming(kind: IntermissionKind, at: Date)
    case running(kind: IntermissionKind, until: Date)
    case open

    /// How long until the thing on screen is over.
    public func remaining(at now: Date) -> TimeInterval? {
        switch self {
        case .session(let until, _), .note(let until, _), .running(_, let until):
            max(0, until.timeIntervalSince(now))
        case .upcoming(_, let at):
            max(0, at.timeIntervalSince(now))
        case .open:
            nil
        }
    }

    /// What the desk should do. Nil when the phase has no opinion.
    public var deskRule: IntermissionKind.DeskRule? {
        switch self {
        case .note(_, let seated): seated ? nil : .up
        case .session(_, let virtual): virtual ? .down : nil
        case .upcoming(let kind, _), .running(let kind, _): kind.deskRule
        case .open: nil
        }
    }

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

extension Phase {
    /// An intermission this far ahead is worth showing as "up next".
    public static let upcomingWindow: TimeInterval = 15 * 60

    /// Reads the phase off the plan and the clock.
    ///
    /// `startedIntermissions` holds the ones Carl has actually begun - the
    /// plan says when reading was meant to start, but only he can say he's
    /// reading, so an intermission block is "upcoming" until he starts it.
    public static func current(
        plan: [PlanBlock],
        kinds: [IntermissionKind],
        now: Date,
        startedIntermissions: Set<String> = []
    ) -> Phase {
        func kind(_ id: String) -> IntermissionKind? { kinds.first { $0.id == id } }

        for block in plan where block.start <= now && now < block.end {
            switch block.kind {
            case .session(let virtual):
                return .session(until: block.end, virtual: virtual)
            case .note(let seated):
                return .note(until: block.end, seated: seated)
            case .intermission(let id):
                guard let kind = kind(id) else { continue }
                return startedIntermissions.contains(id)
                    ? .running(kind: kind, until: block.end)
                    : .upcoming(kind: kind, at: block.start)
            case .calendarEvent, .open:
                continue
            }
        }

        // Nothing running: look just ahead, so the card can say what's coming.
        let soon = plan
            .filter { $0.start > now && $0.start.timeIntervalSince(now) <= upcomingWindow }
            .sorted { $0.start < $1.start }
        for block in soon {
            if case .intermission(let id) = block.kind, let kind = kind(id) {
                return .upcoming(kind: kind, at: block.start)
            }
        }
        return .open
    }
}
