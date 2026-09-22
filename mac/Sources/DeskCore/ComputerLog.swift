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
    /// time is deliberately left out: "off the computer" is meant to mean
    /// lunch and reading, not the Mac idling while he's in session.
    public func labelledBreaks(on day: Date, now: Date, calendar: Calendar = .current) -> [String: TimeInterval] {
        segments(on: day, now: now, calendar: calendar)
            .filter { !$0.isOnComputer && $0.label != nil }
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
