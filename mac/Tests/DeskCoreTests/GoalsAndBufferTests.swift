import Foundation
import Testing
@testable import DeskCore

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}

/// Tuesday 22 Sep 2026 unless a day is given.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 22) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private func session(
    _ from: Int, _ fromMin: Int = 0, to: Int, _ toMin: Int = 0, virtual: Bool = false, day: Int = 22
) -> PublishedSession {
    PublishedSession(
        start: at(from, fromMin, day: day), end: at(to, toMin, day: day),
        mode: virtual ? .virtual : .inPerson
    )
}

private func planner(
    _ kinds: [IntermissionKind] = IntermissionKind.defaults, buffer: Int = 10
) -> Planner {
    Planner(calendar: calendar, intermissions: kinds, bufferMinutes: buffer)
}

/// Two sessions with a long hole between them: room for whatever a test is
/// about, and no room for an argument about the day's edges.
private func wideDay() -> [PublishedSession] {
    [session(9, 30, to: 10, 20), session(16, to: 16, 50)]
}

private func placed(_ plan: [PlanBlock], _ id: String) -> [PlanBlock] {
    plan.filter { $0.intermissionID == id }.sorted { $0.start < $1.start }
}

// MARK: - Goals are offered, not placed

@Test func aWeeklyGoalIsNeverPlacedByItself() {
    let plan = planner().plan(sessions: wideDay(), on: at(9))
    #expect(placed(plan, "reading").isEmpty)
    #expect(placed(plan, "writing").isEmpty)
    #expect(!placed(plan, "lunch").isEmpty)        // breaks still are
}

@Test func aGoalGoesWhereCarlPutIt() {
    let slot = GoalSlot(goalID: "reading", day: at(0), preferredStart: at(14))
    let plan = planner().plan(sessions: wideDay(), on: at(9), goalSlots: [slot])
    let reading = placed(plan, "reading").first
    #expect(reading?.start == at(14))
    #expect(reading?.badge == "Weekly goal")
    #expect(reading?.isGoal == true)
    #expect(reading?.isMine == true)
}

@Test func aGoalWhoseSlotHasFilledUpMovesAndSaysSo() {
    // He put reading at 2:00 on Monday; by Tuesday there's a session there.
    let slot = GoalSlot(goalID: "reading", day: at(0), preferredStart: at(14))
    let plan = planner().plan(
        sessions: wideDay() + [session(14, to: 15)],
        on: at(9),
        goalSlots: [slot]
    )
    let reading = placed(plan, "reading").first
    #expect(reading != nil)
    #expect(reading?.start != at(14))
    #expect(reading?.subline?.contains("Moved from 2:00") == true)
}

@Test func aGoalOnAnotherDayIsNotOnThisOne() {
    let slot = GoalSlot(goalID: "reading", day: at(0, day: 23), preferredStart: at(14, day: 23))
    let plan = planner().plan(sessions: wideDay(), on: at(9), goalSlots: [slot])
    #expect(placed(plan, "reading").isEmpty)
}

@Test func aGoalIsNotPlacedTwiceWhenItsSlotIsAlsoAnEdit() {
    let slot = GoalSlot(goalID: "reading", day: at(0), preferredStart: at(14))
    let plan = planner().plan(
        sessions: wideDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "reading", change: .moved(to: at(13)))],
        goalSlots: [slot]
    )
    #expect(placed(plan, "reading").count == 1)
    #expect(placed(plan, "reading").first?.start == at(13))     // the later word wins
}

// MARK: - Room to breathe

private var tea: IntermissionKind {
    IntermissionKind(
        id: "tea", name: "Tea", minutes: 30, cadence: .daily, preference: .afternoon, deskRule: .any
    )
}

@Test func twoBreaksNeverButtUpAgainstEachOther() {
    // Lunch pinned at noon, and an afternoon break laid out after it. They
    // used to meet on the minute: lunch until 3:05, reading from 3:05.
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let plan = planner([lunch, tea]).plan(
        sessions: wideDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "lunch", change: .moved(to: at(12)))]
    )
    let blocks = plan.filter(\.isSuggestion).sorted { $0.start < $1.start }
    #expect(blocks.count == 2)
    #expect(placed(plan, "tea").first?.start == at(13))      // ten clear of lunch's 12:50
}

