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

/// A day shaped like Carl's: in around 9:30, last session ends at 4:50. The
/// plan's window is read from these, so tests about placement need a real
/// day around whatever they're checking.
private func fullDay(_ extra: [PublishedSession] = []) -> [PublishedSession] {
    ([session(10, to: 10, 50), session(16, to: 16, 50)] + extra).sorted { $0.start < $1.start }
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

@Test func virtualSessionsGetAStandingNoteWindowToo() {
    // Every note is written standing, whatever the session was.
    let plan = planner([]).plan(sessions: [session(9, to: 9, 50, virtual: true)], on: at(9))
    let notes = blocks(plan) { $0 == .note }
    #expect(notes.count == 1)
    #expect(notes[0].title == "Note — standing")
    #expect(blocks(plan) { $0 == .session(virtual: true) }.count == 1)
}

@Test func backToBackSessionsGetWhateverRoomIsLeft() {
    // 9:00-9:50 then 9:55: five minutes is still a note window.
    let tight = planner([]).plan(sessions: [session(9, to: 9, 50), session(9, 55, to: 10, 45)], on: at(9))
    let notes = blocks(tight) { $0 == .note }
    #expect(notes.count == 2)
    #expect(notes[0].start == at(9, 50))
    #expect(notes[0].end == at(9, 55))          // clipped to the next session
}

@Test func trulyBackToBackSessionsGetNoNoteWindow() {
    let plan = planner([]).plan(sessions: [session(9, to: 9, 50), session(9, 50, to: 10, 40)], on: at(9))
    #expect(blocks(plan) { $0 == .note }.count == 1)   // only the last one has room
}

@Test func aNoteWindowNeverRunsIntoACalendarEvent() {
    let plan = planner([]).plan(
        sessions: [session(9, to: 9, 50)],
        events: [CalendarEvent(start: at(9, 55), end: at(10, 30), title: "Call")],
        on: at(9)
    )
    #expect(blocks(plan) { $0 == .note }.first?.end == at(9, 55))
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
        sessions: fullDay([session(12, to: 13, 30)]),           // a session sitting right on lunch
        on: at(9)
    )
    let block = intermission(plan, "lunch")
    #expect(block != nil)
    #expect(block?.subline?.contains("usual time is busy") == true)
}

@Test func readingTakesTheLargestGapAndNotTheMorning() {
    let reading = IntermissionKind.defaults.first { $0.id == "reading" }!
    let plan = planner([reading]).plan(
        sessions: [session(10, to: 10, 50), session(13, to: 13, 20), session(16, to: 16, 50)],
        on: at(9)
    )
    // Biggest gap is 11:00-13:00, but reading is an afternoon habit, so it
    // takes the back of that gap rather than late morning.
    let block = intermission(plan, "reading")
    #expect(block != nil)
    #expect(block!.start >= at(12), "reading should not land in the morning; got \(block!.start)")
    #expect(block!.end <= at(16))
}

@Test func readingMovesToAnotherGapWhenTheBigOneIsTaken() {
    let reading = IntermissionKind.defaults.first { $0.id == "reading" }!
    let plan = planner([reading]).plan(
        sessions: [session(10, to: 13, 20), session(16, to: 16, 50)],
        on: at(9)
    )
    let block = intermission(plan, "reading")!
    #expect(block.start >= at(13, 30))      // after the long session and its note
    #expect(block.end <= at(16))
}

@Test func aWeeklyIntermissionOnlyAppearsOnItsDay() {
    let call = IntermissionKind.defaults.first { $0.id == "call" }!   // Thursday
    let tuesday = planner([call]).plan(sessions: fullDay(), on: at(9))
    let thursday = planner([call]).plan(
        sessions: [session(10, to: 10, 50, day: 24), session(16, to: 16, 50, day: 24)],
        on: at(9, day: 24)
    )
    #expect(intermission(tuesday, "call") == nil)
    #expect(intermission(thursday, "call") != nil)
}

@Test func aDisabledIntermissionIsNeverPlaced() {
    var lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    lunch.enabled = false
    let plan = planner([lunch]).plan(sessions: fullDay(), on: at(9))
    #expect(intermission(plan, "lunch") == nil)
}

@Test func stretchPrefersTheGapBeforeASeatedSession() {
    let stretch = IntermissionKind.defaults.first { $0.id == "stretch" }!
    let plan = planner([stretch]).plan(
        sessions: [session(10, to: 10, 50), session(14, to: 14, 50, virtual: true)],
        on: at(9)
    )
    let block = intermission(plan, "stretch")
    #expect(block?.end == at(14))
    #expect(block?.subline == "Before a seated session")
}

@Test func calendarEventsAreFixedAndBlockGaps() {
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let event = CalendarEvent(start: at(12, 15), end: at(13, 30), title: "Dentist")
    let plan = planner([lunch]).plan(sessions: fullDay(), events: [event], on: at(9))
    let calendarBlocks = blocks(plan) { $0 == .calendarEvent }
    #expect(calendarBlocks.first?.title == "Dentist")
    #expect(calendarBlocks.first?.badge == "Calendar")
    // Lunch cannot overlap it.
    let block = intermission(plan, "lunch")!
    #expect(block.end <= event.start || block.start >= event.end)
}

@Test func nothingOverlapsAnythingElse() {
    let plan = planner().plan(
        sessions: fullDay([session(11, to: 11, 50, virtual: true), session(14, to: 14, 50)]),
        events: [CalendarEvent(start: at(13), end: at(13, 30), title: "Call")],
        on: at(9)
    )
    for (a, b) in zip(plan, plan.dropFirst()) {
        #expect(a.end <= b.start, "\(a.title) overlaps \(b.title)")
    }
}

