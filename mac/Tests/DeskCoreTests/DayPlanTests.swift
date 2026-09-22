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

private func session(_ from: Int, to: Int, _ toMin: Int = 0, virtual: Bool = false) -> PublishedSession {
    PublishedSession(start: at(from), end: at(to, toMin), mode: virtual ? .virtual : .inPerson)
}

/// A day shaped like Carl's, so the plan's window is wide enough to place
/// things in - it runs from just before the first session to just after the last.
private func fullDay(_ extra: [PublishedSession] = []) -> [PublishedSession] {
    ([session(10, to: 10, 50), session(16, to: 16, 50)] + extra).sorted { $0.start < $1.start }
}

private func planner() -> Planner {
    Planner(calendar: calendar, intermissions: IntermissionKind.defaults)
}

private func block(_ plan: [PlanBlock], _ id: String) -> PlanBlock? {
    plan.first { $0.kind == .intermission(id: id) }
}

private func minutes(_ block: PlanBlock?) -> Int? {
    block.map { Int($0.length / 60) }
}

@Test func aMovedIntermissionKeepsTheTimeCarlChose() {
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "lunch", change: .moved(to: at(11, 30)))]
    )
    let lunch = block(plan, "lunch")
    #expect(lunch?.start == at(11, 30))
    #expect(lunch?.subline == "Moved by you")
    #expect(lunch?.badge == "Yours")
}

@Test func aMovedIntermissionSaysWhenTheDayHasMovedUnderIt() {
    // Lunch was put at 11:30; a session has since appeared over it.
    let plan = planner().plan(
        sessions: fullDay([session(11, to: 11, 50)]),
        on: at(9),
        edits: [PlanEdit(intermissionID: "lunch", change: .moved(to: at(11, 30)))]
    )
    #expect(block(plan, "lunch")?.subline == "Overlaps what's booked")
    #expect(block(plan, "lunch")?.start == at(11, 30))     // still where he put it
}

@Test func aSkippedIntermissionStaysAway() {
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "reading", change: .skipped)]
    )
    #expect(block(plan, "reading") == nil)
    #expect(block(plan, "lunch") != nil)     // the others still get placed
}

@Test func aSwapPutsTheReplacementInAndLeavesTheOriginalOut() {
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "reading", change: .swapped(for: "call"))]
    )
    #expect(block(plan, "reading") == nil)
    #expect(block(plan, "call")?.badge == "Yours")
}

@Test func aOneOffIsPlacedWhereItWasPut() {
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "custom-walk", change: .added(name: "Walk", minutes: 25, at: at(15)))]
    )
    let walk = block(plan, "custom-walk")
    #expect(walk?.title == "Walk")
    #expect(walk?.start == at(15))
    #expect(walk?.end == at(15, 25))
}

@Test func untouchedSuggestionsLayOutAroundTheEdits() {
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "lunch", change: .moved(to: at(11, 30)))]
    )
    let lunch = block(plan, "lunch")!
    let reading = block(plan, "reading")!
    #expect(reading.start >= lunch.end || reading.end <= lunch.start)
}

@Test func applyReplacesAnEditOfTheSameSort() {
    var day = DayPlan(day: at(9))
    day.apply(PlanEdit(intermissionID: "lunch", change: .moved(to: at(11, 30))))
    day.apply(PlanEdit(intermissionID: "lunch", change: .moved(to: at(12))))
    #expect(day.edits.count == 1)
    #expect(day.edits.first?.change == .moved(to: at(12)))       // the later time wins

    day.apply(PlanEdit(intermissionID: "reading", change: .skipped))
    #expect(day.edits.count == 2)                                 // different things, both kept
}

@Test func theScheduleSignatureChangesWhenASessionMoves() {
    let before = [session(9, to: 9, 50), session(14, to: 14, 50)]
    let sameAgain = [session(14, to: 14, 50), session(9, to: 9, 50)]      // order doesn't matter
    let moved = [session(9, to: 9, 50), session(15, to: 15, 50)]
    let modalityChanged = [session(9, to: 9, 50, virtual: true), session(14, to: 14, 50)]

    #expect(before.signature == sameAgain.signature)
    #expect(before.signature != moved.signature)
    #expect(before.signature != modalityChanged.signature)
}

