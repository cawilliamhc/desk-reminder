import Foundation

/// Time that has opened up, and what could be done with it.
///
/// The rule is that nothing moves on its own. A session that didn't happen
/// leaves an hour; the app says so and offers two or three things, and the
/// day changes only when Carl picks one. A plan that rearranges itself while
/// he's in a session is a plan he has to re-read every time he looks at it.
public struct Rebalance: Equatable, Sendable {
    public enum Trigger: Equatable, Sendable {
        case sessionDidNotHappen(start: Date)
        case sessionEndedEarly(start: Date, minutes: Int)
        case calendarChanged
        case skipped(id: String, name: String)

        /// Stable enough to remember that this one has been dealt with, so
        /// the banner doesn't come back on the next tick.
        public var key: String {
            switch self {
            case .sessionDidNotHappen(let start): "gone-\(Int(start.timeIntervalSince1970))"
            case .sessionEndedEarly(let start, let minutes): "early-\(Int(start.timeIntervalSince1970))-\(minutes)"
            case .calendarChanged: "calendar"
            case .skipped(let id, _): "skipped-\(id)"
            }
        }
    }

    /// What applying an option does. Kept as intentions rather than as
    /// finished writes so Undo can reverse exactly what it did.
    public enum Action: Equatable, Sendable {
        case edit(PlanEdit)
        case placeGoal(id: String, at: Date)
    }

    public struct Option: Equatable, Identifiable, Sendable {
        public var id: String
        public var label: String
        public var detail: String
        public var actions: [Action]
        /// What the strip says afterwards: "Writing placed at 11:00."
        public var confirmation: String
    }

    public var trigger: Trigger
    /// The headline: "Your 11:00 session didn't happen. 11:00 to 12:00 is open."
    public var title: String
    public var opened: DateInterval
    public var options: [Option]
    /// The option that starts selected - the goal if one fits, else leaving
    /// the time alone.
    public var selected: String

    public var minutes: Int { Int(opened.duration / 60) }
}

extension Planner {
    /// Works out what could be done with time that has just opened up.
    ///
    /// Returns nil when there's nothing to say: no gap worth the words, or
    /// only one thing that could be done with it (the caller shows that as a
    /// one-line strip instead of a banner with a single choice).
    public func rebalance(
        trigger: Rebalance.Trigger,
        reason: String,
        blocks: [PlanBlock],
        goalsRemaining: [String: Int],
        placedGoalsToday: Set<String>,
        on day: Date,
        window: DateInterval,
        workingWindows: [DateInterval] = [],
        opened: DateInterval? = nil
    ) -> Rebalance? {
        let free = openStretches(in: blocks, window: window, workingWindows: workingWindows)
        // The time that actually opened up, not the longest hole in the day:
        // an hour freed at eleven is an hour, even when it sits inside a
        // three-hour afternoon.
        let candidates = opened.map { freed in
            free.compactMap { stretch -> DateInterval? in
                let start = max(stretch.start, freed.start)
                let end = min(stretch.end, freed.end)
                return end > start ? DateInterval(start: start, end: end) : nil
            }
        } ?? free
        guard let gap = candidates.max(by: { $0.duration < $1.duration }), gap.duration >= 15 * 60
        else { return nil }

        var options: [Rebalance.Option] = [
            Rebalance.Option(
                id: "leave",
                label: "Leave it open",
                detail: "\(Int(gap.duration / 60)) minutes to yourself. Nothing moves.",
                actions: [],
                confirmation: "Left it open. The time stays yours."
            )
        ]

        // Something already on the day that would rather be here - lunch at
        // eleven because the eleven o'clock is gone, not lunch at eleven for
        // its own sake, so it only counts when it's near its usual time.
        if let move = breakWorthMoving(into: gap, blocks: blocks, day: day) {
            options.append(move)
        }

        // The goal with the most left to do this week that fits the gap,
        // preferring one whose time of day matches.
        if let goal = goalWorthAdding(
            into: gap, remaining: goalsRemaining, alreadyToday: placedGoalsToday, day: day
        ) {
            options.append(goal)
        }

        guard options.count >= 2 else { return nil }
        return Rebalance(
            trigger: trigger,
            title: "\(reason) \(clockRange(gap)) is open.",
            opened: gap,
            options: options,
            selected: options.last!.id == "leave" ? "leave" : options.last!.id
        )
    }