@Test func theDayRunsFromJustBeforeTheFirstSessionToJustAfterTheLast() {
    // Carl is in at 9:30 for a 10:00, not at eight.
    let plan = planner([]).plan(sessions: [session(10, to: 10, 50), session(15, to: 15, 50)], on: at(9))
    let open = blocks(plan) { $0 == .open }
    #expect(open.first?.start == at(9, 30))
    #expect(open.last?.end == at(16, 20))
}

@Test func aDayWithNoSessionsFallsBackToTheDefaultHours() {
    let window = planner([]).workday(sessions: [], on: at(9))
    #expect(window.start == at(Planner.dayStartHour))
    #expect(window.end == at(Planner.dayEndHour))
}

@Test func aCalendarEventCanStretchTheDay() {
    let window = planner([]).workday(
        sessions: [session(10, to: 10, 50)],
        events: [CalendarEvent(start: at(17), end: at(18), title: "Supervision")],
        on: at(9)
    )
    #expect(window.start == at(9, 30))
    #expect(window.end == at(18, 30))
}


@Test func configuredHoursSetTheDayWhenNothingIsBooked() {
    let hours = DateInterval(start: at(9, 30), end: at(17))
    let window = planner([]).workday(sessions: [], on: at(9), configuredHours: hours)
    #expect(window == hours)
}

@Test func sessionsOutsideTheUsualHoursWidenTheDay() {
    let hours = DateInterval(start: at(9, 30), end: at(17))
    let window = planner([]).workday(
        sessions: [session(10, to: 10, 50), session(18, to: 18, 50)],   // an evening one
        on: at(9),
        configuredHours: hours
    )
    #expect(window.start == at(9, 30))          // still in at half nine
    #expect(window.end == at(19, 20))           // but the evening session stretches it
}

@Test func theMorningBelongsToCarlNotToTheFirstSession() {
    // In at 9:30; first session at 11. Nothing should be offered before 9:30.
    let hours = DateInterval(start: at(9, 30), end: at(17))
    let plan = planner().plan(
        sessions: [session(11, to: 11, 50), session(15, to: 15, 50)],
        on: at(9),
        configuredHours: hours
    )
    #expect(plan.first?.start == at(9, 30))
    #expect(plan.allSatisfy { $0.start >= at(9, 30) })
}


@Test func aGapBetweenWorkingWindowsIsNotSomewhereToPutABreak() {
    // Carl's Thursday: 9:00-10:30, then nothing until 13:30.
    let windows = [
        DateInterval(start: at(9), end: at(10, 30)),
        DateInterval(start: at(13, 30), end: at(17)),
    ]
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let plan = planner([lunch]).plan(
        sessions: [session(9, 30, to: 10, 20), session(14, to: 14, 50)],
        on: at(9),
        configuredHours: DateInterval(start: at(9), end: at(17)),
        workingWindows: windows
    )
    let block = intermission(plan, "lunch")
    #expect(block != nil)
    // Anywhere but the 10:30-13:30 hole.
    #expect(block!.start >= at(13, 30) || block!.end <= at(10, 30))
}

@Test func withoutConfiguredWindowsTheWholeDayIsAvailable() {
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let plan = planner([lunch]).plan(sessions: fullDay(), on: at(9), workingWindows: [])
    #expect(intermission(plan, "lunch")?.start == at(12, 30))
}


/// A day bounded by its sessions, so the only room is between them — the
/// edges of a normal day are wide enough for anything.
private func packed(_ sessions: [PublishedSession], _ kinds: [IntermissionKind]) -> [PlanBlock] {
    planner(kinds).plan(
        sessions: sessions,
        on: at(9),
        workday: DateInterval(start: sessions.first!.start, end: sessions.last!.end)
    )
}

@Test func lunchIsShortenedRatherThanDroppedOnAFullDay() {
    // Sessions leave a 35-minute hole, and the note window takes ten of it.
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let plan = packed([session(10, to: 12, 25), session(13, to: 16, 50)], [lunch])
    let block = intermission(plan, "lunch")
    #expect(block != nil)
    #expect(block!.isShortened)
    #expect(block!.start == at(12, 35))                     // after the note window
    #expect(Int(block!.length / 60) == 25)
    #expect(block!.subline?.contains("gaps are tight") == true)
}

@Test func lunchIsNotOfferedBelowItsMinimum() {
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let plan = packed([session(10, to: 12, 40), session(13, to: 16, 50)], [lunch])   // a 10-minute hole
    #expect(intermission(plan, "lunch") == nil)
    #expect(planner([lunch]).unplaced(in: plan, on: at(9)).map(\.id) == ["lunch"])
}

@Test func somethingWithNoMinimumIsNeverShortened() {
    let reading = IntermissionKind.defaults.first { $0.id == "reading" }!
    #expect(reading.minimumMinutes == nil)
    // A 15-minute hole: too short for a 30-minute read, and it has no floor
    // to fall back to, so it simply isn't offered.
    let plan = packed([session(10, to: 12, 35), session(13, to: 16, 50)], [reading])
    #expect(intermission(plan, "reading") == nil)
}

@Test func aFullLengthPlacementIsNotMarkedShortened() {
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let plan = planner([lunch]).plan(sessions: fullDay(), on: at(9))
    #expect(intermission(plan, "lunch")?.isShortened == false)
}
