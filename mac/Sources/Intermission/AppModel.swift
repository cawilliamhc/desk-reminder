import AppKit
import DeskCore
import Foundation
import Observation

/// Everything the views read, and the one place the pieces meet: the adapter,
/// the day's tally, the coach, the session file and settings.
///
/// The desk is never written to. The adapter's transmit line isn't even
/// connected, and nothing here opens the port for writing - the box reports
/// height by itself while the desk moves. Sending anything makes the handset
/// click and light up, which is exactly what this app must not do.
@MainActor
@Observable
final class AppModel {
    enum View: String, CaseIterable { case today, settings }

    // Where everything lives.
    static let supportDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/com.carlwilliamson.intermission")
    static let sessionsFile = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/com.carlwilliamson.practicestudio/desk-reminder/sessions.json")

    var selectedView: View = .today
    private(set) var adapterStatus: SerialMonitor.Status = .adapterNotFound
    private(set) var lastReport: Date?
    private(set) var timeline: DeskTimeline
    private(set) var today: DayRecord
    private(set) var isPresent = false
    var settings: Settings { didSet { settingsChanged(oldValue) } }

    private var coach: Coach
    private var days: DayStore
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
        presence.idleThreshold = 6 * 60

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
        LastHeight.save(height, directory: Self.supportDirectory)
        if let outcome = coach.heightChanged(height, at: now) { record(outcome) }
    }

    private func tick() {
        let now = Date()
        rolloverIfNeeded(now)

        let present = presence.isPresent
        if present != isPresent {
            isPresent = present
            timeline.setPresent(present, at: now)
        }
        timeline.tick(now)
        syncTodayFromTimeline()

        schedule.reload()
        let inSession = schedule.session(covering: now) != nil
        for session in schedule.endings(after: lastCheck, until: now) {
            // A virtual session is seated; "skip virtual" only silences the
            // nudge, the note window still counts.
            let silent = settings.skipVirtual && session.mode.isSeated
            let (message, outcome) = coach.sessionEnded(at: now, inSession: inSession)
            days.update(now) { $0.notesTotal += 1 }
            if let outcome { record(outcome) } else if let message, !silent { say(message) }
        }
        lastCheck = now

        if let until = snoozedUntil, now >= until {
            snoozedUntil = nil
            if coach.isStanding != true { say(.stillSitting) }
        }

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

    private func say(_ message: CoachMessage) {
        notifier.post(CoachCopy(tone: settings.tone).text(for: message), sound: settings.sound)
    }

    private func handle(_ action: Notifier.Action) {
        switch action {
        case .snooze: snoozedUntil = Date().addingTimeInterval(600)
        case .pauseToday: pause(until: Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)))
        }
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

    private func settingsChanged(_ old: Settings) {
        guard settings != old else { return }
        coach.settings = settings
        timeline.standingThreshold = settings.standingThreshold
        settingsStore.save(settings)
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
