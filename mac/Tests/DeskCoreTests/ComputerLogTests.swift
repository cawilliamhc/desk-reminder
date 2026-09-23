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

@Test func recordsOnAndOffStretches() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.setOnComputer(false, at: at(10))
    log.setOnComputer(true, at: at(10, 30))
    #expect(log.segments.count == 3)
    #expect(log.onComputer(on: at(9), now: at(11), calendar: calendar) == 3600 + 1800)
}

@Test func repeatedSameStateDoesNotSplitTheSegment() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    for minute in 1...5 { log.setOnComputer(true, at: at(9, minute)) }
    #expect(log.segments.count == 1)
}

@Test func aNamedBreakCountsUnderItsName() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.startBreak(label: "Reading", at: at(12))
    log.setOnComputer(true, at: at(12, 40))
    #expect(log.labelledBreaks(on: at(9), now: at(13), calendar: calendar) == ["Reading": 2400])
}

@Test func unlabelledTimeIsNotCountedAsABreak() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.setOnComputer(false, at: at(13))       // in session: away, but not a break
    log.setOnComputer(true, at: at(14))
    #expect(log.labelledBreaks(on: at(9), now: at(15), calendar: calendar).isEmpty)
}

@Test func longUnlabelledBreaksAreOfferedForNaming() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.setOnComputer(false, at: at(12))
    log.setOnComputer(true, at: at(12, 51))    // 51 minutes, unnamed
    log.setOnComputer(false, at: at(13))
    log.setOnComputer(true, at: at(13, 5))     // 5 minutes: too short to ask about

    let asked = log.unlabelledBreaks()
    #expect(asked.count == 1)
    #expect(asked.first?.start == at(12))

    log.label(segmentStartingAt: at(12), as: "Lunch")
    #expect(log.unlabelledBreaks().isEmpty)
    #expect(log.labelledBreaks(on: at(9), now: at(14), calendar: calendar) == ["Lunch": 51 * 60])
}

@Test func anOpenSegmentIsStillCounted() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    #expect(log.onComputer(on: at(9), now: at(9, 30), calendar: calendar) == 1800)
    #expect(log.current?.isOnComputer == true)
}

@Test func pruningDropsSegmentsThatEndedBeforeTheCutoff() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.setOnComputer(false, at: at(10))

    log.prune(before: at(9, 30))      // the 9-10 stretch is still running at the cutoff
    #expect(log.segments.count == 2)

    log.prune(before: at(10, 30))     // now it's wholly behind us
    #expect(log.segments.count == 1)
    #expect(log.current?.start == at(10))
}


private func session(_ from: Int, _ fromMin: Int, to: Int, _ toMin: Int) -> PublishedSession {
    PublishedSession(start: at(from, fromMin), end: at(to, toMin), mode: .inPerson)
}

@Test func timeAwayDuringASessionIsTheSessionNotABreak() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.setOnComputer(false, at: at(13, 10))     // away for the 1:10
    log.setOnComputer(true, at: at(14))

    log.labelSessions([session(13, 10, to: 14, 0)])
    #expect(log.unlabelledBreaks().isEmpty)                    // never asked about
    #expect(log.labelledBreaks(on: at(9), now: at(15), calendar: calendar).isEmpty)  // not "off the computer"
    #expect(log.segments.last { !$0.isOnComputer }?.label == ComputerLog.sessionLabel)
}

@Test func aBreakThatMerelyTouchesASessionCountsAsTheSession() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.setOnComputer(false, at: at(12, 30))     // lunch running into the 1:00
    log.setOnComputer(true, at: at(13, 30))
    log.labelSessions([session(13, 0, to: 13, 50)])
    #expect(log.unlabelledBreaks().isEmpty)
}

@Test func aBreakThatRanIntoTheHourKeepsItsName() {
    // Lunch from 12:30, the 1:00 starts while he's still out: half of it was
    // lunch, so lunch it stays.
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.startBreak(label: "Lunch", at: at(12, 30))
    log.setOnComputer(true, at: at(13, 30))
    log.labelSessions([session(13, 0, to: 13, 50)])
    #expect(log.labelledBreaks(on: at(9), now: at(14), calendar: calendar) == ["Lunch": 3600])
}

@Test func aMislabelledSessionIsPutRight() {
    // Carl's actual data: the app asked what a 1:03-1:52 absence was, he
    // said lunch, and it was the 1:00 session almost exactly.
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.startBreak(label: "Lunch", at: at(13, 3))
    log.setOnComputer(true, at: at(13, 52))
    log.labelSessions([session(13, 0, to: 13, 50)])
    #expect(log.labelledBreaks(on: at(9), now: at(14), calendar: calendar).isEmpty)
    #expect(log.segments.last { !$0.isOnComputer }?.label == ComputerLog.sessionLabel)
}

@Test func aBreakWellClearOfASessionIsStillAskedAbout() {
    var log = ComputerLog()
    log.setOnComputer(true, at: at(9))
    log.setOnComputer(false, at: at(11))
    log.setOnComputer(true, at: at(11, 40))
    log.labelSessions([session(13, 0, to: 13, 50)])
    #expect(log.unlabelledBreaks().count == 1)
}
