import Foundation
import Testing
@testable import DeskCore

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}

/// Tuesday 22 Sep 2026.
private func day(_ number: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: number))!
}

@Test func theRuleIsBuiltFromTheFieldsRatherThanTyped() {
    let stretch = IntermissionKind.defaults.first { $0.id == "stretch" }!
    #expect(stretch.rule == "10 min, up to twice a desk day, just before a seated session. "
            + "Desk stays where it is.")

    let lunch = IntermissionKind.defaults.first { $0.id == "lunch" }!
    #expect(lunch.rule == "50 min (25 if the day is tight), every desk day, in the first gap from 12:00. "
            + "Desk: your call.")
}

@Test func aGoalSaysItIsNeverPlacedForYou() {
    let reading = IntermissionKind.defaults.first { $0.id == "reading" }!
    #expect(reading.rule.contains("3× a week"))
    #expect(reading.rule.contains("Never placed for you"))
    #expect(reading.rule.contains("biggest afternoon gap"))
}

@Test func theRuleFollowsTheFieldsWhenTheyChange() {
    var kind = IntermissionKind.defaults.first { $0.id == "call" }!
    kind.cadence = .days([.tuesday, .thursday])
    kind.preference = .afterSitting(minutes: 90)
    #expect(kind.rule == "20 min, on Tue, Thu, once you've sat for 90 minutes. Desk: your call.")
}

@Test func someDaysReadsMondayFirst() {
    var kind = IntermissionKind.defaults.first { $0.id == "call" }!
    kind.cadence = .days([.friday, .monday, .sunday])
    #expect(kind.rule.contains("on Mon, Fri, Sun"))
}

@Test func aCadenceSavedByTheOldModelStillReads() throws {
    // settings.json written before "some days" existed: one weekday, in
    // Swift's synthesised shape.
    // Weekday is an Int enum, so the old file has its raw value.
    let json = #"{"weekly":{"_0":5}}"#.data(using: .utf8)!
    let cadence = try JSONDecoder().decode(IntermissionKind.Cadence.self, from: json)
    #expect(cadence == .days([.thursday]))
}

@Test func aCadenceRoundTrips() throws {
    for cadence in [IntermissionKind.Cadence.daily, .twiceDaily, .days([.monday, .friday])] {
        let data = try JSONEncoder().encode(cadence)
        #expect(try JSONDecoder().decode(IntermissionKind.Cadence.self, from: data) == cadence)
    }
}

@Test func anIntermissionSavedBeforeV4StillReads() throws {
    // The stored `rule` and the missing `role` are both fine: one is
    // generated now, the other has a default.
    let json = """
    {"id":"lunch","name":"Lunch","minutes":50,"minimumMinutes":25,
     "cadence":{"daily":{}},"preference":{"around":{"_0":750}},
     "deskRule":"any","rule":"First gap of 45 min or more after the target time.",
     "enabled":true,"colorToken":"chart-5"}
    """.data(using: .utf8)!
    let kind = try JSONDecoder().decode(IntermissionKind.self, from: json)
    #expect(kind.role == .dailyBreak)
    #expect(kind.colorToken == "chart-5")          // a colour he chose is his
    #expect(kind.rule.hasPrefix("50 min (25 if the day is tight)"))
}

@Test func daysDecideWhetherABreakRunsToday() {
    var kind = IntermissionKind.defaults.first { $0.id == "call" }!
    kind.cadence = .days([.wednesday])
    #expect(kind.runs(on: day(23), calendar: calendar))      // Wednesday
    #expect(!kind.runs(on: day(22), calendar: calendar))     // Tuesday
}

@Test func aGoalNeverRunsOnItsOwn() {
    let writing = IntermissionKind.defaults.first { $0.id == "writing" }!
    #expect(!writing.runs(on: day(22), calendar: calendar))
    #expect(writing.placementsPerDay == 0)
}

@Test func twiceDailyMeansTwoPlacements() {
    let stretch = IntermissionKind.defaults.first { $0.id == "stretch" }!
    #expect(stretch.placementsPerDay == 2)
    #expect(IntermissionKind.defaults.first { $0.id == "lunch" }!.placementsPerDay == 1)
}

// MARK: - The file on disk, written by an older app

