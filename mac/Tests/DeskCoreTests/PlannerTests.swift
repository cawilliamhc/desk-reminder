import Foundation
import Testing
@testable import DeskCore

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}

/// Tuesday 22 Sep 2026.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 22) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private func session(_ from: Int, _ fromMin: Int = 0, to: Int, _ toMin: Int = 0, virtual: Bool = false, day: Int = 22) -> PublishedSession {
    PublishedSession(start: at(from, fromMin, day: day), end: at(to, toMin, day: day), mode: virtual ? .virtual : .inPerson)
}

private func planner(_ kinds: [IntermissionKind] = IntermissionKind.defaults) -> Planner {
    Planner(calendar: calendar, intermissions: kinds)
}

private func blocks(_ plan: [PlanBlock], _ match: (PlanBlock.Kind) -> Bool) -> [PlanBlock] {
    plan.filter { match($0.kind) }
}

private func intermission(_ plan: [PlanBlock], _ id: String) -> PlanBlock? {
    plan.first { $0.kind == .intermission(id: id) }
}

@Test func inPersonSessionsGetAStandingNoteWindow() {
    let plan = planner([]).plan(sessions: [session(9, to: 9, 50)], on: at(9))
    let notes = blocks(plan) { $0 == .note }
    #expect(notes.count == 1)
    #expect(notes[0].start == at(9, 50))
    #expect(notes[0].end == at(10, 0))
}

@Test func virtualSessionsGetNoStandingWindow() {
    let plan = planner([]).plan(sessions: [session(9, to: 9, 50, virtual: true)], on: at(9))
    #expect(blocks(plan) { $0 == .note }.isEmpty)
    #expect(blocks(plan) { $0 == .session(virtual: true) }.count == 1)
}

@Test func lunchSitsAtItsUsualTimeWhenTheGapIsFree() {
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let plan = planner([lunch]).plan(sessions: [session(9, to: 9, 50), session(14, to: 14, 50)], on: at(9))
    let block = intermission(plan, "lunch")
    #expect(block?.start == at(12, 30))
    #expect(block?.subline == nil)
    #expect(block?.badge == "Suggested")
}

@Test func lunchMovesAndSaysWhyWhenTheUsualTimeIsBusy() {
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let plan = planner([lunch]).plan(
        sessions: [session(12, to: 13, 30)],                    // sitting right on lunch
        on: at(9)
    )
    let block = intermission(plan, "lunch")
    #expect(block != nil)
    #expect(block?.subline?.contains("usual time is busy") == true)
}

@Test func readingTakesTheLargestGapAndNotTheMorning() {
    let reading = IntermissionKind.defaults.first { $0.id == "reading" }!
    let plan = planner([reading]).plan(
        sessions: [session(9, to: 9, 50), session(13, to: 13, 20), session(16, to: 16, 50)],
        on: at(9)
    )
    // Biggest gap is 10:00-13:00, but reading is an afternoon habit, so it
    // takes the back of that gap rather than mid-morning.
    let block = intermission(plan, "reading")
    #expect(block?.start == at(12))
    #expect(block?.end == at(12, 30))
}

@Test func readingMovesToAnotherGapWhenTheBigOneIsTaken() {
    let reading = IntermissionKind.defaults.first { $0.id == "reading" }!
    let plan = planner([reading]).plan(
        sessions: [session(9, to: 9, 50), session(10, to: 13, 20), session(16, to: 16, 50)],
        on: at(9)
    )
    let block = intermission(plan, "reading")!
    #expect(block.start >= at(13, 30))      // after the long session and its note
    #expect(block.end <= at(16))
}

@Test func aWeeklyIntermissionOnlyAppearsOnItsDay() {
    let call = IntermissionKind.defaults.first { $0.id == "call" }!   // Thursday
    let tuesday = planner([call]).plan(sessions: [session(9, to: 9, 50)], on: at(9))
    let thursday = planner([call]).plan(sessions: [session(9, to: 9, 50, day: 24)], on: at(9, day: 24))
    #expect(intermission(tuesday, "call") == nil)
    #expect(intermission(thursday, "call") != nil)
}

@Test func aDisabledIntermissionIsNeverPlaced() {
    var lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    lunch.enabled = false
    let plan = planner([lunch]).plan(sessions: [session(9, to: 9, 50)], on: at(9))
    #expect(intermission(plan, "lunch") == nil)
}

@Test func stretchPrefersTheGapBeforeASeatedSession() {
    let stretch = IntermissionKind.defaults.first { $0.id == "stretch" }!
    let plan = planner([stretch]).plan(
        sessions: [session(9, to: 9, 50), session(14, to: 14, 50, virtual: true)],
        on: at(9)
    )
    let block = intermission(plan, "stretch")
    #expect(block?.end == at(14))
    #expect(block?.subline == "Before a seated session")
}

@Test func calendarEventsAreFixedAndBlockGaps() {
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let event = CalendarEvent(start: at(12, 15), end: at(13, 30), title: "Dentist")
    let plan = planner([lunch]).plan(sessions: [], events: [event], on: at(9))
    let calendarBlocks = blocks(plan) { $0 == .calendarEvent }
    #expect(calendarBlocks.first?.title == "Dentist")
    #expect(calendarBlocks.first?.badge == "Calendar")
    // Lunch cannot overlap it.
    let block = intermission(plan, "lunch")!
    #expect(block.end <= event.start || block.start >= event.end)
}

@Test func nothingOverlapsAnythingElse() {
    let plan = planner().plan(
        sessions: [session(9, to: 9, 50), session(10, to: 10, 50, virtual: true), session(14, to: 14, 50)],
        events: [CalendarEvent(start: at(13), end: at(13, 30), title: "Call")],
        on: at(9)
    )
    for (a, b) in zip(plan, plan.dropFirst()) {
        #expect(a.end <= b.start, "\(a.title) overlaps \(b.title)")
    }
}

@Test func theDayIsCoveredWithOpenTimeBetweenBlocks() {
    let plan = planner([]).plan(sessions: [session(9, to: 9, 50)], on: at(9))
    let open = blocks(plan) { $0 == .open }
    #expect(open.first?.start == at(8))            // the day window starts at 8
    #expect(open.last?.end == at(18))              // and ends at 6
}
