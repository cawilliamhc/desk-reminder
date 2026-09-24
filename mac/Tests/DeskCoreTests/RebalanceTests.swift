import Foundation
import Testing
@testable import DeskCore

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: hour, minute: minute))!
}

private func session(_ from: Int, _ fromMin: Int = 0, to: Int, _ toMin: Int = 0) -> PublishedSession {
    PublishedSession(start: at(from, fromMin), end: at(to, toMin), mode: .inPerson)
}

/// A day like the mock's: sessions at 9, 10, 11, and lunch at noon.
private let sessions = [
    session(9, to: 9, 50), session(10, to: 10, 50), session(11, to: 11, 50), session(14, to: 14, 50),
]

private func planner() -> Planner {
    Planner(calendar: calendar, intermissions: IntermissionKind.defaults)
}

private func plan(_ edits: [PlanEdit] = [], _ slots: [GoalSlot] = []) -> [PlanBlock] {
    planner().plan(sessions: sessions, on: at(9), edits: edits, goalSlots: slots)
}

private var window: DateInterval {
    planner().workday(sessions: sessions, on: at(9))
}

private func offer(
    _ trigger: Rebalance.Trigger,
    reason: String,
    opened: DateInterval?,
    edits: [PlanEdit] = [],
    remaining: [String: Int] = ["writing": 2, "reading": 1],
    placedToday: Set<String> = []
) -> Rebalance? {
    planner().rebalance(
        trigger: trigger,
        reason: reason,
        blocks: plan(edits),
        goalsRemaining: remaining,
        placedGoalsToday: placedToday,
        on: at(9),
        window: window,
        opened: opened
    )
}

@Test func aCancelledSessionOffersTheHourBack() {
    let gone = PlanEdit(target: .session(start: at(11)), change: .didNotHappen)
    let rebalance = offer(
        .sessionDidNotHappen(start: at(11)),
        reason: "Your 11:00 session didn't happen.",
        opened: DateInterval(start: at(11), end: at(11, 50)),
        edits: [gone]
    )
    let offer = try? #require(rebalance)
    #expect(offer?.title == "Your 11:00 session didn't happen. 11:00 to 11:50 is open.")
    #expect(offer?.minutes == 50)
    // Leaving it alone is always one of the answers.
    #expect(offer?.options.first?.id == "leave")
    // And the goal with the most left to do is the one offered, selected.
    #expect(offer?.options.contains { $0.id == "goal-writing" } == true)
    #expect(offer?.selected == "goal-writing")
}

@Test func theOfferIsAboutTheTimeThatOpenedNotTheLongestHole() {
    // Thirty minutes early, ten of which the note window takes: twenty are
    // free, and twenty is what's offered - not the hour and fifty sitting in
    // the middle of the day.
    let tidy = IntermissionKind(
        id: "tidy", name: "Tidy up", role: .weeklyGoal, minutes: 15, perWeek: 2,
        preference: .afternoon, deskRule: .any
    )
    let planner = Planner(calendar: calendar, intermissions: [tidy])
    let early = PlanEdit(target: .session(start: at(14)), change: .endedEarly(minutes: 30))
    let blocks = planner.plan(sessions: sessions, on: at(9), edits: [early])
    let rebalance = planner.rebalance(
        trigger: .sessionEndedEarly(start: at(14), minutes: 30),
        reason: "Your 2:00 ended 30 min early.",
        blocks: blocks,
        goalsRemaining: ["tidy": 2],
        placedGoalsToday: [],
        on: at(9),
        window: window,
        opened: DateInterval(start: at(14, 20), end: at(14, 50))
    )
    #expect(rebalance?.minutes == 20)
    #expect(rebalance?.title == "Your 2:00 ended 30 min early. 2:30 to 2:50 is open.")
}

@Test func aGoalThatWouldNotFitTheFreedTimeIsNotOffered() {
    // Twenty minutes is not a forty-five minute stretch of writing, and
    // pretending otherwise is how a plan stops being true.
    let early = PlanEdit(target: .session(start: at(14)), change: .endedEarly(minutes: 30))
    let rebalance = offer(
        .sessionEndedEarly(start: at(14), minutes: 30),
        reason: "Your 2:00 ended 30 min early.",
        opened: DateInterval(start: at(14, 20), end: at(14, 50)),
        edits: [early]
    )
    #expect(rebalance == nil)
}

