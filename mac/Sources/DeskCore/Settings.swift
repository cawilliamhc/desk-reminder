import Foundation

public enum Tone: String, Codable, CaseIterable, Sendable {
    case dry, warm, playful
}

/// When time opens up: offer what to do with it, or just leave the gap.
public enum CalendarChange: String, Codable, CaseIterable, Sendable {
    case ask, leaveOpen
}

/// A personal calendar event blocks the gap either way. This is about whether
/// he's at the computer during it, which is what standing time is counted from.
public enum CalendarEventMode: String, Codable, CaseIterable, Sendable {
    /// A video call is at the computer; everything else is away from it.
    case guessFromTitle
    case onComputer
    case offComputer
}

public enum Weekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// "Mon". Sentences and day chips both read Monday-first, which is how
    /// Carl's week runs and how Practice Studio publishes availability.
    public var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    public var initial: String {
        self == .thursday ? "T" : String(shortName.prefix(1))
    }

    /// 0 = Monday … 6 = Sunday.
    public var weekIndex: Int { (rawValue + 5) % 7 }

    public static var weekOrder: [Weekday] {
        allCases.sorted { $0.weekIndex < $1.weekIndex }
    }
}

/// Everything the Settings view writes. Stage 1 covers Desk, Notes and Coach;
/// intermissions and calendars join in later stages.
public struct Settings: Codable, Equatable, Sendable {
    /// Whether to hold the serial port open at all. Off, the app still plans
    /// and nudges; it just doesn't know the desk's height.
    public var listenToDesk: Bool = true
    public var standingThreshold: Double = 40
    /// Share of at-desk time (sessions excluded) to aim for.
    public var standingGoal: Double = 0.20
    public var remindForNotes: Bool = true
    public var sound: Bool = true
    public var tone: Tone = .playful
    public var deskDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .friday]
    public var pausedUntil: Date?
    /// Idle for longer than this counts as off the computer; a lock counts at once.
    public var idleMinutes: Int = 6
    /// Ask what an unlabelled break was, when it was long enough to matter.
    public var askWhatABreakWas: Bool = true
    public var intermissions: [IntermissionKind] = IntermissionKind.defaults
    /// EventKit calendar identifiers Carl has chosen to read.
    public var calendarIDs: Set<String> = []
    /// Minutes to be back before a session starts - coming straight from
    /// lunch into someone's hour isn't arriving.
    public var settleMinutes: Int = 10
    public var morningPlan: Bool = true
    /// Offer to plan tomorrow when the last session is done.
    public var eveningPlan: Bool = true
    /// How the day went, once the last session is behind him.
    public var endOfDaySummary: Bool = true
    /// Minutes of daylight between two intermissions. Notes and sessions
    /// don't need it; another break does - lunch used to end at 3:05 and
    /// reading start at 3:05, which is not two things.
    public var bufferMinutes: Int = 10
    /// What happens when the day changes under a plan.
    public var onCalendarChange: CalendarChange = .ask
    /// Average across desk days. Nil means the same as the daily goal.
    public var weeklyStandingGoal: Double?
    /// What a personal calendar event means for where he is.
    public var calendarEventMode: CalendarEventMode = .guessFromTitle
    /// Skipping something this long or longer offers the freed time back.
    /// Skipping a ten-minute stretch shouldn't start a conversation.
    public var rebalanceAfterSkipMinutes: Int = 30
    /// When the day starts on screen, in minutes from midnight. Practice
    /// Studio's hours say when he sees clients; this says when he's about -
    /// the desk is up at half seven whatever the first session says.
    public var dayStartsMinutes: Int = 7 * 60 + 30
    /// Keep the sound to himself while a session is running. The reminder
    /// still arrives; it just doesn't make a noise into somebody's hour.
    public var silentInSession: Bool = true
    /// Close the serial port while a session is running. The handset clicks
    /// and lights up now and then, and the hour with a client is the worst
    /// possible time for it.
    public var closePortInSession: Bool = true

    /// The shape of this file. A file written before v4 has no version at
    /// all, which is how the migration below knows to run.
    public static let currentVersion = 5
    public var version: Int = Settings.currentVersion

    public init() {}

    /// Every key is optional on the way in.
    ///
    /// Swift's synthesised decoder treats a property with a default as
    /// *required* anyway, so adding one field to this struct would have made
    /// last week's settings.json unreadable - and an unreadable file means
    /// the app silently starts from defaults, which is to say it loses his
    /// desk days, his colours and everything he'd added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let blank = Settings()
        listenToDesk = c.value(.listenToDesk, or: blank.listenToDesk)
        standingThreshold = c.value(.standingThreshold, or: blank.standingThreshold)
        standingGoal = c.value(.standingGoal, or: blank.standingGoal)
        remindForNotes = c.value(.remindForNotes, or: blank.remindForNotes)
        sound = c.value(.sound, or: blank.sound)
        tone = c.value(.tone, or: blank.tone)
        deskDays = c.value(.deskDays, or: blank.deskDays)
        pausedUntil = try? c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        idleMinutes = c.value(.idleMinutes, or: blank.idleMinutes)
        askWhatABreakWas = c.value(.askWhatABreakWas, or: blank.askWhatABreakWas)
        intermissions = c.value(.intermissions, or: blank.intermissions)
        calendarIDs = c.value(.calendarIDs, or: blank.calendarIDs)
        settleMinutes = c.value(.settleMinutes, or: blank.settleMinutes)
        morningPlan = c.value(.morningPlan, or: blank.morningPlan)
        eveningPlan = c.value(.eveningPlan, or: blank.eveningPlan)
        endOfDaySummary = c.value(.endOfDaySummary, or: blank.endOfDaySummary)
        bufferMinutes = c.value(.bufferMinutes, or: blank.bufferMinutes)
        onCalendarChange = c.value(.onCalendarChange, or: blank.onCalendarChange)
        weeklyStandingGoal = try? c.decodeIfPresent(Double.self, forKey: .weeklyStandingGoal)
        calendarEventMode = c.value(.calendarEventMode, or: blank.calendarEventMode)
        rebalanceAfterSkipMinutes = c.value(.rebalanceAfterSkipMinutes, or: blank.rebalanceAfterSkipMinutes)
        dayStartsMinutes = c.value(.dayStartsMinutes, or: blank.dayStartsMinutes)
        silentInSession = c.value(.silentInSession, or: blank.silentInSession)
        closePortInSession = c.value(.closePortInSession, or: blank.closePortInSession)
        version = c.value(.version, or: 0)
    }

    /// Brings a file written before v4 up to date.
    ///
    /// The built-ins are taken as they now are - lunch is amber, reading is a
    /// weekly goal, the call happens on the days he picked - keeping only
    /// whether each was switched on. Anything Carl added himself is left
    /// exactly as it was, with one exception: a break he'd made that v4 now
    /// ships as a goal. He had his own Writing, and two of them on the same
    /// screen is one too many, so the built-in takes over and keeps his
    /// colour.
    public mutating func migrate() {
        guard version < Self.currentVersion else { return }
        var mine = intermissions
        var updated: [IntermissionKind] = []

        for original in IntermissionKind.defaults {
            var kind = original
            if let index = mine.firstIndex(where: { $0.id == original.id }) {
                kind.enabled = mine[index].enabled
                mine.remove(at: index)
            }
            // His own version of the same thing, by name.
            if let index = mine.firstIndex(where: {
                $0.name.caseInsensitiveCompare(original.name) == .orderedSame
            }) {
                kind.colorToken = mine[index].colorToken
                mine.remove(at: index)
            }
            updated.append(kind)
        }

        intermissions = updated + mine
        version = Self.currentVersion
    }

    public func paused(at now: Date) -> Bool {
        guard let until = pausedUntil else { return false }
        return now < until
    }

    /// Whether a reminder should make a noise.
    ///
    /// A notification during a session is still worth having - he sees it
    /// when he looks - but a sound goes into the room, and into whatever the
    /// client is in the middle of saying. A live microphone counts as being
    /// in session whatever the schedule says: the eleven o'clock that's
    /// still going at ten past twelve is the exact case this is for.
    public func soundAllowed(inSession: Bool, micInUse: Bool) -> Bool {
        guard sound else { return false }
        guard silentInSession else { return true }
        return !inSession && !micInUse
    }

    /// Whether the app should be holding the serial port open.
    ///
    /// Almost nothing is lost by closing it during a session: the desk is
    /// down for one by definition, and session time is left out of the
    /// day's totals either way. The box only speaks while the desk moves, so
    /// a closed port during an hour the desk doesn't move costs no reading
    /// at all.
    public func listening(inSession: Bool, micInUse: Bool) -> Bool {
        guard listenToDesk else { return false }
        guard closePortInSession else { return true }
        return !inSession && !micInUse
    }

    public func isDeskDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let day = Weekday(rawValue: calendar.component(.weekday, from: date)) else { return false }
        return deskDays.contains(day)
    }
}

extension KeyedDecodingContainer {
    /// The stored value, or the fallback when the key is missing or the
    /// shape has changed since it was written. Settings and intermissions
    /// both read this way, so a new field never costs Carl an old file.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback
    }
}

/// Reads and writes settings.json. A missing or unreadable file means defaults:
/// the app must start even if the file is damaged.
public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              var settings = try? JSONDecoder.deskDecoder.decode(Settings.self, from: data)
        else { return Settings() }
        if settings.version < Settings.currentVersion {
            settings.migrate()
            save(settings)
        }
        return settings
    }

    public func save(_ settings: Settings) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? JSONEncoder.deskEncoder.encode(settings).write(to: url, options: .atomic)
    }
}

extension JSONDecoder {
    public static var deskDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    public static var deskEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
