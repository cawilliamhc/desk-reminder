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

private let reading = IntermissionKind.defaults.first { $0.id == "reading" }!
private let stretch = IntermissionKind.defaults.first { $0.id == "stretch" }!

private let plan: [PlanBlock] = [
    PlanBlock(kind: .session(virtual: false), start: at(9), end: at(9, 50), title: "Session"),
    PlanBlock(kind: .note(seated: false), start: at(9, 50), end: at(10), title: "Note — standing"),
    PlanBlock(kind: .open, start: at(10), end: at(14), title: "Open"),
    PlanBlock(kind: .intermission(id: "reading"), start: at(14), end: at(14, 30), title: "Reading"),
    PlanBlock(kind: .session(virtual: true), start: at(15), end: at(15, 50), title: "Session"),
]

private func phase(_ now: Date, started: Set<String> = []) -> Phase {
    Phase.current(plan: plan, kinds: IntermissionKind.defaults, now: now, startedIntermissions: started)
}

@Test func aSessionOutranksEverything() {
    #expect(phase(at(9, 30)) == .session(until: at(9, 50), virtual: false))
    #expect(phase(at(15, 10)) == .session(until: at(15, 50), virtual: true))
}

@Test func theNoteWindowSaysToStand() {
    let now = phase(at(9, 55))
    #expect(now == .note(until: at(10), seated: false))
    #expect(now.deskRule == .up)
    #expect(now.remaining(at: at(9, 55)) == 300)
}

@Test func anIntermissionIsUpcomingUntilItIsStarted() {
    #expect(phase(at(14, 5)) == .upcoming(kind: reading, at: at(14)))
    #expect(phase(at(14, 5), started: ["reading"]) == .running(kind: reading, until: at(14, 30)))
}

@Test func theNextIntermissionShowsShortlyBefore() {
    #expect(phase(at(13, 50)) == .upcoming(kind: reading, at: at(14)))
    #expect(phase(at(13, 40)) == .open)      // more than 15 minutes out
}

@Test func openTimeHasNoDeskOpinionOrCountdown() {
    let open = phase(at(11))
    #expect(open == .open)
    #expect(open.deskRule == nil)
    #expect(open.remaining(at: at(11)) == nil)
}

@Test func deskRuleFollowsTheIntermission() {
    #expect(Phase.running(kind: reading, until: at(14, 30)).deskRule == .down)
    #expect(Phase.running(kind: stretch, until: at(14, 10)).deskRule == .unchanged)
    #expect(Phase.session(until: at(15, 50), virtual: true).deskRule == .down)
    #expect(Phase.session(until: at(9, 50), virtual: false).deskRule == nil)
}