    /// The open stretches of a laid-out day, buffers included, in order.
    public func openStretches(
        in blocks: [PlanBlock], window: DateInterval, workingWindows: [DateInterval] = []
    ) -> [DateInterval] {
        let gaps = gaps(around: blocks.filter { $0.kind != .open }, from: window.start, to: window.end)
        let trimmed: [Gap] = workingWindows.isEmpty ? gaps : gaps.flatMap { gap in
            workingWindows.compactMap { window -> Gap? in
                let start = max(gap.start, window.start)
                let end = min(gap.end, window.end)
                return end > start ? Gap(start: start, end: end) : nil
            }
        }
        return trimmed.map { DateInterval(start: $0.start, end: $0.end) }
    }

    private func breakWorthMoving(into gap: DateInterval, blocks: [PlanBlock], day: Date) -> Rebalance.Option? {
        for block in blocks.sorted(by: { $0.start < $1.start }) {
            guard let id = block.intermissionID, !block.isGoal,
                  let kind = intermissions.first(where: { $0.id == id }),
                  case .around(let target) = kind.preference,
                  block.length <= gap.duration
            else { continue }
            let usual = calendar.date(bySettingHour: target / 60, minute: target % 60, second: 0, of: day)!
            // Within an hour and a half of when it wants to be, or it isn't
            // lunch any more.
            guard abs(gap.start.timeIntervalSince(usual)) <= 90 * 60 else { continue }
            let earlier = gap.start < block.start
            return Rebalance.Option(
                id: "move-\(id)",
                label: "\(kind.name) \(earlier ? "earlier" : "later")",
                detail: "\(clock(gap.start))–\(clock(gap.start.addingTimeInterval(block.length))). "
                    + "\(clock(block.start)) opens instead.",
                actions: [.edit(PlanEdit(intermissionID: id, change: .moved(to: gap.start)))],
                confirmation: "\(kind.name) moved to \(clock(gap.start))."
            )
        }
        return nil
    }

    private func goalWorthAdding(
        into gap: DateInterval, remaining: [String: Int], alreadyToday: Set<String>, day: Date
    ) -> Rebalance.Option? {
        let candidates = goals.filter { kind in
            kind.enabled && !alreadyToday.contains(kind.id)
                && (remaining[kind.id] ?? 0) > 0
                && kind.length <= gap.duration
        }
        guard !candidates.isEmpty else { return nil }
        let best = candidates.max { a, b in
            let (left, right) = (suits(a, gap, day), suits(b, gap, day))
            if left != right { return !left && right }
            return (remaining[a.id] ?? 0) < (remaining[b.id] ?? 0)
        }
        guard let goal = best else { return nil }
        return Rebalance.Option(
            id: "goal-\(goal.id)",
            label: "\(goal.name) here",
            detail: "\(clock(gap.start))–\(clock(gap.start.addingTimeInterval(goal.length))) · a weekly goal.",
            actions: [.placeGoal(id: goal.id, at: gap.start)],
            confirmation: "\(goal.name) placed at \(clock(gap.start))."
        )
    }

    /// Whether a gap is the time of day this goal asked for.
    private func suits(_ kind: IntermissionKind, _ gap: DateInterval, _ day: Date) -> Bool {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let three = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: day)!
        switch kind.preference {
        case .morning: return gap.start < noon
        case .afternoon: return gap.end > noon
        case .lateAfternoon: return gap.end > three
        case .around(let minutes):
            let usual = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)!
            return abs(gap.start.timeIntervalSince(usual)) <= 90 * 60
        case .beforeSeated, .afterSitting: return true
        }
    }

    private func clockRange(_ interval: DateInterval) -> String {
        "\(clock(interval.start)) to \(clock(interval.end))"
    }
}
