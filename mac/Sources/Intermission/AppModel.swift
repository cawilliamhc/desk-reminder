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
    enum View: String, CaseIterable { case plan, today, settings }
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
    private(set) var computer = ComputerLog()
    private(set) var heights = HeightLog()
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
    /// Today's intermissions that wouldn't fit anywhere.
    private(set) var unplacedToday: [IntermissionKind] = []
    let calendars = Calendars()
    var settings: DeskCore.Settings { didSet { settingsChanged(oldValue) } }

    private var coach: Coach
    private var days: DayStore
    private var plans: PlanStore
    private var schedule: SessionSchedule
    private let settingsStore: SettingsStore
    private let presence = Presence()
    private let notifier = Notifier()
    private var monitor: SerialMonitor?
    private var lastCheck = Date()
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

        notifier.requestAuthorization()
        if ProcessInfo.processInfo.environment["INTERMISSION_TEST_NOTIFY"] != nil {
            notifier.post("Test notification from Intermission.", sound: true)
        }
        notifier.onAction = { [weak self] action in self?.handle(action) }
        schedule.reload()
        start()
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

    private func start() {
        let monitor = SerialMonitor(
            onHeight: { [weak self] height, at in
                Task { @MainActor in self?.heightReported(height, at: at) }
            },
            onStatus: { [weak self] status in
                Task { @MainActor in self?.adapterStatus = status }
            }
        )
        monitor.start()
        self.monitor = monitor

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    // MARK: - The loop

    private func heightReported(_ height: Double, at now: Date) {
        lastReport = now
        timeline.report(height: height, at: now)
        heights.record(standing: height >= settings.standingThreshold, at: now)
        LastHeight.save(height, directory: Self.supportDirectory)
        if let outcome = coach.heightChanged(height, at: now) { record(outcome) }
    }

    private func tick() {
        let now = Date()
        self.now = now
        rolloverIfNeeded(now)

        let present = presence.isPresent
        if present != isPresent {
            isPresent = present
            timeline.setPresent(present, at: now)
        }
        timeline.tick(now)
        syncTodayFromTimeline()
        computer.setOnComputer(present, at: now)
        if settings.askWhatABreakWas, breakToLabel == nil, present {
            breakToLabel = computer.unlabelledBreaks().first
        }
        if plan.isEmpty { rebuildPlan() }
        phase = Phase.current(
            plan: plan, kinds: settings.intermissions, now: now,
            startedIntermissions: startedIntermissions
        )

        schedule.reload()
        let inSession = schedule.session(covering: now) != nil || schedule.isDayOff(now)
        for _ in schedule.endings(after: lastCheck, until: now) {
            // Every session ends in a standing note, virtual included.
            let (message, outcome) = coach.sessionEnded(at: now, inSession: inSession)
            days.update(now) { $0.notesTotal += 1 }
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
        currentDay = startOfDay
        coach.newDay()
        today = days[now]
        startedIntermissions = []
        skippedIntermissions = []
        announcedIntermissions = []
        planDay = .today
        computer.prune(before: startOfDay.addingTimeInterval(-7 * 86_400))
        heights.prune(before: startOfDay.addingTimeInterval(-7 * 86_400))
        rebuildPlan()
        if settings.morningPlan && settings.isDeskDay(now) { selectedView = .plan }
    }

    private func syncTodayFromTimeline() {
        let totals = timeline.totals(for: currentDay)
        days.update(currentDay) {
            $0.standing = totals.standing
            $0.sitting = totals.sitting
            $0.isDeskDay = settings.isDeskDay(currentDay)
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
            sound: settings.sound,
            category: category
        )
    }

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
        plan = blocks(for: Date())
        events = calendars.events(on: Date(), calendarIDs: settings.calendarIDs)

        let planner = Planner(intermissions: settings.intermissions)
        unplacedToday = schedule.isDayOff(Date()) ? [] : planner.unplaced(in: plan, on: Date())

        let shown = shownDate
        shownPlan = planDay == .today ? plan : blocks(for: shown)
        shownEvents = planDay == .today ? events : calendars.events(on: shown, calendarIDs: settings.calendarIDs)

        let saved = plans[shown]
        scheduleMovedSincePlanning = saved.committedAt != nil
            && !saved.scheduleSignature.isEmpty
            && saved.scheduleSignature != schedule.sessions(on: shown).signature
    }

    /// The plan for a day: its sessions and events, laid out around whatever
    /// Carl has already changed about it.
    private func blocks(for day: Date) -> [PlanBlock] {
        // A day off is a day off: no plan, nothing to nudge about.
        guard !schedule.isDayOff(day) else { return [] }
        let planner = Planner(intermissions: settings.intermissions.filter { !skippedIntermissions.contains($0.id) })
        return planner.plan(
            sessions: schedule.sessions,
            events: calendars.events(on: day, calendarIDs: settings.calendarIDs),
            on: day,
            edits: plans[day].edits,
            configuredHours: schedule.workingHours(on: day),
            workingWindows: schedule.workingWindows(on: day)
        )
    }

    var isPlanCommitted: Bool { plans[shownDate].committedAt != nil }
    /// When today's plan was committed, for the sidebar - "8:04" says it was
    /// planned far better than a count of breaks does.
    var planCommittedAt: Date? { plans[Date()].committedAt }

    /// "Skip planning today": the day runs with no suggestions at all.
    func skipPlanning() {
        for block in shownPlan {
            if case .intermission(let id) = block.kind { apply(.skipped, to: id) }
        }
        if planDay == .today { selectedView = .today }
    }

    func commitShownPlan() {
        var day = plans[shownDate]
        day.committedAt = Date()
        day.scheduleSignature = schedule.sessions(on: shownDate).signature
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
        rebuildPlan()
    }

    /// Nudging a block with the keyboard, for when a drag is the wrong tool.
    func nudge(_ intermissionID: String, byMinutes minutes: Int) {
        guard let block = shownPlan.first(where: { $0.kind == .intermission(id: intermissionID) }) else { return }
        apply(.moved(to: block.start.addingTimeInterval(TimeInterval(minutes * 60))), to: intermissionID)
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

    /// The colour for a block, with the intermission's own choice honoured.
    func color(for kind: PlanBlock.Kind) -> Color {
        switch kind {
        case .session: Theme.session
        case .note: Theme.standing
        case .calendarEvent: Theme.calendar
        case .open: Theme.border
        case .intermission(let id):
            settings.intermissions.first { $0.id == id }
                .map { Theme.color(token: $0.colorToken) } ?? Theme.primary
        }
    }

    /// The next intermission on the plan that hasn't been started or skipped.
    var upNext: (kind: IntermissionKind, at: Date)? {
        for block in plan.sorted(by: { $0.start < $1.start }) {
            guard case .intermission(let id) = block.kind,
                  block.end > now,
                  !startedIntermissions.contains(id),
                  let kind = settings.intermissions.first(where: { $0.id == id })
            else { continue }
            return (kind, block.start)
        }
        return nil
    }

    /// The block the clock is inside, for the Now card's progress bar.
    var currentBlock: PlanBlock? {
        plan.first { $0.start <= now && now < $0.end }
    }

    /// Intermissions that could stand in for another one.
    var swapCandidates: [IntermissionKind] { settings.intermissions }

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
                  !startedIntermissions.contains(id),
                  let kind = settings.intermissions.first(where: { $0.id == id })
            else { continue }
            announcedIntermissions.insert(id)
            say(.intermissionDue(
                name: kind.name,
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

    func labelBreak(_ segment: ComputerSegment, as label: String) {
        computer.label(segmentStartingAt: segment.start, as: label)
        breakToLabel = nil
    }

    func dismissBreakPrompt() { breakToLabel = nil }

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

    func finishedSessionNow() {
        let (message, outcome) = coach.sessionEnded(at: Date())
        days.update(Date()) { $0.notesTotal += 1 }
        if let outcome { record(outcome) } else if let message { say(message) }
    }

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
        if settings.intermissions != old.intermissions || settings.calendarIDs != old.calendarIDs {
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