@Test func theBufferCanBeTurnedOff() {
    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    let plan = planner([lunch, tea], buffer: 0).plan(
        sessions: wideDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "lunch", change: .moved(to: at(12)))]
    )
    #expect(placed(plan, "tea").first?.start == at(12, 50))  // straight after, if he asks for it
}

@Test func aNoteWindowNeedsNoBuffer() {
    // The ten minutes after a session are standing at the desk, not away
    // from it, so nothing has to be kept clear of them.
    let stretch = IntermissionKind(
        id: "stretch", name: "Stretch", minutes: 10, cadence: .daily,
        preference: .around(10 * 60 + 30), deskRule: .unchanged
    )
    let plan = planner([stretch]).plan(sessions: [session(9, 30, to: 10, 20)], on: at(9))
    let block = placed(plan, "stretch").first
    #expect(block?.start == at(10, 30))       // right after the note window
}

@Test func twiceDailyGetsTwoDifferentGaps() {
    let stretch = IntermissionKind.defaults.first { $0.id == "stretch" }!
    let plan = planner([stretch]).plan(
        sessions: [session(9, 30, to: 10, 20), session(13, to: 13, 50, virtual: true), session(16, to: 16, 50)],
        on: at(9)
    )
    let stretches = placed(plan, "stretch")
    #expect(stretches.count == 2)
    #expect(stretches[0].end <= stretches[1].start)
}

@Test func oneIntermissionToAGap() {
    // A single long hole doesn't become a queue of suggestions.
    let breaks = (1...4).map {
        IntermissionKind(
            id: "b\($0)", name: "Break \($0)", minutes: 20, cadence: .daily,
            preference: .afternoon, deskRule: .any
        )
    }
    let sessions = [session(9, 30, to: 10, 20), session(16, to: 16, 50)]
    let plan = planner(breaks).plan(sessions: sessions, on: at(9))
    let blocks = plan.filter(\.isSuggestion).sorted { $0.start < $1.start }
    // Three empty stretches in that day - before the first session, the long
    // middle, and after the last note - so the fourth break has nowhere to
    // go rather than doubling up in the middle.
    #expect(blocks.count == 3)
    for (a, b) in zip(blocks, blocks.dropFirst()) {
        #expect(b.start.timeIntervalSince(a.end) >= 30 * 60, "two suggestions share one gap")
    }
}

// MARK: - Sessions and events, as edited

@Test func aSessionThatDidNotHappenTakesItsNoteWithIt() {
    let sessions = [session(11, to: 11, 50), session(14, to: 14, 50)]
    let plan = planner([]).plan(
        sessions: sessions,
        on: at(9),
        edits: [PlanEdit(target: .session(start: at(11)), change: .didNotHappen)]
    )
    #expect(plan.filter { if case .session = $0.kind { return true } else { return false } }.count == 1)
    #expect(plan.filter { $0.kind == .note }.count == 1)
    // And the hour it left says what happened to it.
    let open = plan.first { $0.kind == .open && $0.start <= at(11, 30) && $0.end >= at(11, 30) }
    #expect(open?.title == "Open — 11:00 session didn't happen")
}

@Test func aSessionThatEndedEarlyGivesTheTimeBackAndMovesItsNote() {
    let plan = planner([]).plan(
        sessions: [session(14, to: 14, 50)],
        on: at(9),
        edits: [PlanEdit(target: .session(start: at(14)), change: .endedEarly(minutes: 20))]
    )
    let session = plan.first { if case .session = $0.kind { return true } else { return false } }
    #expect(session?.end == at(14, 30))
    #expect(plan.first { $0.kind == .note }?.start == at(14, 30))
}

@Test func aNoteCanBeSkippedForOneSession() {
    let plan = planner([]).plan(
        sessions: [session(14, to: 14, 50)],
        on: at(9),
        edits: [PlanEdit(target: .session(start: at(14)), change: .skipNote)]
    )
    #expect(plan.filter { $0.kind == .note }.isEmpty)
}

@Test func aSessionCanBeToldItWasVirtualAfterAll() {
    let plan = planner([]).plan(
        sessions: [session(14, to: 14, 50)],
        on: at(9),
        edits: [PlanEdit(target: .session(start: at(14)), change: .mode("virtual"))]
    )
    #expect(plan.contains { $0.kind == .session(virtual: true) })
    #expect(plan.contains { $0.kind == .note })          // still a standing note
}