@Test func plansRoundTripAndOldOnesArePruned() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var store = PlanStore(url: url, calendar: calendar)
    var today = store[Date()]
    today.apply(PlanEdit(intermissionID: "lunch", change: .skipped))
    today.committedAt = Date()
    store[Date()] = today

    var ancient = DayPlan(day: calendar.date(byAdding: .day, value: -30, to: Date())!)
    ancient.committedAt = Date()
    store[ancient.day] = ancient
    store.save()

    let reloaded = PlanStore(url: url, calendar: calendar)
    #expect(reloaded.isPlanned(Date()))
    #expect(reloaded[Date()].edits.count == 1)
    #expect(!reloaded.isPlanned(ancient.day))
}


@Test func swappingInSomethingThenMovingItGivesOneBlockNotTwo() {
    // Carl's actual tangle: reading swapped for stretch, then stretch moved.
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [
            PlanEdit(intermissionID: "reading", change: .swapped(for: "stretch")),
            PlanEdit(intermissionID: "stretch", change: .moved(to: at(14, 30))),
        ]
    )
    let stretches = plan.filter { $0.kind == .intermission(id: "stretch") }
    #expect(stretches.count == 1)
    #expect(stretches.first?.start == at(14, 30))      // where he put it
}

@Test func movingSomethingSkippedMeansHeWantsItBack() {
    var day = DayPlan(day: at(9))
    day.apply(PlanEdit(intermissionID: "stretch", change: .skipped))
    day.apply(PlanEdit(intermissionID: "stretch", change: .moved(to: at(14, 30))))
    #expect(day.edits.count == 1)
    #expect(day.edits.first?.change == .moved(to: at(14, 30)))
}

@Test func skippingSomethingMovedDropsTheMove() {
    var day = DayPlan(day: at(9))
    day.apply(PlanEdit(intermissionID: "stretch", change: .moved(to: at(14, 30))))
    day.apply(PlanEdit(intermissionID: "stretch", change: .skipped))
    #expect(day.edits.count == 1)
    #expect(day.edits.first?.change == .skipped)
}

@Test func noIntermissionIsEverPlacedTwice() {
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [
            PlanEdit(intermissionID: "lunch", change: .moved(to: at(12))),
            PlanEdit(intermissionID: "reading", change: .swapped(for: "lunch")),
        ]
    )
    let ids = plan.compactMap { block -> String? in
        if case .intermission(let id) = block.kind { return id }
        return nil
    }
    #expect(ids.count == Set(ids).count)
}

@Test func blocksStartingTogetherAreStillTwoThings() {
    let a = PlanBlock(kind: .open, start: at(12), end: at(13), title: "Open")
    let b = PlanBlock(kind: .intermission(id: "lunch"), start: at(12), end: at(12, 50), title: "Lunch")
    #expect(a.id != b.id)
}


@Test func aResizedIntermissionKeepsTheLengthCarlDragged() {
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "lunch", change: .resized(minutes: 30))]
    )
    #expect(minutes(block(plan, "lunch")) == 30)
}

@Test func resizingAndMovingTogetherBothHold() {
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [
            PlanEdit(intermissionID: "lunch", change: .moved(to: at(12))),
            PlanEdit(intermissionID: "lunch", change: .resized(minutes: 35)),
        ]
    )
    let lunch = block(plan, "lunch")
    #expect(lunch?.start == at(12))
    #expect(minutes(lunch) == 35)
}

@Test func aResizeCannotShrinkToNothing() {
    let plan = planner().plan(
        sessions: fullDay(),
        on: at(9),
        edits: [PlanEdit(intermissionID: "lunch", change: .resized(minutes: 0))]
    )
    #expect(minutes(block(plan, "lunch")) == 5)
}

@Test func skippingDropsAResize() {
    var day = DayPlan(day: at(9))
    day.apply(PlanEdit(intermissionID: "lunch", change: .resized(minutes: 30)))
    day.apply(PlanEdit(intermissionID: "lunch", change: .skipped))
    #expect(day.edits.count == 1)
    #expect(day.edits.first?.change == .skipped)
}

@Test func aSecondResizeReplacesTheFirst() {
    var day = DayPlan(day: at(9))
    day.apply(PlanEdit(intermissionID: "lunch", change: .resized(minutes: 30)))
    day.apply(PlanEdit(intermissionID: "lunch", change: .resized(minutes: 40)))
    #expect(day.edits.count == 1)
    #expect(day.edits.first?.change == .resized(minutes: 40))
}

