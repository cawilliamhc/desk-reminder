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

@Test func recordsTheStretchesTheDeskSpentUpAndDown() {
    var log = HeightLog()
    log.record(standing: false, at: at(9))
    log.record(standing: true, at: at(10))
    log.record(standing: false, at: at(11))

    let segments = log.segments(on: at(9), calendar: calendar)
    #expect(segments.count == 3)
    #expect(segments[1].isStanding)
    #expect(segments[1].duration(now: at(12)) == 3600)
    #expect(segments[0].end == at(10))
}

@Test func repeatedReportsAtTheSameStateDoNotSplitAStretch() {
    var log = HeightLog()
    log.record(standing: true, at: at(9))
    for minute in stride(from: 1, to: 20, by: 1) {
        log.record(standing: true, at: at(9, minute))     // the box reports every ~220 ms while moving
    }
    #expect(log.segments.count == 1)
    #expect(log.current?.start == at(9))
}

@Test func theOpenStretchRunsToNow() {
    var log = HeightLog()
    log.record(standing: true, at: at(9))
    #expect(log.current?.duration(now: at(9, 30)) == 1800)
    #expect(log.current?.end == nil)
}

@Test func pruningKeepsWhatOverlapsTheCutoff() {
    var log = HeightLog()
    log.record(standing: false, at: at(9))
    log.record(standing: true, at: at(10))
    log.prune(before: at(10, 30))
    #expect(log.segments.count == 1)
    #expect(log.segments.first?.isStanding == true)
}
