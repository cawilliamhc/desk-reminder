import Foundation
import Testing
@testable import DeskCore

private let monday = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 10:13 ET, a desk day
private let thursday = monday.addingTimeInterval(3 * 86_400)      // a rest day by default

private func coach(_ tweak: (inout Settings) -> Void = { _ in }) -> Coach {
    var s = Settings()
    tweak(&s)
    return Coach(settings: s)
}

@Test func remindsThenCountsStanding() {
    var c = coach()
    _ = c.heightChanged(29.5, at: monday)
    let (message, outcome) = c.sessionEnded(at: monday)
    #expect(message == .noteWindow)
    #expect(outcome == nil)
    #expect(c.heightChanged(35, at: monday.addingTimeInterval(10)) == nil)   // not up yet
    #expect(c.heightChanged(44.5, at: monday.addingTimeInterval(20))?.stood == true)
    #expect(!c.isWaiting)
}

@Test func alreadyStandingCountsWithoutANudge() {
    var c = coach()
    _ = c.heightChanged(44.5, at: monday)
    let (message, outcome) = c.sessionEnded(at: monday)
    #expect(message == nil)
    #expect(outcome?.stood == true)
}

@Test func secondNudgeThenGivesUp() {
    var c = coach()
    _ = c.heightChanged(29.5, at: monday)
    _ = c.sessionEnded(at: monday)
    #expect(c.tick(at: monday.addingTimeInterval(Coach.remindAgain)).message == .stillSitting)
    #expect(c.tick(at: monday.addingTimeInterval(Coach.remindAgain + 60)).message == nil)
    #expect(c.tick(at: monday.addingTimeInterval(Coach.giveUp)).outcome?.stood == false)
    #expect(!c.isWaiting)
}

@Test func silentDuringASession() {
    var c = coach()
    _ = c.heightChanged(29.5, at: monday)
    let (message, outcome) = c.sessionEnded(at: monday, inSession: true)
    #expect(message == nil && outcome == nil && !c.isWaiting)
}

@Test func silentWhilePausedAndOnRestDays() {
    var paused = coach { $0.pausedUntil = monday.addingTimeInterval(3600) }
    _ = paused.heightChanged(29.5, at: monday)
    #expect(paused.sessionEnded(at: monday).message == nil)

    var rest = coach()
    _ = rest.heightChanged(29.5, at: thursday)
    #expect(rest.sessionEnded(at: thursday).message == nil)
}

@Test func pausingMidWindowDropsItWithoutCounting() {
    var c = coach()
    _ = c.heightChanged(29.5, at: monday)
    _ = c.sessionEnded(at: monday)
    c.settings.pausedUntil = monday.addingTimeInterval(3600)
    let (message, outcome) = c.tick(at: monday.addingTimeInterval(60))
    #expect(message == nil && outcome == nil && !c.isWaiting)
}

@Test func remindersCanBeTurnedOff() {
    var c = coach { $0.remindForNotes = false }
    _ = c.heightChanged(29.5, at: monday)
    #expect(c.sessionEnded(at: monday).message == nil)
}

@Test func goalIsAnnouncedOncePerDay() {
    var c = coach()
    #expect(c.goalCrossed(share: 0.19, at: monday) == nil)
    #expect(c.goalCrossed(share: 0.22, at: monday) == .goalReached(percent: 22))
    #expect(c.goalCrossed(share: 0.30, at: monday) == nil)
    c.newDay()
    #expect(c.goalCrossed(share: 0.30, at: monday) == .goalReached(percent: 30))
}

@Test func everyMessageHasCopyInEveryTone() {
    let messages: [CoachMessage] = [
        .noteWindow, .stillSitting, .goalReached(percent: 22),
        .newStreak(days: 5, best: 6), .endOfDay(percent: 46, notesStanding: 9, notesTotal: 11),
    ]
    for tone in Tone.allCases {
        let copy = CoachCopy(tone: tone, pick: { $0.first ?? "" })
        for message in messages {
            #expect(!copy.text(for: message).isEmpty)
        }
    }
}

@Test func streakCopyMarksABest() {
    let copy = CoachCopy(tone: .playful, pick: { $0.first ?? "" })
    #expect(copy.text(for: .newStreak(days: 7, best: 6)).contains("new best"))
    #expect(copy.text(for: .newStreak(days: 5, best: 6)).contains("best is 6"))
}