@Test func nothingIsOfferedWhenTheresOnlyOneThingToDo() {
    // No goals left this week and no break near enough to move: one option
    // isn't a choice, so the caller shows a line of text instead.
    let rebalance = offer(
        .sessionDidNotHappen(start: at(9)),
        reason: "Your 9:00 session didn't happen.",
        opened: DateInterval(start: at(9), end: at(9, 50)),
        edits: [PlanEdit(target: .session(start: at(9)), change: .didNotHappen)],
        remaining: [:]
    )
    #expect(rebalance == nil)
}

@Test func nothingIsOfferedForATinyGap() {
    let rebalance = offer(
        .sessionEndedEarly(start: at(14), minutes: 5),
        reason: "Your 2:00 ended 5 min early.",
        opened: DateInterval(start: at(14, 45), end: at(14, 50))
    )
    #expect(rebalance == nil)
}

@Test func lunchIsOfferedTheFreedHourWhenItIsNearItsUsualTime() {
    let gone = PlanEdit(target: .session(start: at(11)), change: .didNotHappen)
    let rebalance = offer(
        .sessionDidNotHappen(start: at(11)),
        reason: "Your 11:00 session didn't happen.",
        opened: DateInterval(start: at(11), end: at(11, 50)),
        edits: [gone],
        remaining: [:]
    )
    let offer = try? #require(rebalance)
    let move = offer?.options.first { $0.id == "move-lunch" }
    #expect(move?.label == "Lunch earlier")
    #expect(move?.confirmation == "Lunch moved to 11:00.")
    #expect(offer?.selected == "move-lunch")
}

@Test func aGoalAlreadyOnTodayIsNotOfferedAgain() {
    let gone = PlanEdit(target: .session(start: at(11)), change: .didNotHappen)
    let rebalance = offer(
        .sessionDidNotHappen(start: at(11)),
        reason: "Your 11:00 session didn't happen.",
        opened: DateInterval(start: at(11), end: at(11, 50)),
        edits: [gone],
        remaining: ["writing": 2],
        placedToday: ["writing"]
    )
    #expect(rebalance?.options.contains { $0.id == "goal-writing" } != true)
}

@Test func applyingAnOptionIsJustEditsAndPlacements() {
    // What an option does is expressed as intentions, so Undo can reverse
    // exactly those and nothing else.
    let gone = PlanEdit(target: .session(start: at(11)), change: .didNotHappen)
    let rebalance = offer(
        .sessionDidNotHappen(start: at(11)),
        reason: "Your 11:00 session didn't happen.",
        opened: DateInterval(start: at(11), end: at(11, 50)),
        edits: [gone]
    )
    let goal = rebalance?.options.first { $0.id == "goal-writing" }
    #expect(goal?.actions == [.placeGoal(id: "writing", at: at(11))])
    #expect(rebalance?.options.first { $0.id == "leave" }?.actions.isEmpty == true)
}

@Test func aTriggerRemembersItselfSoTheBannerGoesOnce() {
    #expect(Rebalance.Trigger.sessionDidNotHappen(start: at(11)).key
            == Rebalance.Trigger.sessionDidNotHappen(start: at(11)).key)
    #expect(Rebalance.Trigger.sessionDidNotHappen(start: at(11)).key
            != Rebalance.Trigger.sessionDidNotHappen(start: at(14)).key)
    #expect(Rebalance.Trigger.skipped(id: "lunch", name: "Lunch").key == "skipped-lunch")
}

@Test func settledRebalancesAreRememberedWithTheDay() {
    var day = DayPlan(day: at(9))
    day.settledRebalances.insert("gone-1")
    #expect(day.settledRebalances.contains("gone-1"))

    let data = try! JSONEncoder.deskEncoder.encode([day])
    let reloaded = try! JSONDecoder.deskDecoder.decode([DayPlan].self, from: data)
    #expect(reloaded.first?.settledRebalances == ["gone-1"])
}

@Test func anEditSavedBeforeTargetsExistedStillReads() throws {
    let json = """
    [{"day":"2026-09-22T13:00:00Z","edits":[{"intermissionID":"lunch","change":{"skipped":{}}}],
      "scheduleSignature":""}]
    """.data(using: .utf8)!
    let plans = try JSONDecoder.deskDecoder.decode([DayPlan].self, from: json)
    #expect(plans.first?.edits.first?.target == .intermission("lunch"))
    #expect(plans.first?.edits.first?.change == .skipped)
    #expect(plans.first?.settledRebalances.isEmpty == true)
}

@Test func aFixedBlockKnowsWhatAnEditToItWouldBeAbout() {
    let blocks = plan()
    let session = blocks.first { if case .session = $0.kind { return true } else { return false } }
    #expect(session?.target == .session(start: at(9)))
    #expect(blocks.first { $0.kind == .note }?.target == nil)      // a note is not editable
}