@Test func anEventCanBeMarkedAsTimeAtTheComputer() {
    let event = CalendarEvent(start: at(13), end: at(13, 30), title: "Dentist")
    let plan = planner([]).plan(
        sessions: [],
        events: [event],
        on: at(9),
        edits: [PlanEdit(target: .event(start: at(13), title: "Dentist"), change: .presence(onComputer: true))]
    )
    #expect(plan.first { $0.kind == .calendarEvent }?.subline?.contains("on the computer") == true)
}

@Test func anEditKeyedToASessionThatMovedSimplyStopsApplying() {
    // Practice Studio moved the 11:00 to 11:30 after he said it didn't
    // happen. The edit doesn't follow it - the day has changed, and the
    // banner is what says so.
    let plan = planner([]).plan(
        sessions: [session(11, 30, to: 12, 20)],
        on: at(9),
        edits: [PlanEdit(target: .session(start: at(11)), change: .didNotHappen)]
    )
    #expect(plan.contains { if case .session = $0.kind { return true } else { return false } })
}

@Test func aVideoCallCountsAsTimeAtTheComputer() {
    let call = CalendarEvent(start: at(13), end: at(13, 30), title: "Zoom with the group")
    let walk = CalendarEvent(start: at(15), end: at(15, 30), title: "School pickup")
    #expect(call.isOnComputer(.guessFromTitle))
    #expect(!walk.isOnComputer(.guessFromTitle))
    #expect(walk.isOnComputer(.onComputer))
    #expect(!call.isOnComputer(.offComputer))
}

// MARK: - The week's own record

@Test func aWeekRunsMondayToSunday() {
    // Tuesday 22 Sep 2026 sits in the week of Monday the 21st.
    #expect(WeekPlan.weekStart(of: at(9), calendar: calendar) == at(0, day: 21))
    #expect(WeekPlan.weekStart(of: at(9, day: 27), calendar: calendar) == at(0, day: 21))   // Sunday
    #expect(WeekPlan.weekStart(of: at(9, day: 28), calendar: calendar) == at(0, day: 28))   // next Monday
}

@Test func placingAGoalTwiceOnADayReplacesIt() {
    var week = WeekPlan(weekStart: at(0, day: 21))
    week.place("reading", on: at(9), at: at(14), calendar: calendar)
    week.place("reading", on: at(9), at: at(15), calendar: calendar)
    #expect(week.placed("reading") == 1)
    #expect(week.slot(for: "reading", on: at(9), calendar: calendar)?.preferredStart == at(15))

    week.place("reading", on: at(9, day: 23), at: at(14, day: 23), calendar: calendar)
    #expect(week.placed("reading") == 2)                 // a different day is a different slot
    week.remove("reading", on: at(9), calendar: calendar)
    #expect(week.placed("reading") == 1)
}

@Test func aGoalIsDoneWhenHeWasAwayForMostOfIt() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.setOnComputer(false, at: at(14, 5))
    log.setOnComputer(true, at: at(14, 35))         // 30 of the 30 minutes
    let slot = GoalSlot(goalID: "reading", day: at(0), preferredStart: at(14))
    let planned = DateInterval(start: at(14), end: at(14, 30))
    #expect(goalWasDone(slot: slot, planned: planned, computer: log, now: at(15)))
}

@Test func aGoalStillAtTheComputerIsNotDone() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    let slot = GoalSlot(goalID: "reading", day: at(0), preferredStart: at(14))
    let planned = DateInterval(start: at(14), end: at(14, 30))
    #expect(!goalWasDone(slot: slot, planned: planned, computer: log, now: at(15)))
}

@Test func whatCarlSaysAboutAGoalBeatsWhatTheLogThinks() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))          // writing at the desk looks like work
    var slot = GoalSlot(goalID: "writing", day: at(0), preferredStart: at(10))
    slot.markedDone = true
    #expect(goalWasDone(
        slot: slot,
        planned: DateInterval(start: at(10), end: at(10, 45)),
        computer: log, now: at(12)
    ))

    slot.markedDone = false
    #expect(!goalWasDone(
        slot: slot,
        planned: DateInterval(start: at(10), end: at(10, 45)),
        computer: log, now: at(12)
    ))
}

