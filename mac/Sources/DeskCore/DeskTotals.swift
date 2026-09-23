import Foundation

/// The day's standing and sitting time, worked out from what was logged
/// rather than counted up as the day goes.
///
/// Canonically: the desk is up and Carl is at the computer, so he's standing.
/// Both halves of that are already recorded - HeightLog knows when the desk
/// was up, ComputerLog knows when he was here - and both survive a restart,
/// which a running tally did not: relaunching the app used to reset the day
/// to zero and then write those zeros over the saved totals.
///
/// Session time is left out of both sides. The desk is down for a session by
/// definition, and counting it would drown the number he's actually moving.
public func deskTotals(
    heights: HeightLog,
    computer: ComputerLog,
    sessions: [PublishedSession] = [],
    on day: Date,
    now: Date,
    calendar: Calendar = .current
) -> DayTotals {
    let dayStart = calendar.startOfDay(for: day)
    let dayEnd = min(now, calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now)
    guard dayEnd > dayStart else { return DayTotals() }

    let atDesk = computer.segments
        .filter(\.isOnComputer)
        .compactMap { clip($0.start, $0.end ?? now, to: dayStart, dayEnd) }
    let inSession = sessions.compactMap { clip($0.start, $0.end, to: dayStart, dayEnd) }

    var totals = DayTotals()
    for stretch in heights.segments {
        guard let desk = clip(stretch.start, stretch.end ?? now, to: dayStart, dayEnd) else { continue }
        for present in atDesk {
            guard let both = overlap(desk, present) else { continue }
            let seconds = both.duration - inSession.reduce(0) { $0 + (overlap(both, $1)?.duration ?? 0) }
            guard seconds > 0 else { continue }
            if stretch.isStanding {
                totals.standing += seconds
            } else {
                totals.sitting += seconds
            }
        }
    }
    return totals
}

private func clip(_ start: Date, _ end: Date, to dayStart: Date, _ dayEnd: Date) -> DateInterval? {
    let from = max(start, dayStart)
    let to = min(end, dayEnd)
    return to > from ? DateInterval(start: from, end: to) : nil
}

private func overlap(_ a: DateInterval, _ b: DateInterval) -> DateInterval? {
    let from = max(a.start, b.start)
    let to = min(a.end, b.end)
    return to > from ? DateInterval(start: from, end: to) : nil
}
