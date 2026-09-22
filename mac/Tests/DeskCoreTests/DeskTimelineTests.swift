import Foundation
import Testing
@testable import DeskCore

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 22) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private func timeline(assumed: Double? = nil) -> DeskTimeline {
    DeskTimeline(standingThreshold: 40, assumedHeight: assumed, calendar: calendar)
}

@Test func countsStandingAndSittingWhilePresent() {
    var t = timeline()
    t.setPresent(true, at: at(9))
    t.report(height: 29.5, at: at(9))
    t.tick(at(10))              // an hour sitting
    t.report(height: 44.5, at: at(10))
    t.tick(at(10, 30))          // half an hour standing
    let day = t.totals(for: at(9))
    #expect(day.sitting == 3600)
    #expect(day.standing == 1800)
    #expect(day.standingShare == 1.0 / 3)
}

@Test func timeAwayFromTheMacIsNotCounted() {
    var t = timeline()
    t.setPresent(true, at: at(9))
    t.report(height: 44.5, at: at(9))
    t.setPresent(false, at: at(9, 30))
    t.tick(at(11))              // the subletter's afternoon, not Carl's
    t.setPresent(true, at: at(11))
    t.tick(at(11, 15))
    #expect(t.totals(for: at(9)).standing == 1800 + 900)
}

@Test func nothingIsCountedBeforeTheFirstHeight() {
    var t = timeline()
    t.setPresent(true, at: at(9))
    t.tick(at(10))
    #expect(t.totals(for: at(9)) == DayTotals())
}

@Test func anAssumedHeightCountsButIsMarkedAssumed() {
    var t = timeline(assumed: 44.5)
    #expect(t.heightIsAssumed)
    t.setPresent(true, at: at(9))
    t.tick(at(9, 30))
    #expect(t.totals(for: at(9)).standing == 1800)

    t.report(height: 44.5, at: at(9, 30))
    #expect(!t.heightIsAssumed)
}

@Test func intervalSpanningMidnightSplitsAcrossDays() {
    var t = timeline()
    t.setPresent(true, at: at(23))
    t.report(height: 44.5, at: at(23))
    t.tick(at(1, day: 23))
    #expect(t.totals(for: at(23)).standing == 3600)
    #expect(t.totals(for: at(1, day: 23)).standing == 3600)
}

@Test func thresholdDecidesStanding() {
    var t = timeline()
    t.report(height: 40, at: at(9))
    #expect(t.isStanding == true)
    t.report(height: 39.9, at: at(9))
    #expect(t.isStanding == false)
}


@Test func workingHoursAndDaysOffComeFromTheFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    let json = """
    {"sessions": [], "hours": [{"day": 1, "startMinutes": 570, "endMinutes": 1020}],
     "daysOff": ["2026-11-26"], "ends": []}
    """
    try json.write(to: url, atomically: true, encoding: .utf8)

    var schedule = SessionSchedule(url: url)
    schedule.reload()

    // day 1 is Tuesday in Practice Studio's 0=Mon numbering.
    let tuesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!
    let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
    let hours = schedule.workingHours(on: tuesday, calendar: calendar)
    #expect(hours?.start == calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 9, minute: 30)))
    #expect(hours?.end == calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 17)))
    #expect(schedule.workingHours(on: wednesday, calendar: calendar) == nil)

    let thanksgiving = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 12))!
    #expect(schedule.isDayOff(thanksgiving, calendar: calendar))
    #expect(!schedule.isDayOff(tuesday, calendar: calendar))
}
