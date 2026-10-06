import AppKit
import DeskCore
import Foundation
import Observation
import SwiftUI

/// Everything the views read, and the one place the pieces meet: the adapter,
/// the day's tally, the coach, the session file and settings.
///
/// The desk is never written to. The adapter's transmit line isn't even
/// connected, and nothing here opens the port for writing - the box reports
/// height by itself while the desk moves. Sending anything makes the handset
/// click and light up, which is exactly what this app must not do.
/// Where everything lives. Outside the model so tools like --dump-plan can
/// read it without touching the main actor.
enum Paths {
    static let support = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/com.carlwilliamson.intermission")
    static let sessions = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/com.carlwilliamson.practicestudio/desk-reminder/sessions.json")
}

@MainActor
@Observable
final class AppModel {
    enum View: String, CaseIterable { case plan, week, today, settings }
    enum PlanDay: String, CaseIterable, Identifiable {
        case today, tomorrow
        var id: String { rawValue }
        var title: String { self == .today ? "Today" : "Tomorrow" }
    }

    static var supportDirectory: URL { Paths.support }
    static var sessionsFile: URL { Paths.sessions }

    var selectedView: View = .today
    private(set) var adapterStatus: SerialMonitor.Status = .adapterNotFound
    private(set) var lastReport: Date?
    private(set) var timeline: DeskTimeline
    private(set) var today: DayRecord
    private(set) var isPresent = false
    private(set) var computer: ComputerLog
    private(set) var heights: HeightLog
    private(set) var plan: [PlanBlock] = []
    /// The day the Plan view is showing. In the evening it opens on tomorrow.
    var planDay: PlanDay = .today { didSet { rebuildPlan() } }
    private(set) var shownPlan: [PlanBlock] = []
    private(set) var shownEvents: [CalendarEvent] = []
    /// True when the schedule has changed since this day's plan was committed.
    private(set) var scheduleMovedSincePlanning = false
    private(set) var phase: Phase = .open
    private(set) var events: [CalendarEvent] = []
    /// The break Carl came back from that nobody has named yet.
    private(set) var breakToLabel: ComputerSegment?
    private(set) var startedIntermissions: Set<String> = []
    /// Updated every tick so countdowns move without each view keeping a timer.
    private(set) var now = Date()
    private(set) var skippedIntermissions: Set<String> = []
    /// Intermissions already announced today, so each is said once.
    private var announcedIntermissions: Set<String> = []
    /// Today's daily breaks that wouldn't fit anywhere.
    private(set) var unplacedToday: [IntermissionKind] = []
    /// This week's goal placements, and the goal Week has selected.
    private(set) var weekPlan: WeekPlan
    var selectedGoalID: String?
    /// Time that has opened up, and what could be done with it. Nothing
    /// moves until Carl picks one of the options.
    private(set) var rebalance: Rebalance?
    /// Which option is chosen in the banner.
    var rebalanceChoice: String = ""
    /// What was done with the freed time, and how to take it back.
    private(set) var rebalanceStrip: RebalanceStrip?
    /// The card being edited in Settings.
    var editingIntermissionID: String?
    let calendars = Calendars()
    var settings: DeskCore.Settings { didSet { settingsChanged(oldValue) } }

    private var coach: Coach
    private var days: DayStore
    private var plans: PlanStore
    private var weeks: WeekPlanStore
    private let logs: LogStore
    private var schedule: SessionSchedule
    private let settingsStore: SettingsStore
    private let presence = Presence()
    private let notifier = Notifier()
    private let serialLog = SerialLogFile()
    private var monitor: SerialMonitor?
    private var lastCheck = Date()
    private var lastSaved = Date.distantPast
    /// The schedule as it was on the last tick, for noticing a change.
    private var lastSignature = ""
    /// When the port was last opened or closed, so it can't flap.
    private var lastPortChange = Date.distantPast
    /// Laid-out days and their calendar events, dropped on every rebuild.
    private var planCache: [Date: [PlanBlock]] = [:]
    private var eventCache: [Date: [CalendarEvent]] = [:]
    private var snoozedUntil: Date?
    private var currentDay: Date

    init() {
        let store = SettingsStore(url: Self.supportDirectory.appending(path: "settings.json"))
        let settings = store.load()
        self.settingsStore = store
        self.settings = settings
        self.coach = Coach(settings: settings)
        self.days = DayStore(url: Self.supportDirectory.appending(path: "days.json"))
        self.plans = PlanStore(url: Self.supportDirectory.appending(path: "plans.json"))
        let weeks = WeekPlanStore(url: Self.supportDirectory.appending(path: "weeks.json"))
        self.weeks = weeks
        self.weekPlan = weeks[Date()]
        self.logs = LogStore(url: Self.supportDirectory.appending(path: "logs.json"))
        let saved = logs.load()
        self.heights = saved.heights
        self.computer = saved.computer
        self.schedule = SessionSchedule(url: Self.sessionsFile)
        self.timeline = DeskTimeline(
            standingThreshold: settings.standingThreshold,
            assumedHeight: LastHeight.load(directory: Self.supportDirectory)
        )
        let startOfDay = Calendar.current.startOfDay(for: Date())
        self.currentDay = startOfDay
        self.today = DayRecord(day: startOfDay)

        // Every stored property is set; now self is usable.
        self.today = days[startOfDay]
        presence.idleThreshold = TimeInterval(settings.idleMinutes * 60)

        recomputeRecentDays()
        notifier.requestAuthorization()
        if ProcessInfo.processInfo.environment["INTERMISSION_TEST_NOTIFY"] != nil {
            notifier.post("Test notification from Intermission.", sound: true)
        }
        notifier.onAction = { [weak self] action in self?.handle(action) }
        // For checking a screen without clicking through to it.
        if let name = ProcessInfo.processInfo.environment["INTERMISSION_VIEW"],
           let view = View(rawValue: name) {
            selectedView = view
        }
        if let day = ProcessInfo.processInfo.environment["INTERMISSION_PLAN_DAY"],
           let planDay = PlanDay(rawValue: day) {
            self.planDay = planDay
        }
        schedule.reload()
        start()
        watchCalendars()
    }

