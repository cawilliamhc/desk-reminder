import Foundation

/// When Carl was on the computer, and what he was doing when he wasn't.
///
/// On = the Mac awake, unlocked and not idle. Off = locked, idle past the
/// threshold, or a break he started himself. A label given by hand always
/// wins over one inferred: "I'm off - reading" said so.
///
/// Off stretches with no label, longer than `promptAfter`, are what the
/// "what was that?" prompt asks about when he comes back.
public struct ComputerSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { start }
    public var start: Date
    public var end: Date?
    public var isOnComputer: Bool
    /// Only ever set on an off segment: "Lunch", "Reading", ...
    public var label: String?

    public func duration(now: Date) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }
}

public struct ComputerLog: Codable, Equatable, Sendable {
    /// An unlabelled break longer than this is worth asking about.
    public static let promptAfter: TimeInterval = 20 * 60
    /// Time away that was a session. Not a break, and never asked about:
    /// if Carl was in session, the session is what he was doing.
    public static let sessionLabel = "In session"

    public private(set) var segments: [ComputerSegment] = []

    public init() {}

    public var current: ComputerSegment? { segments.last.flatMap { $0.end == nil ? $0 : nil } }

    /// Presence changed. Nothing happens if it matches the open segment, so
    /// this can be called every tick.
    public mutating func setOnComputer(_ on: Bool, at now: Date) {
        if let current, current.isOnComputer == on { return }
        close(at: now)
        segments.append(ComputerSegment(start: now, end: nil, isOnComputer: on, label: nil))
    }

    /// "I'm off - reading": an off stretch that already knows what it is.
    public mutating func startBreak(label: String, at now: Date) {
        close(at: now)
        segments.append(ComputerSegment(start: now, end: nil, isOnComputer: false, label: label))
    }

    /// Names a break after the fact - the answer to "what was that?".
    public mutating func label(segmentStartingAt start: Date, as label: String) {
        guard let index = segments.firstIndex(where: { $0.start == start }), !segments[index].isOnComputer
        else { return }
        segments[index].label = label
    }

    /// A stretch this much inside a session was the session, whatever it
    /// was called. Below it, an overlap is just a break running long.
    public static let mostlyInSession = 0.8

    /// Names stretches away that were sessions.
    ///
    /// Unlabelled ones need only touch a session: the hour with a client is
    /// never something to ask Carl about. A stretch he named himself is left
    /// alone unless it sits almost entirely inside a session - a lunch that
    /// ran into the hour is still lunch, but a "lunch" from 1:03 to 1:52 on
    /// top of a 1:00 session is the session, and only became a lunch because
    /// the app asked a question it shouldn't have.
    @discardableResult
    public mutating func labelSessions(_ sessions: [PublishedSession], now: Date = Date()) -> Int {
        var named = 0
        for index in segments.indices {
            let segment = segments[index]
            guard !segment.isOnComputer, segment.label != Self.sessionLabel else { continue }
            let end = segment.end ?? now
            let length = end.timeIntervalSince(segment.start)
            guard length > 0 else { continue }

            let inSession = sessions.reduce(0.0) { covered, session in
                let from = max(segment.start, session.start)
                let to = min(end, session.end)
                return covered + max(0, to.timeIntervalSince(from))
            }
            guard inSession > 0 else { continue }

            let claimed = segment.label == nil || inSession / length >= Self.mostlyInSession
            if claimed {
                segments[index].label = Self.sessionLabel
                named += 1
            }
        }
        return named
    }

    /// Finished off stretches with no label, long enough to be worth asking
    /// about, newest first.
    public func unlabelledBreaks(longerThan minimum: TimeInterval = promptAfter) -> [ComputerSegment] {
        segments
            .filter { !$0.isOnComputer && $0.label == nil && $0.end != nil }
            .filter { $0.duration(now: $0.end!) >= minimum }
            .reversed()
    }

    public func segments(on day: Date, now: Date, calendar: Calendar = .current) -> [ComputerSegment] {
        segments.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    /// Seconds on the computer today.
    public func onComputer(on day: Date, now: Date, calendar: Calendar = .current) -> TimeInterval {
        segments(on: day, now: now, calendar: calendar)
            .filter(\.isOnComputer)
            .reduce(0) { $0 + $1.duration(now: now) }
    }

    /// Seconds off the computer today that Carl named, by label. Unlabelled
    /// time is deliberately left out, and so is session time: "off the
    /// computer" means lunch and reading, not the hour with a client.
    public func labelledBreaks(on day: Date, now: Date, calendar: Calendar = .current) -> [String: TimeInterval] {
        segments(on: day, now: now, calendar: calendar)
            .filter { !$0.isOnComputer && $0.label != nil && $0.label != Self.sessionLabel }
            .reduce(into: [:]) { totals, segment in
                totals[segment.label!, default: 0] += segment.duration(now: now)
            }
    }

    /// Trims segments older than `days`, so the file stays small.
    public mutating func prune(before cutoff: Date) {
        segments.removeAll { ($0.end ?? cutoff) < cutoff }
    }

    private mutating func close(at now: Date) {
        guard let index = segments.indices.last, segments[index].end == nil else { return }
        segments[index].end = now
    }
}