@Test func aGoalIsNotDoneBeforeItsTimeHasPassed() {
    var log = ComputerLog()
    log.setOnComputer(false, at: at(14))
    let slot = GoalSlot(goalID: "reading", day: at(0), preferredStart: at(14))
    #expect(!goalWasDone(
        slot: slot,
        planned: DateInterval(start: at(14), end: at(14, 30)),
        computer: log, now: at(14, 10)
    ))
}

@Test func weekPlansRoundTripAndOldOnesArePruned() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var store = WeekPlanStore(url: url, calendar: calendar)
    var week = store[Date()]
    week.place("reading", on: Date(), at: Date(), calendar: calendar)
    store[Date()] = week

    var ancient = WeekPlan(weekStart: calendar.date(byAdding: .day, value: -60, to: Date())!)
    ancient.place("writing", on: ancient.weekStart, calendar: calendar)
    store[ancient.weekStart] = ancient
    store.save()

    let reloaded = WeekPlanStore(url: url, calendar: calendar)
    #expect(reloaded[Date()].placed("reading") == 1)
    #expect(reloaded[ancient.weekStart].slots.isEmpty)
}

// MARK: - A day he doesn't work is still a day

@Test func aDayWithNoBreaksStillHasItsHoursAndItsSpace() {
    // Thursday isn't a desk day, but he's often at the desk anyway - and a
    // Plan with no hours, no red line and nowhere to add anything is no use.
    let plan = planner().plan(sessions: wideDay(), on: at(9), placeBreaks: false)
    #expect(plan.contains { $0.kind == .open })
    #expect(plan.contains { if case .session = $0.kind { return true } else { return false } })
    #expect(plan.filter(\.isSuggestion).isEmpty)          // nothing placed for him
}

@Test func whatHePutOnADayOffIsStillPlaced() {
    let slot = GoalSlot(goalID: "reading", day: at(0), preferredStart: at(14))
    let plan = planner().plan(
        sessions: wideDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "custom-walk", change: .added(name: "Walk", minutes: 20, at: at(11)))],
        goalSlots: [slot],
        placeBreaks: false
    )
    #expect(placed(plan, "reading").first?.start == at(14))
    #expect(placed(plan, "custom-walk").first?.start == at(11))
}

// MARK: - Where something would go

@Test func aStretchThatHasBegunOffersTheNextFiveMinuteMark() {
    let afternoon = DateInterval(start: at(13, 30), end: at(17))
    let start = placeableStart(length: 45 * 60, in: afternoon, now: at(15, 47), calendar: calendar)
    #expect(start == at(15, 50))
}

@Test func aStretchStillToComeOffersItsOwnStart() {
    let afternoon = DateInterval(start: at(13, 30), end: at(17))
    #expect(placeableStart(length: 45 * 60, in: afternoon, now: at(11), calendar: calendar) == at(13, 30))
}

@Test func aStretchThatIsOverIsNowhereToPutAnything() {
    // "Writing at 9:00" offered at twenty to four, from an empty stretch
    // that ended at half ten.
    let morning = DateInterval(start: at(9), end: at(10, 30))
    #expect(placeableStart(length: 45 * 60, in: morning, now: at(15, 40), calendar: calendar) == nil)
}

@Test func whatIsLeftOfAStretchHasToBeEnough() {
    let afternoon = DateInterval(start: at(13, 30), end: at(17))
    // Forty-five minutes of writing doesn't fit into the last half hour.
    #expect(placeableStart(length: 45 * 60, in: afternoon, now: at(16, 40), calendar: calendar) == nil)
    #expect(placeableStart(length: 15 * 60, in: afternoon, now: at(16, 40), calendar: calendar) == at(16, 45))
}

@Test func aGoalCanBeLongerOrShorterForADay() {
    // "The writing was twenty minutes" - the same edit a break takes.
    let slot = GoalSlot(goalID: "writing", day: at(0), preferredStart: at(12))
    let plan = planner().plan(
        sessions: wideDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "writing", change: .resized(minutes: 20))],
        goalSlots: [slot]
    )
    let writing = placed(plan, "writing").first
    #expect(writing?.start == at(12))
    #expect(writing?.end == at(12, 20))
}
