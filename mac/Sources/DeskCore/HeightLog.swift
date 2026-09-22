import Foundation

/// When the desk was up and when it was down, as stretches rather than
/// totals.
///
/// DeskTimeline keeps the day's sums, which is what the percentage needs.
/// This keeps the shape of the day, which is what the Desk lane needs - and
/// without it the lane had to colour the whole day by whatever the desk is
/// doing right now, which read as "you stood all day" the moment you stood up.
public struct DeskSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { start }
    public var start: Date
    public var end: Date?
    public var isStanding: Bool

    public func duration(now: Date) -> TimeInterval { (end ?? now).timeIntervalSince(start) }
}

public struct HeightLog: Codable, Equatable, Sendable {
    public private(set) var segments: [DeskSegment] = []

    public init() {}

    public var current: DeskSegment? { segments.last.flatMap { $0.end == nil ? $0 : nil } }

    /// Called on every height report; only a change starts a new stretch.
    public mutating func record(standing: Bool, at now: Date) {
        if let current, current.isStanding == standing { return }
        if let index = segments.indices.last, segments[index].end == nil {
            segments[index].end = now
        }
        segments.append(DeskSegment(start: now, end: nil, isStanding: standing))
    }

    public func segments(on day: Date, calendar: Calendar = .current) -> [DeskSegment] {
        segments.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    public mutating func prune(before cutoff: Date) {
        segments.removeAll { ($0.end ?? cutoff) < cutoff }
    }
}