@Test func settingsWrittenBeforeV4KeepEverythingCarlChose() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    // A settings.json as the previous build wrote it: no version, no buffer,
    // no roles, and four intermissions.
    let json = """
    {"askWhatABreakWas":true,"calendarIDs":["a-calendar-id"],"deskDays":[2,3,4,6],
     "endOfDaySummary":true,"eveningPlan":true,"idleMinutes":10,"intermissions":[
       {"cadence":{"daily":{}},"colorToken":"chart-5","deskRule":"any","enabled":true,
        "id":"lunch","minimumMinutes":25,"minutes":50,"name":"Lunch",
        "preference":{"around":{"_0":750}},"rule":"First gap after the target time."},
       {"cadence":{"daily":{}},"colorToken":"chart-3","deskRule":"down","enabled":false,
        "id":"reading","minutes":30,"name":"Reading","preference":{"afternoon":{}},
        "rule":"Largest remaining gap."},
       {"cadence":{"weekly":{"_0":5}},"colorToken":"chart-7","deskRule":"any","enabled":true,
        "id":"call","minutes":20,"name":"Call a friend","preference":{"lateAfternoon":{}},
        "rule":"Any gap of 20 min or more."},
       {"cadence":{"twiceDaily":{}},"colorToken":"desk-6","deskRule":"up","enabled":true,
        "id":"custom-walk","minutes":15,"name":"Walk outside","preference":{"afternoon":{}},
        "rule":"Yours. Placed in a gap that fits it."},
       {"cadence":{"days":{"_0":[5]}},"colorToken":"chart-6","deskRule":"any","enabled":true,
        "id":"custom-writing","minutes":20,"name":"Writing","preference":{"afternoon":{}},
        "rule":"Yours. Placed in a gap that fits it."}],
     "listenToDesk":true,"morningPlan":true,"remindForNotes":true,"settleMinutes":10,
     "sound":true,"standingGoal":0.25,"standingThreshold":40.5,"tone":"playful"}
    """
    try json.write(to: url, atomically: true, encoding: .utf8)

    let settings = SettingsStore(url: url).load()

    // His own settings survive, which is the whole point.
    #expect(settings.standingGoal == 0.25)
    #expect(settings.standingThreshold == 40.5)
    #expect(settings.idleMinutes == 10)
    #expect(settings.deskDays == [.monday, .tuesday, .wednesday, .friday])
    #expect(settings.calendarIDs == ["a-calendar-id"])

    // The new fields arrive at their defaults.
    #expect(settings.bufferMinutes == 10)
    #expect(settings.onCalendarChange == .ask)
    #expect(settings.calendarEventMode == .guessFromTitle)
    #expect(settings.version == Settings.currentVersion)

    // The built-ins are v4's: reading is a goal, lunch is amber, the call is
    // on the days he picked - but reading stays switched off, because that
    // was his answer, not the design's.
    let reading = settings.intermissions.first { $0.id == "reading" }
    #expect(reading?.role == .weeklyGoal)
    #expect(reading?.perWeek == 3)
    #expect(reading?.enabled == false)
    #expect(settings.intermissions.first { $0.id == "lunch" }?.colorToken == "chart-8")
    #expect(settings.intermissions.first { $0.id == "writing" } != nil)     // new, and added

    // The Writing he'd made himself becomes the built-in goal, and keeps the
    // colour he gave it. Two Writings on one screen is one too many.
    let writings = settings.intermissions.filter { $0.name == "Writing" }
    #expect(writings.count == 1)
    #expect(writings.first?.role == .weeklyGoal)
    #expect(writings.first?.colorToken == "chart-6")
    #expect(writings.first?.minutes == 45)

    // What Carl made himself is untouched.
    let walk = settings.intermissions.first { $0.id == "custom-walk" }
    #expect(walk?.name == "Walk outside")
    #expect(walk?.colorToken == "desk-6")
    #expect(walk?.minutes == 15)
    #expect(walk?.deskRule == .up)
    #expect(walk?.cadence == .twiceDaily)
}

@Test func migratingHappensOnceAndLeavesLaterChoicesAlone() {
    var settings = Settings()
    settings.version = 0
    settings.migrate()
    #expect(settings.version == Settings.currentVersion)

    // He picks a different colour for lunch afterwards.
    if let index = settings.intermissions.firstIndex(where: { $0.id == "lunch" }) {
        settings.intermissions[index].colorToken = "desk-5"
    }
    settings.migrate()      // a no-op now
    #expect(settings.intermissions.first { $0.id == "lunch" }?.colorToken == "desk-5")
}

// MARK: - When a reminder is allowed to make a noise

@Test func aReminderStaysQuietWhileASessionIsRunning() {
    var settings = Settings()
    settings.sound = true
    #expect(settings.soundAllowed(inSession: false, micInUse: false))
    #expect(!settings.soundAllowed(inSession: true, micInUse: false))
    // The hour that was booked until twelve and is still going at ten past:
    // the schedule says it's over, the microphone says otherwise.
    #expect(!settings.soundAllowed(inSession: false, micInUse: true))
}

@Test func soundOffMeansOffEitherWay() {
    var settings = Settings()
    settings.sound = false
    #expect(!settings.soundAllowed(inSession: false, micInUse: false))
}

@Test func theQuietRuleCanBeTurnedOff() {
    var settings = Settings()
    settings.sound = true
    settings.silentInSession = false
    #expect(settings.soundAllowed(inSession: true, micInUse: true))
}

// MARK: - When the port is held open

@Test func thePortClosesForASessionAndOpensAfterIt() {
    var settings = Settings()
    settings.listenToDesk = true
    #expect(settings.listening(inSession: false, micInUse: false))
    #expect(!settings.listening(inSession: true, micInUse: false))
    #expect(!settings.listening(inSession: false, micInUse: true))
}

@Test func theMasterSwitchStillWins() {
    var settings = Settings()
    settings.listenToDesk = false
    #expect(!settings.listening(inSession: false, micInUse: false))

    settings.listenToDesk = true
    settings.closePortInSession = false
    #expect(settings.listening(inSession: true, micInUse: true))
}

// MARK: - The one colour that isn't from the palette

@Test func aCalendarColourIsKeptAndCanBeCleared() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = SettingsStore(url: url)
    var settings = Settings()
    #expect(settings.calendarColor == nil)          // the palette's terracotta

    settings.calendarColor = "#3A7D8C"
    store.save(settings)
    #expect(store.load().calendarColor == "#3A7D8C")

    settings.calendarColor = nil
    store.save(settings)
    #expect(store.load().calendarColor == nil)
}
