import Foundation
import Testing
@testable import DeskCore

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: hour, minute: minute))!
}

/// Standing all morning, then sitting — Carl's actual Wednesday.
private func morning() -> (HeightLog, ComputerLog) {
    var heights = HeightLog()
    heights.record(standing: true, at: at(9, 30))
    heights.record(standing: false, at: at(10, 30))

    var computer = ComputerLog()
    computer.setOnComputer(true, at: at(9, 30))
    return (heights, computer)
}

@Test func deskUpAndAtTheComputerIsStanding() {
    let (heights, computer) = morning()
    let totals = deskTotals(heights: heights, computer: computer, on: at(9), now: at(11), calendar: calendar)
    #expect(totals.standing == 3600)          // 9:30-10:30
    #expect(totals.sitting == 1800)           // 10:30-11:00, still going
}

@Test func timeAwayFromTheComputerIsNeither() {
    var (heights, computer) = morning()
    computer.setOnComputer(false, at: at(10))     // away 10:00-10:15
    computer.setOnComputer(true, at: at(10, 15))
    let totals = deskTotals(heights: heights, computer: computer, on: at(9), now: at(11), calendar: calendar)
    #expect(totals.standing == 2700)          // the quarter hour away doesn't count
    #expect(totals.sitting == 1800)
}

@Test func sessionTimeIsLeftOutOfBothSides() {
    let (heights, computer) = morning()
    let session = PublishedSession(start: at(10), end: at(10, 50), mode: .inPerson)
    let totals = deskTotals(
        heights: heights, computer: computer, sessions: [session],
        on: at(9), now: at(11), calendar: calendar
    )
    #expect(totals.standing == 1800)          // 9:30-10:00; the session's half hour is out
    #expect(totals.sitting == 600)            // 10:50-11:00
}

@Test func totalsSurviveWhateverTheAppWasDoing() {
    // The whole point: these come from the logs, so a restart changes nothing.
    let (heights, computer) = morning()
    let first = deskTotals(heights: heights, computer: computer, on: at(9), now: at(11), calendar: calendar)
    let again = deskTotals(heights: heights, computer: computer, on: at(9), now: at(11), calendar: calendar)
    #expect(first == again)
}

@Test func yesterdaysStretchesDoNotCountToday() {
    var heights = HeightLog()
    heights.record(standing: true, at: at(9).addingTimeInterval(-86_400))
    heights.record(standing: false, at: at(10, 30))
    var computer = ComputerLog()
    computer.setOnComputer(true, at: at(9).addingTimeInterval(-86_400))

    let totals = deskTotals(heights: heights, computer: computer, on: at(9), now: at(11), calendar: calendar)
    #expect(totals.standing == 10 * 3600 + 1800)   // midnight to 10:30 only
}

@Test func anEmptyDayIsZero() {
    let totals = deskTotals(heights: HeightLog(), computer: ComputerLog(), on: at(9), now: at(11), calendar: calendar)
    #expect(totals == DayTotals())
}
