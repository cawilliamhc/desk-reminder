import Foundation
import Testing
@testable import DeskCore

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}

private func day(_ d: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12))!
}

private func store(_ file: String = UUID().uuidString) -> DayStore {
    DayStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(file), calendar: calendar)
}

@Test func standingShareExcludesSessions() {
    var record = DayRecord(day: day(22))
    record.standing = 3600
    record.sitting = 3600
    record.inSession = 7200
    #expect(record.standingShare == 0.5)
}

@Test func roundTripsThroughTheFile() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var s = DayStore(url: url, calendar: calendar)
    s.update(day(22)) { $0.standing = 1800; $0.notesStanding = 3; $0.notesTotal = 4 }
    s.save()

    let reloaded = DayStore(url: url, calendar: calendar)
    #expect(reloaded[day(22)].standing == 1800)
    #expect(reloaded[day(22)].notesStanding == 3)
}

@Test func recentDaysIncludeEmptyOnes() {
    var s = store()
    s.update(day(22)) { $0.standing = 60 }
    let week = s.recent(7, endingOn: day(22))
    #expect(week.count == 7)
    #expect(week.last?.standing == 60)
    #expect(week.first?.standing == 0)
}

@Test func streakCountsDaysOverGoal() {
    var s = store()
    for d in 18...22 {
        s.update(day(d)) { $0.standing = 30 * 60; $0.sitting = 70 * 60 }   // 30% of a 100-minute day
    }
    #expect(s.streak(endingOn: day(22), goal: 0.2) == 5)
    #expect(s.streak(endingOn: day(22), goal: 0.4) == 0)
}

@Test func aRestDayNeitherBreaksNorExtendsAStreak() {
    var s = store()
    s.update(day(22)) { $0.standing = 30 * 60; $0.sitting = 70 * 60 }
    s.update(day(21)) { $0.isDeskDay = false }                   // rest day, nothing logged
    s.update(day(20)) { $0.standing = 30 * 60; $0.sitting = 70 * 60 }
    #expect(s.streak(endingOn: day(22), goal: 0.2) == 2)
}

@Test func aDayUnderGoalEndsTheStreak() {
    var s = store()
    s.update(day(22)) { $0.standing = 30 * 60; $0.sitting = 70 * 60 }
    s.update(day(21)) { $0.standing = 5 * 60; $0.sitting = 95 * 60 }
    s.update(day(20)) { $0.standing = 30 * 60; $0.sitting = 70 * 60 }
    #expect(s.streak(endingOn: day(22), goal: 0.2) == 1)
    #expect(s.bestStreak(goal: 0.2) == 1)
}


@Test func aHandfulOfSecondsIsNotADay() {
    var scrap = DayRecord(day: day(21))
    scrap.standing = 7                      // what a restart leaves behind
    #expect(!scrap.isRecorded)
    #expect(scrap.standingShare == 1.0)     // the share is real, the day isn't

    var real = DayRecord(day: day(22))
    real.standing = 300
    #expect(real.isRecorded)
}

@Test func aScrapOfADayNeitherMakesNorBreaksAStreak() {
    var s = store()
    s.update(day(22)) { $0.standing = 1800; $0.sitting = 1800 }
    s.update(day(21)) { $0.standing = 7 }                        // seven seconds
    s.update(day(20)) { $0.standing = 1800; $0.sitting = 1800 }
    #expect(s.streak(endingOn: day(22), goal: 0.2) == 2)
}