    /// The calendar, at launch and whenever it changes.
    ///
    /// Never asked means ask - macOS puts its own prompt up once, and that's
    /// the whole permission dance. Said-no means say so, which is what
    /// `calendarTrouble` is for: there's nothing this app can do about a
    /// switch that lives in System Settings except point at it.
    private func watchCalendars() {
        if calendars.isUndecided {
            Task { @MainActor in
                await calendars.requestAccess()
                rebuildPlan()
            }
        }
        // And once, out loud, a few seconds in - long enough for the system
        // prompt to have been answered. He shouldn't have to open the window
        // to find out the calendar has fallen off.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, let trouble = self.calendarTrouble else { return }
            self.notifier.post("\(trouble.text) Open Intermission to put it right.", sound: false)
        }
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.calendars.refreshAuthorization()
                self?.rebuildPlan()
            }
        }
    }

    /// What's wrong with the calendar, if anything: something to put in front
    /// of him rather than leave him to find in Settings.
    var calendarTrouble: (text: String, action: String)? {
        if calendars.isDenied {
            return (
                "Intermission can't see your calendars, so nothing from them is in the plan.",
                "Open Privacy settings"
            )
        }
        guard calendars.authorized else { return nil }
        if settings.calendarIDs.isEmpty {
            return ("No calendars are switched on, so nothing from them is in the plan.", "Choose calendars")
        }
        return nil
    }

    /// The button on that warning.
    func fixCalendarTrouble() {
        if calendars.isDenied {
            Calendars.openPrivacySettings()
        } else {
            selectedView = .settings
        }
    }

    var height: Double? { timeline.height }
    var heightIsAssumed: Bool { timeline.heightIsAssumed }
    var isStanding: Bool? { timeline.isStanding }

    /// The menu-bar title: live height, remembered height with a "~", or a dash.
    var menuBarTitle: String {
        let paused = settings.paused(at: Date()) ? " ⏸" : ""
        guard let height else { return "↕ —" + paused }
        let mark = heightIsAssumed ? "~" : ""
        let glyph = isStanding == true && !heightIsAssumed ? "🧍" : "↕"
        return "\(glyph) \(mark)\(String(format: "%.1f", height))″" + paused
    }

    private func startListening() {
        guard monitor == nil else { return }
        let log: SerialLogFile? = settings.logSerialTraffic ? serialLog : nil
        log?.note("port opening")

        var sink: (@Sendable ([UInt8], Date) -> Void)?
        if let log {
            sink = { bytes, at in log.bytes(bytes, at: at) }
        }

        let monitor = SerialMonitor(
            onHeight: { [weak self] height, at in
                Task { @MainActor in self?.heightReported(height, at: at) }
            },
            onStatus: { [weak self] status in
                log?.note("adapter: \(status.detail)")
                Task { @MainActor in self?.adapterStatus = status }
            },
            onBytes: sink
        )
        monitor.start()
        self.monitor = monitor
    }

    /// Opens and closes the port around sessions.
    ///
    /// The handset wakes up now and then - a click and a lit screen - and
    /// the likeliest cause is this app's tap sitting on the line the box
    /// talks to it on. Whatever the cause, a client's hour is the worst time
    /// for it, and the port is worth almost nothing during one: the desk is
    /// down, and the box only speaks while the desk moves.
    ///
    /// A minute has to pass before it changes its mind again, so a
    /// microphone that flickers can't turn the port into a metronome.
    private func followTheSessionWithThePort(_ now: Date) {
        let wanted = settings.listening(inSession: isInSession, micInUse: isInCall)
        guard wanted != (monitor != nil) else { return }
        guard now.timeIntervalSince(lastPortChange) >= 60 else { return }
        lastPortChange = now
        wanted ? startListening() : stopListening()
    }

    private func stopListening() {
        if settings.logSerialTraffic, monitor != nil {
            serialLog.note("port closing\(isInSession ? " — session" : isInCall ? " — microphone live" : "")")
        }
        monitor?.stop()
        monitor = nil
        adapterStatus = .adapterNotFound
    }

    private func start() {
        if settings.listenToDesk { startListening() }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    // MARK: - The loop

    private func heightReported(_ height: Double, at now: Date) {
        lastReport = now
        if settings.logSerialTraffic { serialLog.note(String(format: "height %.1f\"", height), at: now) }
        timeline.report(height: height, at: now)
        heights.record(standing: height >= settings.standingThreshold, at: now)
        LastHeight.save(height, directory: Self.supportDirectory)
        if let outcome = coach.heightChanged(height, at: now) { record(outcome) }
    }

    private func tick() {
        let now = Date()
        self.now = now
        rolloverIfNeeded(now)

        // Cheap enough to ask every second: it's a device property, not the
        // audio itself.
        isInCall = Microphone.isInUse
        followTheSessionWithThePort(now)

        let present = presence.isPresent
        if present != isPresent {
            isPresent = present
            timeline.setPresent(present, at: now)
        }
        // The log only hears about the desk when it moves, so a day that
        // starts with the desk already up had nothing in it until the first
        // move. The remembered height opens the first stretch instead.
        if heights.current == nil, let standing = isStanding {
            heights.record(standing: standing, at: now)
        }
        timeline.tick(now)
        syncTodayFromTimeline()
        saveIfDue(now)
        computer.setOnComputer(present, at: now)
        // Away during a session? That was the session. Named before the
        // prompt looks, so it never asks about a client's hour.
        computer.labelSessions(schedule.sessions(on: currentDay), now: now)
        // And time away that ran past the end of the day was going home.
        let published = schedule
        computer.labelDayEnds(closing: { Self.closeOfBusiness(on: $0, in: published) }, now: now)
        // A stretch the prompt is already asking about can be claimed by
        // one of those passes; the question has answered itself.
        if let asked = breakToLabel, computer.segment(startingAt: asked.start)?.label != nil {
            breakToLabel = nil
        }
        if settings.askWhatABreakWas, breakToLabel == nil, present {
            breakToLabel = computer.unlabelledBreaks().first
        }
        if plan.isEmpty { rebuildPlan() }
        phase = Phase.current(
            plan: plan, kinds: settings.intermissions, now: now,
            startedIntermissions: startedIntermissions
        )

        schedule.reload()
        // The day changing under a plan is the third thing that opens time
        // up, alongside a cancellation and an early finish.
        let signature = schedule.sessions(on: currentDay).signature
        if signature != lastSignature {
            let hadOne = !lastSignature.isEmpty
            lastSignature = signature
            if hadOne {
                rebuildPlan()
                offerRebalance(
                    .calendarChanged,
                    reason: "Your day has changed since you planned it.",
                    edit: nil
                )
            }
        }
        let inSession = schedule.session(covering: now) != nil || schedule.isDayOff(now)
        for _ in schedule.endings(after: lastCheck, until: now) {
            // Every session ends in a standing note, virtual included.
            let (message, outcome) = coach.sessionEnded(at: now, inSession: inSession)
            if let outcome { record(outcome) } else if let message { say(message) }
        }
        lastCheck = now

        if let until = snoozedUntil, now >= until {
            snoozedUntil = nil
            if coach.isStanding != true { say(.stillSitting) }
        }

        announceIntermissionIfDue(now)
        offerTomorrowIfDayIsDone(now)
        summariseDayIfDone(now)

        let (message, outcome) = coach.tick(at: now)
        if let message, snoozedUntil == nil { say(message) }
        if let outcome { record(outcome) }
        if let goal = coach.goalCrossed(share: today.standingShare, at: now) { say(goal) }
    }

    private func rolloverIfNeeded(_ now: Date) {
        let startOfDay = Calendar.current.startOfDay(for: now)
        guard startOfDay != currentDay else { return }
        days.save()
        recomputeRecentDays()      // settle yesterday before moving on
        currentDay = startOfDay
        coach.newDay()
        today = days[now]
        startedIntermissions = []
        skippedIntermissions = []
        announcedIntermissions = []
        planDay = .today
        computer.prune(before: startOfDay.addingTimeInterval(-7 * 86_400))
        heights.prune(before: startOfDay.addingTimeInterval(-7 * 86_400))
        logs.save(heights: heights, computer: computer)
        rebuildPlan()
        if settings.morningPlan && settings.isDeskDay(now) { selectedView = .plan }
    }

    /// Totals are written once a minute. They used to reach disk only when a
    /// note was recorded or the day rolled over, so every restart threw away
    /// the standing time since - which is why the numbers read zero.
    private func saveIfDue(_ now: Date) {
        guard now.timeIntervalSince(lastSaved) >= 60 else { return }
        lastSaved = now
        days.save()
        logs.save(heights: heights, computer: computer)
    }

    /// The day's totals, worked out from the logs each tick.
    ///
    /// They used to be counted up by a timeline living in memory, so every
    /// relaunch started from zero AND wrote those zeros over the saved day.
    /// The logs persist, so this is the same answer whatever the app has been
    /// doing.
    /// Re-derives the last week's totals from the logs.
    ///
    /// A day's numbers used to be whatever the running tally happened to have
    /// when it last saved, which is how yesterday ended up claiming zero
    /// standing. The logs are the record; anything they cover is recomputed
    /// from them. A day they don't cover is left alone rather than zeroed.
    private func recomputeRecentDays() {
        let calendar = Calendar.current
        for back in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: currentDay) else { continue }
            let logged = heights.segments(on: day).isEmpty == false
            guard logged else { continue }
            let totals = deskTotals(
                heights: heights, computer: computer,
                sessions: schedule.sessions(on: day),
                on: day, now: calendar.date(byAdding: .day, value: 1, to: day) ?? Date()
            )
            days.update(day) {
                $0.standing = totals.standing
                $0.sitting = totals.sitting
            }
        }
        days.save()
    }

    private func syncTodayFromTimeline() {
        let totals = deskTotals(
            heights: heights,
            computer: computer,
            sessions: schedule.sessions(on: currentDay),
            on: currentDay,
            now: now
        )
        days.update(currentDay) {
            $0.standing = totals.standing
            $0.sitting = totals.sitting
            $0.inSession = inSessionToday
            $0.isDeskDay = settings.isDeskDay(currentDay)
            // Every session that has ended is a note owed, whether or not the
            // app was running when it ended.
            $0.notesTotal = schedule.sessions(on: currentDay).count { $0.end <= now }
        }
        today = days[currentDay]
    }

    private func record(_ outcome: Coach.Outcome) {
        days.update(outcome.at) { if outcome.stood { $0.notesStanding += 1 } }
        today = days[currentDay]
        days.save()
    }

    private func say(_ message: CoachMessage, category: String = Notifier.category) {
        notifier.post(
            CoachCopy(tone: settings.tone).text(for: message),
            sound: settings.soundAllowed(inSession: isInSession, micInUse: isInCall),
            category: category
        )
    }

    /// A session is running, as far as Practice Studio knows.
    var isInSession: Bool { schedule.session(covering: now) != nil }

    /// Something is using a microphone - a call is happening, whether or not
    /// it's the one in the diary and whether or not it has finished on paper.
    private(set) var isInCall = false

    var hasSerialLog: Bool { FileManager.default.fileExists(atPath: SerialLogFile.url.path) }

    /// "12 KB so far", for the line under the switch.
    var serialLogSize: String {
        let size = (try? FileManager.default.attributesOfItem(atPath: SerialLogFile.url.path)[.size]) as? Int
        guard let size, size > 0 else { return "Nothing logged yet." }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) + " so far."
    }

    func revealSerialLog() {
        NSWorkspace.shared.activateFileViewerSelecting([SerialLogFile.url])
    }

    /// Whether the serial port is open at this moment.
    var isListening: Bool { monitor != nil }

    /// Opens the window on tomorrow's plan - what the evening notification does.
    func showTomorrow() {
        planDay = .tomorrow
        selectedView = .plan
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handle(_ action: Notifier.Action) {
        switch action {
        case .snooze: snoozedUntil = Date().addingTimeInterval(600)
        case .pauseToday: pause(until: Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)))
        case .planTomorrow: showTomorrow()
        }
    }

    // MARK: - Plan and intermissions

    var shownDate: Date {
        planDay == .today ? Date() : Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    func rebuildPlan() {
        schedule.reload()
        planCache = [:]
        eventCache = [:]
        weekPlan = weeks[Date()]
        plan = blocks(for: Date())
        events = calendarEvents(on: Date())

        // Nothing is "unplaced" on a day the planner wasn't placing into.
        unplacedToday = isDeskDay(Date()) ? planner().unplaced(in: plan, on: Date()) : []

        let shown = shownDate
        shownPlan = planDay == .today ? plan : blocks(for: shown)
        shownEvents = planDay == .today ? events : calendarEvents(on: shown)

        matchSlotsToPlacedGoals()

        let saved = plans[shown]
        scheduleMovedSincePlanning = saved.committedAt != nil
            && !saved.scheduleSignature.isEmpty
            && saved.scheduleSignature != schedule.sessions(on: shown).signature
    }

    /// Keeps the week's list and the day's plan telling the same story.
    ///
    /// A goal can reach a day by being dropped in Week, filled into a gap, or
    /// dragged around the timeline. Only the first of those wrote a slot, so
    /// the other two left a block on the day that the week's count knew
    /// nothing about.
    private func matchSlotsToPlacedGoals() {
        for day in [currentDay, Calendar.current.date(byAdding: .day, value: 1, to: currentDay)]
            .compactMap({ $0 }) {
            var week = weeks[day]
            var changed = false
            for block in blocks(for: day) where block.isGoal {
                guard let id = block.intermissionID, week.slot(for: id, on: day) == nil else { continue }
                week.place(id, on: day, at: block.start)
                changed = true
            }
            guard changed else { continue }
            weeks[day] = week
            weeks.save()
            planCache.removeValue(forKey: Calendar.current.startOfDay(for: day))
        }
        weekPlan = weeks[Date()]
    }

    /// The planner, set up from the settings as they are now.
    private func planner() -> Planner {
        Planner(
            intermissions: settings.intermissions.filter { !skippedIntermissions.contains($0.id) },
            settleMinutes: settings.settleMinutes,
            bufferMinutes: settings.bufferMinutes,
            calendarEventMode: settings.calendarEventMode
        )
    }

    /// The plan for a day: its sessions and events, the goals Carl has put on
    /// it, and whatever else he's already changed about it.
    ///
    /// Cached per day and thrown away whenever anything is rebuilt. Views ask
    /// for this constantly - the Week grid wants seven days, the goal tray
    /// asks each goal where it would fit - and every answer used to lay the
    /// day out again and query the calendar store, once a second.
    func blocks(for day: Date) -> [PlanBlock] {
        let key = Calendar.current.startOfDay(for: day)
        if let cached = planCache[key] { return cached }
        // Every day gets laid out, including the ones he doesn't work: he's
        // often at the desk on a Thursday, and a blank Plan with no hours,
        // no red line and nowhere to add anything is no use to him. What a
        // rest day doesn't get is breaks placed into it.
        // And not into a day that's already been: what a past Tuesday shows
        // is what happened on it, not what this morning's rules would have
        // suggested for it.
        let today = Calendar.current.startOfDay(for: now)
        let placeBreaks = !schedule.isDayOff(day) && settings.isDeskDay(day)
            && Calendar.current.startOfDay(for: day) >= today
        let blocks = planner().plan(
            sessions: schedule.sessions,
            events: calendarEvents(on: day),
            on: day,
            edits: plans[day].edits,
            goalSlots: weeks[day].slots(on: day),
            placeBreaks: placeBreaks,
            configuredHours: dayHours(on: day),
            workingWindows: schedule.workingWindows(on: day)
        )
        planCache[key] = blocks
        return blocks
    }

    /// A day as the Week grid draws it: the plan, plus the breaks the log
    /// says actually happened.
    ///
    /// A past day has nothing placed into it, so without this a Monday shows
    /// its sessions and an empty afternoon - when the log knows perfectly
    /// well that lunch was at 12:41.
    func weekBlocks(on day: Date) -> [PlanBlock] {
        let planned = blocks(for: day)
        guard Calendar.current.startOfDay(for: day) < Calendar.current.startOfDay(for: now) else {
            return planned
        }
        let placed = Set(planned.compactMap(\.intermissionID))
        return planned + recordedBreaks(on: day).filter { block in
            block.intermissionID.map { !placed.contains($0) } ?? true
        }
    }

    /// Time away from the computer that Carl named, as blocks.
    func recordedBreaks(on day: Date) -> [PlanBlock] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return computer.segments.compactMap { segment -> PlanBlock? in
            guard !segment.isOnComputer, let label = segment.label,
                  label != ComputerLog.sessionLabel,
                  label != ComputerLog.declinedLabel,
                  label != ComputerLog.dayEndLabel
            else { return nil }
            let start = max(segment.start, dayStart)
            let end = min(segment.end ?? now, dayEnd)
            guard end > start, start < dayEnd, end > dayStart else { return nil }
            let kind = settings.intermissions.first { $0.name.caseInsensitiveCompare(label) == .orderedSame }
            return PlanBlock(
                kind: .intermission(id: kind?.id ?? "logged-\(label.lowercased())"),
                start: start, end: end,
                title: label,
                subline: "Recorded",
                badge: "Happened",
                isMine: true,
                isGoal: kind?.isGoal ?? false
            )
        }
    }

    /// A day's calendar events, read once per rebuild.
    private func calendarEvents(on day: Date) -> [CalendarEvent] {
        let key = Calendar.current.startOfDay(for: day)
        if let cached = eventCache[key] { return cached }
        let events = calendars.events(on: day, calendarIDs: settings.calendarIDs)
        eventCache[key] = events
        return events
    }

    /// The hours a day's plan covers, for the timeline and the Week grid.
    func planWindow(for day: Date) -> DateInterval {
        planner().workday(
            sessions: schedule.sessions(on: day),
            events: calendarEvents(on: day),
            on: day,
            configuredHours: dayHours(on: day)
        )
    }

    /// The day on screen: Practice Studio's hours, opened out to the time he
    /// actually gets in. His first session is at ten and he's at the desk by
    /// half seven, and a plan that starts at ten is missing the part of the
    /// morning he can do something about.
    private func dayHours(on day: Date) -> DateInterval {
        let calendar = Calendar.current
        let published = schedule.workingHours(on: day)
        let opens = calendar.date(
            bySettingHour: settings.dayStartsMinutes / 60,
            minute: settings.dayStartsMinutes % 60, second: 0, of: day
        ) ?? day
        let closes = published?.end
            ?? calendar.date(bySettingHour: Planner.dayEndHour, minute: 0, second: 0, of: day)
            ?? opens.addingTimeInterval(8 * 3600)
        let start = min(opens, published?.start ?? opens)
        return DateInterval(start: start, end: max(closes, start.addingTimeInterval(3600)))
    }

    var isPlanCommitted: Bool { plans[shownDate].committedAt != nil }
    /// When today's plan was committed, for the sidebar - "8:04" says it was
    /// planned far better than a count of breaks does.
    var planCommittedAt: Date? { plans[Date()].committedAt }

    /// "Skip planning today": the day runs with no suggestions at all.
    func skipPlanning() {
        for block in shownPlan {
            guard let id = block.intermissionID else { continue }
            if block.isGoal {
                removeGoal(id, on: shownDate)
            } else {
                apply(.skipped, to: id)
            }
        }
        if planDay == .today { selectedView = .today }
    }

    func commitShownPlan() {
        var day = plans[shownDate]
        day.committedAt = Date()
        day.scheduleSignature = schedule.sessions(on: shownDate).signature
        // Starting the day with this plan pins what's in it. Until now the
        // whole day was laid out again on every rebuild, so a session moving
        // at noon could quietly shuffle the afternoon's breaks; from here
        // they stay where he agreed to them, and the rebalance banner is the
        // only thing that offers to change that.
        for block in shownPlan where block.isSuggestion && !block.isMine && !block.isGoal {
            guard let id = block.intermissionID else { continue }
            day.apply(PlanEdit(intermissionID: id, change: .pinned(to: block.start)))
            if block.isShortened {
                day.apply(PlanEdit(intermissionID: id, change: .resized(minutes: Int(block.length / 60))))
            }
        }
        plans[shownDate] = day
        plans.save()
        rebuildPlan()
        if planDay == .today { selectedView = .today }
    }

    func apply(_ change: PlanEdit.Change, to intermissionID: String) {
        var day = plans[shownDate]
        day.apply(PlanEdit(intermissionID: intermissionID, change: change))
        plans[shownDate] = day
        plans.save()
        // A goal dragged onto the plan is a goal he did this week, wherever
        // he put it from. Without this the block sat on the day while the
        // tray still said none were planned.
        if case .moved(let start) = change,
           settings.intermissions.first(where: { $0.id == intermissionID })?.isGoal == true {
            var week = weeks[shownDate]
            week.place(intermissionID, on: shownDate, at: start)
            weeks[shownDate] = week
            weeks.save()
        }
        rebuildPlan()
    }

    /// Fill an empty stretch with something.
    ///
    /// It takes the WHOLE gap, not the intermission's usual length: an eighty
    /// minute hole filled with lunch is eighty minutes of lunch, and the
    /// bottom edge is there to shrink it. Clamping it to fifty and making him
    /// stretch it back was the wrong way round.
    func fill(_ gap: PlanBlock, with kind: IntermissionKind) {
        // A goal goes on the day through the week's own list, or it wouldn't
        // count towards the week.
        if kind.isGoal {
            placeGoal(kind.id, on: shownDate, at: gap.start)
            return
        }
        let minutes = max(5, Int(gap.length / 60))
        if settings.intermissions.contains(where: { $0.id == kind.id }) {
            apply(.moved(to: gap.start), to: kind.id)
            apply(.resized(minutes: minutes), to: kind.id)
        } else {
            addOneOff(name: kind.name, minutes: minutes, at: gap.start)
        }
    }

    /// What can go in a gap: anything switched on, since filling is his
    /// choice rather than the planner's. Longest first, as a hint at fit.
    func candidates(for gap: PlanBlock) -> [IntermissionKind] {
        guard gap.length >= 5 * 60 else { return [] }
        return settings.intermissions.filter(\.enabled).sorted { $0.minutes > $1.minutes }
    }

    /// Nudging a block with the keyboard, for when a drag is the wrong tool.
    func nudge(_ intermissionID: String, byMinutes minutes: Int) {
        guard let block = shownPlan.first(where: { $0.kind == .intermission(id: intermissionID) }) else { return }
        apply(.moved(to: block.start.addingTimeInterval(TimeInterval(minutes * 60))), to: intermissionID)
    }

    /// A one-off belongs to its day, so removing it means forgetting the
    /// edit. A regular intermission is skipped for the day instead.
    func isOneOff(_ intermissionID: String) -> Bool {
        !settings.intermissions.contains { $0.id == intermissionID }
    }

    func removeFromPlan(_ intermissionID: String) {
        let block = shownPlan.first { $0.intermissionID == intermissionID }
        if block?.isGoal == true {
            // A goal isn't skipped, it's taken off the day and goes back to
            // the tray for another one.
            removeGoal(intermissionID, on: shownDate)
        } else if isOneOff(intermissionID) {
            undoEdits(for: intermissionID)
        } else {
            apply(.skipped, to: intermissionID)
        }
        // Skipping a ten-minute stretch is a shrug; skipping lunch leaves
        // most of an hour, and that's worth offering back.
        guard planDay == .today, let block,
              Int(block.length / 60) >= settings.rebalanceAfterSkipMinutes
        else { return }
        offerRebalance(
            .skipped(id: intermissionID, name: block.title),
            reason: "You skipped \(block.title.lowercased()).",
            edit: nil,
            opened: DateInterval(start: block.start, end: block.end)
        )
    }

    /// Drops a recurring intermission from the list for good.
    func deleteIntermission(_ intermissionID: String) {
        settings.intermissions.removeAll { $0.id == intermissionID }
    }

    func undoEdits(for intermissionID: String) {
        var day = plans[shownDate]
        day.clearEdits(for: intermissionID)
        plans[shownDate] = day
        plans.save()
        rebuildPlan()
    }

    func addOneOff(name: String, minutes: Int, at start: Date) {
        apply(.added(name: name, minutes: minutes, at: start), to: "custom-\(UUID().uuidString.prefix(8))")
    }

    /// The colour calendar events are drawn in: his if he's picked one.
    var calendarColor: Color {
        settings.calendarColor.flatMap { Theme.color(hex: $0) } ?? Theme.calendar
    }

    /// The colour for a block, with the intermission's own choice honoured.
    func color(for kind: PlanBlock.Kind) -> Color {
        switch kind {
        case .session: Theme.session
        case .note: Theme.standing
        case .calendarEvent: calendarColor
        case .open: Theme.border
        case .intermission(let id):
            settings.intermissions.first { $0.id == id }
                .map { Theme.color(token: $0.colorToken) } ?? Theme.primary
        }
    }

    /// The next thing on the day, whatever it is: a session, a note window,
    /// something from the calendar, a break. Open space isn't a thing, so it
    /// doesn't count. "Up next" means next, not next break.
    var upNext: PlanBlock? {
        plan
            .sorted { $0.start < $1.start }
            .first { $0.start > now && $0.kind != .open }
    }

    /// What's happening right now, if anything is.
    var currentThing: PlanBlock? {
        plan.first { $0.start <= now && now < $0.end && $0.kind != .open }
    }

    /// The definition behind a block, when there is one. A one-off has none.
    func kind(of block: PlanBlock) -> IntermissionKind? {
        guard case .intermission(let id) = block.kind else { return nil }
        return settings.intermissions.first { $0.id == id }
    }

    func intermissionID(of block: PlanBlock) -> String? {
        if case .intermission(let id) = block.kind { return id }
        return nil
    }

    /// The block the clock is inside, for the Now card's progress bar.
    var currentBlock: PlanBlock? {
        plan.first { $0.start <= now && now < $0.end }
    }

    /// Breaks that could stand in for another one. A weekly goal never
    /// stands in for anything: it happens because Carl put it somewhere.
    var swapCandidates: [IntermissionKind] { settings.intermissions.filter { !$0.isGoal && $0.enabled } }

    // MARK: - Weekly goals

    var goals: [IntermissionKind] { settings.intermissions.filter { $0.isGoal && $0.enabled } }
    var breaks: [IntermissionKind] { settings.intermissions.filter { !$0.isGoal } }

    /// Done, planned and the week's target for a goal.
    ///
    /// "Done" is the log's answer unless Carl has overridden it: he was away
    /// from the computer for most of the time the goal was planned for.
    func goalProgress(_ id: String) -> (done: Int, planned: Int, target: Int) {
        let target = settings.intermissions.first { $0.id == id }?.perWeek ?? 0
        var done = 0
        var planned = 0
        for slot in weekPlan.slots where slot.goalID == id {
            if goalIsDone(slot) { done += 1 } else { planned += 1 }
        }
        return (done, planned, target)
    }

    func goalIsDone(_ slot: GoalSlot) -> Bool {
        goalWasDone(slot: slot, planned: plannedInterval(for: slot), computer: computer, now: now)
    }

    /// When a goal actually sits on its day, which is what "done" is judged
    /// against. Nil when the day couldn't fit it after all.
    private func plannedInterval(for slot: GoalSlot) -> DateInterval? {
        guard let block = blocks(for: slot.day).first(where: { $0.intermissionID == slot.goalID })
        else { return nil }
        return DateInterval(start: block.start, end: block.end)
    }

    /// How many of each goal are still without a slot this week.
    var goalsRemaining: [String: Int] {
        goals.reduce(into: [:]) { remaining, goal in
            let progress = goalProgress(goal.id)
            remaining[goal.id] = max(0, progress.target - progress.done - progress.planned)
        }
    }

    var goalSlotsLeft: Int { goalsRemaining.values.reduce(0, +) }

    func goalSlot(_ id: String, on day: Date) -> GoalSlot? { weekPlan.slot(for: id, on: day) }

    /// The first open stretch on a day that a goal would fit into, buffers
    /// and working hours included. Nil when the day has no room for it.
    func goalFit(_ goal: IntermissionKind, on day: Date) -> Date? {
        guard isWorkingDay(day) else { return nil }
        let blocks = blocks(for: day)
        return planner()
            .openStretches(
                in: blocks,
                window: planWindow(for: day),
                workingWindows: schedule.workingWindows(on: day)
            )
            .compactMap { start(for: goal, in: $0) }
            .first
    }

    /// Where a goal would go in an empty stretch, if it would.
    func start(for goal: IntermissionKind, in stretch: DateInterval) -> Date? {
        placeableStart(length: goal.length, in: stretch, now: now)
    }

    func placeGoal(_ id: String, on day: Date, at start: Date? = nil) {
        var week = weeks[day]
        week.place(id, on: day, at: start)
        if let start, start < now {
            week.mark(id, on: day, done: true)
        } else if Calendar.current.startOfDay(for: day) < Calendar.current.startOfDay(for: now) {
            week.mark(id, on: day, done: true)
        }
        weeks[day] = week
        weeks.save()
        selectedGoalID = nil
        rebuildPlan()
    }

    func removeGoal(_ id: String, on day: Date) {
        var week = weeks[day]
        week.remove(id, on: day)
        weeks[day] = week
        weeks.save()
        rebuildPlan()
    }

    /// Says outright whether a goal happened, rather than toggling.
    func markGoal(_ id: String, on day: Date, done: Bool?) {
        var week = weeks[day]
        week.mark(id, on: day, done: done)
        weeks[day] = week
        weeks.save()
        rebuildPlan()
    }

    /// Skips a break on a day that isn't the one being shown.
    func recordSkip(_ id: String, on day: Date) {
        var saved = plans[day]
        saved.apply(PlanEdit(intermissionID: id, change: .skipped))
        plans[day] = saved
        plans.save()
        rebuildPlan()
    }

    /// The tick in the tray: says it happened, or says it didn't, whatever
    /// the log thinks.
    func toggleGoalDone(_ id: String, on day: Date) {
        guard let slot = goalSlot(id, on: day) else { return }
        var week = weeks[day]
        week.mark(id, on: day, done: !goalIsDone(slot))
        weeks[day] = week
        weeks.save()
        rebuildPlan()
    }

    /// What an intermission is doing today, for its card in Settings.
    ///
    /// The card used to show the rule and nothing else, so there was no way
    /// to tell a break that was placed this morning from one that hasn't
    /// fitted in a fortnight.
    func todayStatus(for kind: IntermissionKind) -> String {
        guard kind.enabled else { return "Off" }
        let today = plan.filter { $0.intermissionID == kind.id }.sorted { $0.start < $1.start }

        if kind.isGoal {
            let progress = goalProgress(kind.id)
            var text = "\(progress.done) done, \(progress.planned) planned of \(progress.target)"
            if let block = today.first {
                text += " · today at \(clock(block.start))"
            } else if goalFit(kind, on: Date()) == nil {
                text += " · no gap fits today"
            }
            return text
        }

        guard kind.runs(on: Date()) else {
            return nextDay(for: kind).map { "Not today · next \($0.shortName)" } ?? "Not today"
        }
        guard let first = today.first else {
            return isDayOff ? "Not today · a day off" : "Didn't fit today"
        }
        let times = "Today \(clock(first.start))–\(clock(first.end))"
        if kind.placementsPerDay > 1 {
            guard today.count > 1 else { return times + " · no room for a second" }
            return times + " and \(clock(today[1].start))–\(clock(today[1].end))"
        }
        return times
    }

    /// The next day this break runs, for "Not today · next Thu".
    private func nextDay(for kind: IntermissionKind) -> Weekday? {
        let calendar = Calendar.current
        for ahead in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: ahead, to: Date()) else { continue }
            if kind.runs(on: day) { return Weekday(rawValue: calendar.component(.weekday, from: day)) }
        }
        return nil
    }

    /// Adds a break or a goal and opens its editor.
    func addIntermission(role: IntermissionKind.Role) {
        let kind = IntermissionKind.blank(role: role, id: "custom-\(UUID().uuidString.prefix(8))")
        settings.intermissions.append(kind)
        editingIntermissionID = kind.id
    }

    /// Puts a built-in back the way it came. Carl's own have no default, so
    /// their card offers Delete instead.
    func resetIntermission(_ id: String) {
        guard let index = settings.intermissions.firstIndex(where: { $0.id == id }),
              let original = settings.intermissions[index].builtIn else { return }
        settings.intermissions[index] = original
    }

    // MARK: - The week

    /// The days the Week grid shows: Monday to Friday, always, plus a
    /// weekend day if something is on it.
    ///
    /// It used to show only his desk days, which meant Thursday - the day he
    /// most often ends up at the desk anyway - simply wasn't in the week.
    var weekDays: [Date] {
        let calendar = Calendar.current
        let start = WeekPlan.weekStart(of: now)
        return (0..<7).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            guard offset > 4 else { return day }
            let weekend = !schedule.sessions(on: day).isEmpty
                || !weeks[day].slots(on: day).isEmpty
                || settings.isDeskDay(day)
            return weekend ? day : nil
        }
    }

    /// A day things can be put on. Time off and holidays are out; a day he
    /// doesn't usually work isn't - that's where "I did read on Thursday"
    /// goes.
    func isWorkingDay(_ day: Date) -> Bool { !schedule.isDayOff(day) }

    /// Drawn hatched: time off and holidays, which Practice Studio publishes.
    func isRestDay(_ day: Date) -> Bool { schedule.isDayOff(day) }

    /// A day the planner will place breaks into by itself.
    func isDeskDay(_ day: Date) -> Bool { settings.isDeskDay(day) && !schedule.isDayOff(day) }

    /// The hours the grid's rows cover: the widest working day of the week,
    /// so every column lines up on the same clock.
    /// The hours the grid's rows cover, as a clock range on one day.
    ///
    /// It has to be a clock range, not a span of dates: taking the earliest
    /// start and the latest end across the week gave Monday morning to
    /// Friday evening, and the grid drew a column four days tall.
    var weekHours: DateInterval {
        let calendar = Calendar.current
        let windows = weekDays.map { planWindow(for: $0) }
        func minutes(_ date: Date) -> Int {
            calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
        let first = windows.map { minutes($0.start) }.min() ?? 9 * 60
        let last = windows.map { minutes($0.end) }.max() ?? 18 * 60
        let base = calendar.startOfDay(for: now)
        return DateInterval(
            start: base.addingTimeInterval(TimeInterval(first * 60)),
            end: base.addingTimeInterval(TimeInterval(max(last, first + 120) * 60))
        )
    }

    /// What a day's standing came to, or nil when nothing was recorded.
    func standingShare(on day: Date) -> Double? {
        let record = days[day]
        guard record.isRecorded else { return nil }
        return record.standingShare
    }

    /// The week's standing, averaged across the days that have a number.
    /// A day with nothing recorded isn't a nought, it's a day with no answer.
    var weekStandingShare: Double? {
        let shares = weekDays.filter { !isRestDay($0) }.compactMap { standingShare(on: $0) }
        guard !shares.isEmpty else { return nil }
        return shares.reduce(0, +) / Double(shares.count)
    }

    var weeklyStandingGoal: Double { settings.weeklyStandingGoal ?? settings.standingGoal }

    // MARK: - Rebalancing

    struct RebalanceStrip: Equatable {
        var text: String
        var actions: [Rebalance.Action]
        var trigger: Rebalance.Trigger
        /// The edit that opened the time, so Undo can put the day back.
        var triggeringEdit: PlanEdit?
    }

    /// An edit to something fixed: a session that didn't happen, one that
    /// finished early, a calendar event he'll be at the computer for.
    func apply(_ change: PlanEdit.Change, to target: PlanEdit.Target) {
        let edit = PlanEdit(target: target, change: change)
        var day = plans[shownDate]
        day.apply(edit)
        plans[shownDate] = day
        plans.save()
        rebuildPlan()

        guard planDay == .today else { return }
        switch change {
        case .didNotHappen:
            if case .session(let start) = target {
                offerRebalance(
                    .sessionDidNotHappen(start: start),
                    reason: "Your \(clock(start)) session didn't happen.",
                    edit: edit,
                    opened: schedule.sessions(on: currentDay)
                        .first { $0.start == start }
                        .map { DateInterval(start: $0.start, end: $0.end) }
                )
            } else if case .event(let start, let title) = target {
                offerRebalance(
                    .calendarChanged, reason: "\(title) is off.", edit: edit,
                    opened: events.first { $0.start == start && $0.title == title }
                        .map { DateInterval(start: $0.start, end: $0.end) }
                )
            }
        case .endedEarly(let minutes):
            if case .session(let start) = target {
                let freed = schedule.sessions(on: currentDay).first { $0.start == start }.map {
                    DateInterval(start: $0.end.addingTimeInterval(TimeInterval(-minutes * 60)), end: $0.end)
                }
                offerRebalance(
                    .sessionEndedEarly(start: start, minutes: minutes),
                    reason: "Your \(clock(start)) ended \(minutes) min early.",
                    edit: edit,
                    opened: freed
                )
            }
        default:
            break
        }
    }

    /// "I did have lunch on Monday": puts a break on a day at a time, after
    /// the fact. It goes in as an edit, so the planner leaves it alone and a
    /// past day can hold something nobody planned.
    func recordBreak(_ id: String, on day: Date, at start: Date, minutes: Int? = nil) {
        var saved = plans[day]
        saved.apply(PlanEdit(intermissionID: id, change: .moved(to: start)))
        if let minutes { saved.apply(PlanEdit(intermissionID: id, change: .resized(minutes: minutes))) }
        plans[day] = saved
        plans.save()
        rebuildPlan()
    }

    /// Sets when something is and how long it runs, on a given day.
    ///
    /// One call for every route: the popover, a drag between days, a resize.
    /// A goal keeps its slot - and keeps being done, if it was - because
    /// moving something that happened doesn't unhappen it.
    func setTimes(_ block: PlanBlock, on day: Date, start: Date, minutes: Int) {
        guard let id = block.intermissionID else { return }
        let length = max(5, minutes)
        var saved = plans[day]
        if isOneOff(id) {
            saved.apply(PlanEdit(
                intermissionID: id,
                change: .added(name: block.title, minutes: length, at: start)
            ))
        } else {
            saved.apply(PlanEdit(intermissionID: id, change: .moved(to: start)))
            saved.apply(PlanEdit(intermissionID: id, change: .resized(minutes: length)))
        }
        plans[day] = saved
        plans.save()

        if block.isGoal {
            let wasDone = goalSlot(id, on: day).map { goalIsDone($0) }
            var week = weeks[day]
            week.place(id, on: day, at: start)
            if wasDone == true { week.mark(id, on: day, done: true) }
            weeks[day] = week
            weeks.save()
        }
        rebuildPlan()
    }

    /// Moves a block from one day to another, keeping its length.
    func move(_ block: PlanBlock, from oldDay: Date, to day: Date, at start: Date) {
        guard let id = block.intermissionID else { return }
        let wasDone = block.isGoal ? goalSlot(id, on: oldDay).map { goalIsDone($0) } : nil
        if !Calendar.current.isDate(oldDay, inSameDayAs: day) {
            clearEdits(for: .intermission(id), on: oldDay)
            if block.isGoal { removeGoal(id, on: oldDay) }
        }
        setTimes(block, on: day, start: start, minutes: Int(block.length / 60))
        if wasDone == true {
            var week = weeks[day]
            week.mark(id, on: day, done: true)
            weeks[day] = week
            weeks.save()
            rebuildPlan()
        }
    }

    /// Takes something off a particular day, wherever that day is.
    func clearEdits(for target: PlanEdit.Target, on day: Date) {
        var saved = plans[day]
        saved.clearEdits(for: target)
        plans[day] = saved
        plans.save()
        rebuildPlan()
    }

    func clearEdits(for target: PlanEdit.Target) {
        var day = plans[shownDate]
        day.clearEdits(for: target)
        plans[shownDate] = day
        plans.save()
        rebuildPlan()
    }

    func edits(for target: PlanEdit.Target) -> [PlanEdit] { plans[shownDate].edits(for: target) }

    /// Offers the freed time back. One option isn't a choice, so the banner
    /// only appears when there are at least two; otherwise the strip says
    /// what happened and leaves it there.
    private func offerRebalance(
        _ trigger: Rebalance.Trigger, reason: String, edit: PlanEdit?, opened: DateInterval? = nil
    ) {
        guard settings.onCalendarChange == .ask else { return }
        guard !plans[currentDay].settledRebalances.contains(trigger.key) else { return }
        let offer = planner().rebalance(
            trigger: trigger,
            reason: reason,
            blocks: plan,
            goalsRemaining: goalsRemaining,
            placedGoalsToday: Set(weekPlan.slots(on: currentDay).map(\.goalID)),
            on: currentDay,
            window: planWindow(for: currentDay),
            workingWindows: schedule.workingWindows(on: currentDay),
            opened: opened
        )
        guard let offer else {
            rebalanceStrip = RebalanceStrip(
                text: reason + " The time stays open.",
                actions: [], trigger: trigger, triggeringEdit: edit
            )
            settle(trigger)
            return
        }
        rebalance = offer
        rebalanceChoice = offer.selected
        rebalanceStrip = nil
    }

    func applyRebalance() {
        guard let offer = rebalance,
              let option = offer.options.first(where: { $0.id == rebalanceChoice }) ?? offer.options.first
        else { return }
        for action in option.actions { perform(action) }
        rebalanceStrip = RebalanceStrip(
            text: option.confirmation,
            actions: option.actions,
            trigger: offer.trigger,
            triggeringEdit: triggeringEdit(for: offer.trigger)
        )
        settle(offer.trigger)
        rebalance = nil
        rebuildPlan()
    }

    /// "Not now": the gap stays open and the banner goes away.
    func dismissRebalance() {
        guard let offer = rebalance else { return }
        rebalanceStrip = RebalanceStrip(
            text: "Left it open. The time stays yours.",
            actions: [],
            trigger: offer.trigger,
            triggeringEdit: triggeringEdit(for: offer.trigger)
        )
        settle(offer.trigger)
        rebalance = nil
    }

    /// Undo takes back what was applied AND what opened the time, so the day
    /// goes back to what it was rather than to a half-changed version of it.
    func undoRebalance() {
        guard let strip = rebalanceStrip else { return }
        for action in strip.actions { reverse(action) }
        if let edit = strip.triggeringEdit {
            var day = plans[currentDay]
            day.remove([edit])
            plans[currentDay] = day
            plans.save()
        }
        var day = plans[currentDay]
        day.settledRebalances.remove(strip.trigger.key)
        plans[currentDay] = day
        plans.save()
        rebalanceStrip = nil
        rebuildPlan()
    }

    func hideRebalanceStrip() { rebalanceStrip = nil }

    private func perform(_ action: Rebalance.Action) {
        switch action {
        case .edit(let edit):
            var day = plans[currentDay]
            day.apply(edit)
            plans[currentDay] = day
            plans.save()
        case .placeGoal(let id, let at):
            placeGoal(id, on: currentDay, at: at)
        }
    }

    private func reverse(_ action: Rebalance.Action) {
        switch action {
        case .edit(let edit):
            var day = plans[currentDay]
            day.remove([edit])
            plans[currentDay] = day
            plans.save()
        case .placeGoal(let id, _):
            removeGoal(id, on: currentDay)
        }
    }

    private func settle(_ trigger: Rebalance.Trigger) {
        var day = plans[currentDay]
        day.settledRebalances.insert(trigger.key)
        plans[currentDay] = day
        plans.save()
    }

    private func triggeringEdit(for trigger: Rebalance.Trigger) -> PlanEdit? {
        switch trigger {
        case .sessionDidNotHappen(let start):
            plans[currentDay].edits(for: .session(start: start)).first { $0.change == .didNotHappen }
        case .sessionEndedEarly(let start, let minutes):
            plans[currentDay].edits(for: .session(start: start))
                .first { $0.change == .endedEarly(minutes: minutes) }
        case .calendarChanged, .skipped:
            nil
        }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - The evening offer to plan tomorrow

    /// A planned intermission's time has come round. Said once, and never
    /// during a session or while paused.
    private func announceIntermissionIfDue(_ now: Date) {
        guard !settings.paused(at: now), !schedule.isDayOff(now),
              schedule.session(covering: now) == nil
        else { return }
        for block in plan {
            guard case .intermission(let id) = block.kind,
                  block.start <= now, now < block.end,
                  !announcedIntermissions.contains(id),
                  !startedIntermissions.contains(id)
            else { continue }
            announcedIntermissions.insert(id)
            say(.intermissionDue(
                name: block.title,
                minutes: Int(block.length / 60),
                shortened: block.isShortened
            ))
        }
    }

    /// The day in a sentence, once the last session is behind him.
    private func summariseDayIfDone(_ now: Date) {
        guard settings.endOfDaySummary, !settings.paused(at: now), !schedule.isDayOff(now) else { return }
        guard let lastEnd = schedule.sessions(on: now).map(\.end).max(),
              now >= lastEnd.addingTimeInterval(1800),          // half an hour after
              today.atDesk > 0
        else { return }
        var record = days[now]
        guard record.summarisedAt == nil else { return }
        record.summarisedAt = now
        days[now] = record
        days.save()

        say(.endOfDay(
            percent: Int((today.standingShare * 100).rounded()),
            notesStanding: today.notesStanding,
            notesTotal: today.notesTotal
        ))
    }

    private func offerTomorrowIfDayIsDone(_ now: Date) {
        guard settings.eveningPlan, !settings.paused(at: now), !schedule.isDayOff(now) else { return }
        let todays = schedule.sessions(on: now)
        guard let lastEnd = todays.map(\.end).max() else { return }
        // Ten minutes after the last session, so the note comes first.
        guard now >= lastEnd.addingTimeInterval(600) else { return }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        var record = plans[tomorrow]
        guard record.promptedAt == nil, record.committedAt == nil else { return }
        record.promptedAt = now
        plans[tomorrow] = record
        plans.save()

        let sessions = schedule.sessions(on: tomorrow)
        say(.planTomorrow(
            sessions: sessions.count,
            virtual: sessions.filter { $0.mode.isSeated }.count
        ), category: Notifier.planCategory)
    }

    /// Time off and holidays come from Practice Studio; desk days are Carl's
    /// own setting. Either one makes today a day the app stays quiet.
    var isDayOff: Bool { schedule.isDayOff(Date()) || !settings.isDeskDay(Date()) }

    func startIntermission(_ id: String) {
        startedIntermissions.insert(id)
        computer.startBreak(label: settings.intermissions.first { $0.id == id }?.name ?? id, at: Date())
    }

    func finishIntermission(_ id: String) {
        startedIntermissions.remove(id)
        computer.setOnComputer(true, at: Date())
    }

    func skipIntermission(_ id: String) {
        skippedIntermissions.insert(id)
        rebuildPlan()
    }

    /// "Done" on the note card: stop the reminder without waiting for the
    /// window to run out. Standing already counted when the desk went up.
    func noteDone() {
        coach.cancel()
    }

    /// "Skip ahead" on the Now card: this session is over, whatever
    /// sessions.json still says. A manual override, not the normal path -
    /// the phase moves on by itself when the published hour ends.
    func endSessionEarly() {
        planDay = .today
        guard let block = plan.first(where: {
            if case .session = $0.kind { return $0.start <= now && now < $0.end }
            return false
        }), let target = block.target else { return }
        let minutes = max(1, Int((block.end.timeIntervalSince(now) / 60).rounded()))
        apply(.endedEarly(minutes: minutes), to: target)
    }

    /// When the office closes on a given day, for deciding that time away
    /// was the end of it. Nil when availability isn't set up at all - then
    /// only a night between the leaving and the coming back counts. A day
    /// with no hours, or a day off, closes before it opens: nothing that
    /// happens on it is an intermission.
    private static func closeOfBusiness(on day: Date, in schedule: SessionSchedule) -> Date? {
        guard !schedule.hours.isEmpty else { return nil }
        if schedule.isDayOff(day) { return Calendar.current.startOfDay(for: day) }
        return schedule.workingHours(on: day)?.end ?? Calendar.current.startOfDay(for: day)
    }

    func labelBreak(_ segment: ComputerSegment, as label: String) {
        computer.label(segmentStartingAt: segment.start, as: label)
        breakToLabel = nil
        logs.save(heights: heights, computer: computer)
    }

    /// "Neither". Recorded, so the prompt doesn't ask about it again.
    func dismissBreakPrompt() {
        if let breakToLabel { computer.decline(segmentStartingAt: breakToLabel.start) }
        breakToLabel = nil
        logs.save(heights: heights, computer: computer)
    }

    /// Off-the-computer time today, by what it was.
    var breaksToday: [String: TimeInterval] {
        computer.labelledBreaks(on: currentDay, now: Date())
    }

    var offComputerToday: TimeInterval { breaksToday.values.reduce(0, +) }

    var inSessionToday: TimeInterval {
        schedule.sessions(on: currentDay).reduce(0) { total, session in
            total + min(session.end, Date()).timeIntervalSince(session.start).clampedToZero
        }
    }

    /// How many times the desk changed state today: the day's restlessness.
    var switchesToday: Int { max(0, heights.segments(on: currentDay).count - 1) }

    var weekNotes: (standing: Int, total: Int) {
        week.reduce(into: (0, 0)) { total, day in
            total.0 += day.notesStanding
            total.1 += day.notesTotal
        }
    }

    /// Everything booked today, whether it has happened yet or not.
    var inSessionPlannedToday: TimeInterval {
        schedule.sessions(on: currentDay).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    var intermissionsDone: Int { startedIntermissions.count }
    var intermissionsPlanned: Int {
        plan.filter { if case .intermission = $0.kind { return true } else { return false } }.count
    }

    // MARK: - Actions the views call

    func pause(until: Date) {
        settings.pausedUntil = until
        coach.cancel()
    }

    func resume() { settings.pausedUntil = nil }

    func useCurrentHeightAsStanding() {
        guard let height, height >= 35 else { return }
        settings.standingThreshold = (height - 1).rounded(.toNearestOrEven)
    }

    private(set) var opensAtLogin = LoginItem.isEnabled

    func setOpensAtLogin(_ enabled: Bool) {
        opensAtLogin = LoginItem.set(enabled)
    }

    /// Last 7 days, oldest first, for the week chart.
    var week: [DayRecord] { days.recent(7, endingOn: Date()) }
    var streak: Int { days.streak(endingOn: Date(), goal: settings.standingGoal) }

    private func settingsChanged(_ old: DeskCore.Settings) {
        guard settings != old else { return }
        coach.settings = settings
        timeline.standingThreshold = settings.standingThreshold
        presence.idleThreshold = TimeInterval(settings.idleMinutes * 60)
        settingsStore.save(settings)
        if settings.listenToDesk != old.listenToDesk || settings.closePortInSession != old.closePortInSession {
            lastPortChange = .distantPast          // a switch he flicked shouldn't wait
        }
        if settings.logSerialTraffic != old.logSerialTraffic {
            // The hook is handed to the monitor when it's made, so the port
            // has to come round again for it to take.
            stopListening()
            lastPortChange = .distantPast
            if settings.logSerialTraffic {
                serialLog.note("logging on — every byte from here, with the time it arrived")
            } else {
                serialLog.note("logging off")
                serialLog.close()
            }
        }
        if settings.intermissions != old.intermissions || settings.calendarIDs != old.calendarIDs
            || settings.calendarColor != old.calendarColor
            || settings.bufferMinutes != old.bufferMinutes
            || settings.calendarEventMode != old.calendarEventMode
            || settings.settleMinutes != old.settleMinutes
            || settings.deskDays != old.deskDays
            || settings.dayStartsMinutes != old.dayStartsMinutes {
            rebuildPlan()
        }
    }
}

/// The last height seen, so the menu bar has something to show after a
/// restart. Display and accounting only - the coach acts on live reports.
enum LastHeight {
    static func load(directory: URL) -> Double? {
        guard let data = try? Data(contentsOf: directory.appending(path: "last_height.json")),
              let value = try? JSONDecoder().decode([String: Double].self, from: data)["height"]
        else { return nil }
        return value
    }

    static func save(_ height: Double, directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(["height": height])
            .write(to: directory.appending(path: "last_height.json"), options: .atomic)
    }
}
