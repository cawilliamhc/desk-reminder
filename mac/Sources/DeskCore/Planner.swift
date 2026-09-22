import Foundation

/// A block on the day's plan.
public struct PlanBlock: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case session(virtual: Bool)
        /// The standing window after a session - after every session, virtual
        /// included. Carl writes his notes on his feet; a seated one was the
        /// comps' idea, not his.
        case note
        case calendarEvent
        case intermission(id: String)
        case open
    }

    /// Kind and time together: two blocks can start at the same instant (an
    /// open stretch and whatever Carl pinned to its start), and a list keyed
    /// on time alone would treat them as one.
    public var id: String { "\(kindKey)@\(Int(start.timeIntervalSince1970))" }

    private var kindKey: String {
        switch kind {
        case .session(let virtual): virtual ? "session-virtual" : "session"
        case .note: "note"
        case .calendarEvent: "calendar"
        case .intermission(let id): "intermission-\(id)"
        case .open: "open"
        }
    }

    public var kind: Kind
    public var start: Date
    public var end: Date
    public var title: String
    public var subline: String?
    public var badge: String?
    /// True when it had to be trimmed to fit the day.
    public var isShortened: Bool = false

    public var length: TimeInterval { end.timeIntervalSince(start) }
    public var isSuggestion: Bool {
        if case .intermission = kind { return true }
        return false
    }
}

/// An event from a personal calendar. Kept as a plain value so the planner
/// doesn't depend on EventKit and can be tested without it.
public struct CalendarEvent: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var title: String

    public init(start: Date, end: Date, title: String) {
        self.start = start
        self.end = end
        self.title = title
    }
}

/// Lays out the day: sessions and calendar events are fixed, a standing note
/// window follows each in-person session, and intermissions fill the gaps
/// that suit them.
///
/// Made once in the morning and left alone. A plan that reshuffles itself
/// every time a session runs long is a plan you stop trusting - so when the
/// day slips, the plan stays put and the app says what got missed.
public struct Planner: Sendable {
    /// The window after a session, for writing the note.
    public static let noteMinutes = 10
    /// Shorter than this and it isn't a window, it's a gap between sessions.
    public static let minimumNoteMinutes = 5
    /// Fallback window, used only when a day has no sessions to read it from.
    public static let dayStartHour = 9
    public static let dayEndHour = 18
    /// How long before the first session, and after the last, the day is
    /// treated as his: arriving, settling, writing the last note.
    public static let edgeMinutes = 30

    public var calendar: Calendar
    public var intermissions: [IntermissionKind]

    public init(calendar: Calendar = .current, intermissions: [IntermissionKind] = IntermissionKind.defaults) {
        self.calendar = calendar
        self.intermissions = intermissions
    }

    /// The hours the plan covers.
    ///
    /// Read from the day itself: Carl is in the office half an hour or so
    /// before his first session, not at eight, and a plan that offers him a
    /// stretch at 8:10 is describing somebody else's morning. A day with no
    /// sessions falls back to the constants above.
    public func workday(
        sessions: [PublishedSession],
        events: [CalendarEvent] = [],
        on day: Date,
        configuredHours: DateInterval? = nil
    ) -> DateInterval {
        let fallbackStart = calendar.date(bySettingHour: Self.dayStartHour, minute: 0, second: 0, of: day)!
        let fallbackEnd = calendar.date(bySettingHour: Self.dayEndHour, minute: 0, second: 0, of: day)!

        let todays = sessions.filter { calendar.isDate($0.start, inSameDayAs: day) }
        let todaysEvents = events.filter { calendar.isDate($0.start, inSameDayAs: day) }
        let starts = todays.map(\.start) + todaysEvents.map(\.start)
        let ends = todays.map(\.end) + todaysEvents.map(\.end)
        guard let first = starts.min(), let last = ends.max() else {
            // Nothing booked: his configured working hours, else the fallback.
            return configuredHours ?? DateInterval(start: fallbackStart, end: fallbackEnd)
        }
        let edge = TimeInterval(Self.edgeMinutes * 60)
        let fromSessions = DateInterval(
            start: first.addingTimeInterval(-edge),
            end: last.addingTimeInterval(edge)
        )
        guard let configured = configuredHours else { return fromSessions }
        // Configured hours say when he's there; the sessions can only widen
        // that, for the evening one that runs past the usual close.
        return DateInterval(
            start: min(configured.start, fromSessions.start),
            end: max(configured.end, fromSessions.end)
        )
    }

    /// Today's intermissions that couldn't be fitted anywhere. The plan is
    /// silent about them otherwise, and a silent absence reads as a bug.
    public func unplaced(in blocks: [PlanBlock], on day: Date) -> [IntermissionKind] {
        intermissions.filter { kind in
            kind.enabled && runsToday(kind, on: day)
                && !blocks.contains { $0.kind == .intermission(id: kind.id) }
        }
    }

    public func plan(
        sessions: [PublishedSession],
        events: [CalendarEvent] = [],
        on day: Date,
        edits: [PlanEdit] = [],
        workday: DateInterval? = nil,
        configuredHours: DateInterval? = nil,
        workingWindows: [DateInterval] = []
    ) -> [PlanBlock] {
        let window = workday ?? self.workday(
            sessions: sessions, events: events, on: day, configuredHours: configuredHours
        )
        let dayStart = window.start
        let dayEnd = window.end

        var blocks: [PlanBlock] = []
        let today = sessions.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
        let todaysEvents = events.filter { calendar.isDate($0.start, inSameDayAs: day) }

        for (index, session) in today.enumerated() {
            blocks.append(PlanBlock(
                kind: .session(virtual: session.mode.isSeated),
                start: session.start, end: session.end,
                title: "Session",
                subline: session.mode.isSeated ? "Virtual · seated" : "In person"
            ))

            // A note after every session, as close to it as the day allows -
            // Carl writes them while the session is still in his head. Back to
            // back, there's no room, and the plan says so by leaving it out.
            let wanted = session.end.addingTimeInterval(TimeInterval(Self.noteMinutes * 60))
            let nextFixed = [
                today.dropFirst(index + 1).first?.start,
                todaysEvents.first { $0.start >= session.end }?.start,
                dayEnd,
            ].compactMap { $0 }.min() ?? dayEnd
            let noteEnd = min(wanted, nextFixed)
            if noteEnd.timeIntervalSince(session.end) >= TimeInterval(Self.minimumNoteMinutes * 60) {
                blocks.append(PlanBlock(
                    kind: .note, start: session.end, end: noteEnd,
                    title: "Note — standing", subline: nil
                ))
            }
        }

        for event in todaysEvents {
            blocks.append(PlanBlock(
                kind: .calendarEvent, start: event.start, end: event.end,
                title: event.title, subline: nil, badge: "Calendar"
            ))
        }

        // Carl's own changes first, so the suggestions lay out around them
        // rather than the other way round.
        let skipped = Set(edits.compactMap { edit -> String? in
            if case .skipped = edit.change { return edit.intermissionID }
            return nil
        })
        let swappedAway = Set(edits.compactMap { edit -> String? in
            if case .swapped = edit.change { return edit.intermissionID }
            return nil
        })

        func free() -> [Gap] {
            within(gaps(around: blocks, from: dayStart, to: dayEnd), workingWindows)
        }

        // One block per intermission, whatever route it took onto the plan.
        var placed = Set<String>()
        func claim(_ id: String) -> Bool { placed.insert(id).inserted }

        // A length Carl set by hand, for today only.
        var resized: [String: Int] = [:]
        for edit in edits {
            if case .resized(let minutes) = edit.change { resized[edit.intermissionID] = minutes }
        }
        func length(_ kind: IntermissionKind) -> TimeInterval {
            resized[kind.id].map { TimeInterval(max(5, $0) * 60) } ?? kind.length
        }

        // An exact time is the most specific thing Carl can say, so moves and
        // one-offs are placed before a swap that might claim the same thing.
        let ordered = edits.sorted { a, b in
            func rank(_ change: PlanEdit.Change) -> Int {
                switch change {
                case .moved, .added: 0
                case .swapped: 1
                case .skipped, .resized: 2      // resize is applied above, not placed
                }
            }
            return rank(a.change) < rank(b.change)
        }

        for edit in ordered where !skipped.contains(edit.intermissionID) {
            switch edit.change {
            case .moved(let start):
                guard let kind = intermissions.first(where: { $0.id == edit.intermissionID }),
                      claim(kind.id) else { continue }
                blocks.append(fixed(kind, at: start, length: length(kind), blocks: blocks, subline: "Moved by you"))
            case .resized:
                continue
            case .added(let name, let minutes, let start):
                guard claim(edit.intermissionID) else { continue }
                blocks.append(PlanBlock(
                    kind: .intermission(id: edit.intermissionID),
                    start: start,
                    end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                    title: name,
                    subline: collides(start, minutes: minutes, with: blocks) ? "Overlaps what's booked" : "Added by you",
                    badge: "Yours"
                ))
            case .swapped(let replacement):
                guard let kind = intermissions.first(where: { $0.id == replacement }),
                      claim(kind.id) else { continue }
                guard let slot = place(kind, in: free(), blocks: blocks, day: day) else { continue }
                let length = resized[kind.id].map { TimeInterval(max(5, $0) * 60) } ?? slot.length ?? kind.length
                blocks.append(PlanBlock(
                    kind: .intermission(id: kind.id),
                    start: slot.start,
                    end: slot.start.addingTimeInterval(length),
                    title: kind.name,
                    subline: "Swapped in by you",
                    badge: "Yours",
                    isShortened: length < kind.length
                ))
            case .skipped:
                continue
            }
        }

        // Only the edits that PLACE something count as handled here. A resize
        // says how long, not where, so the suggestion still has to be laid out.
        let edited = Set(edits.compactMap { edit -> String? in
            switch edit.change {
            case .moved, .added, .swapped: edit.intermissionID
            case .skipped, .resized: nil
            }
        })
        // Then the untouched suggestions, into what's left.
        for kind in intermissions
        where kind.enabled && runsToday(kind, on: day)
            && !skipped.contains(kind.id) && !swappedAway.contains(kind.id)
            && !edited.contains(kind.id) && !placed.contains(kind.id) {
            guard let slot = place(kind, in: free(), blocks: blocks, day: day), claim(kind.id) else { continue }
            let length = resized[kind.id].map { TimeInterval(max(5, $0) * 60) } ?? slot.length ?? kind.length
            blocks.append(PlanBlock(
                kind: .intermission(id: kind.id),
                start: slot.start,
                end: slot.start.addingTimeInterval(length),
                title: kind.name,
                subline: slot.subline,
                badge: "Suggested",
                isShortened: length < kind.length
            ))
        }

        // Whatever is still empty, so the day reads as a whole.
        for gap in gaps(around: blocks, from: dayStart, to: dayEnd) where gap.end.timeIntervalSince(gap.start) >= 300 {
            blocks.append(PlanBlock(kind: .open, start: gap.start, end: gap.end, title: "Open", subline: nil))
        }

        return blocks.sorted { $0.start < $1.start }
    }

    // MARK: - Placing

    private struct Gap {
        var start: Date
        var end: Date
        var length: TimeInterval { end.timeIntervalSince(start) }
    }

    private struct Slot {
        var start: Date
        var subline: String?
        /// How long it actually gets; shorter than asked for on a tight day.
        var length: TimeInterval?
    }

    /// A block Carl placed himself. It keeps its time even when the day has
    /// moved under it - the plan says it overlaps rather than quietly moving
    /// what he asked for.
    private func fixed(
        _ kind: IntermissionKind, at start: Date, length: TimeInterval,
        blocks: [PlanBlock], subline: String
    ) -> PlanBlock {
        PlanBlock(
            kind: .intermission(id: kind.id),
            start: start,
            end: start.addingTimeInterval(length),
            title: kind.name,
            subline: collides(start, minutes: Int(length / 60), with: blocks) ? "Overlaps what's booked" : subline,
            badge: "Yours"
        )
    }

    private func collides(_ start: Date, minutes: Int, with blocks: [PlanBlock]) -> Bool {
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        return blocks.contains { block in
            guard !isOpen(block) else { return false }
            return block.start < end && start < block.end
        }
    }

    private func runsToday(_ kind: IntermissionKind, on day: Date) -> Bool {
        switch kind.cadence {
        case .daily, .twiceDaily: true
        case .weekly(let weekday): calendar.component(.weekday, from: day) == weekday.rawValue
        }
    }

    private func place(_ kind: IntermissionKind, in gaps: [Gap], blocks: [PlanBlock], day: Date) -> Slot? {
        let full = gaps.filter { $0.length >= kind.length }
        // Nothing big enough: take the best of what's left, if it's still
        // long enough to be worth doing.
        guard !full.isEmpty else {
            guard kind.shortestLength < kind.length,
                  let best = gaps.filter({ $0.length >= kind.shortestLength }).max(by: { $0.length < $1.length })
            else { return nil }
            return Slot(
                start: best.start,
                subline: "\(Int(best.length / 60)) min — the gaps are tight today",
                length: best.length
            )
        }
        let fits = full

        switch kind.preference {
        case .around(let minutes):
            let target = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)!
            if let onTime = fits.first(where: { $0.start <= target && $0.end >= target.addingTimeInterval(kind.length) }) {
                return Slot(start: max(onTime.start, target), subline: nil)
            }
            // Nothing free at the usual time: take the nearest gap and say why.
            if let nearest = fits.min(by: {
                abs($0.start.timeIntervalSince(target)) < abs($1.start.timeIntervalSince(target))
            }) {
                let early = nearest.start < target
                return Slot(
                    start: nearest.start,
                    subline: early ? "Moved up — the usual time is busy" : "Moved later — the usual time is busy"
                )
            }
            return nil

        case .afternoon, .lateAfternoon:
            let fromHour = kind.preference == .lateAfternoon ? 15 : 12
            let from = calendar.date(bySettingHour: fromHour, minute: 0, second: 0, of: day)!
            let afternoon = fits.filter { $0.end > from }
            // The largest gap, so reading gets room to be worth starting.
            guard let biggest = (afternoon.isEmpty ? fits : afternoon).max(by: { $0.length < $1.length }) else { return nil }
            return Slot(start: max(biggest.start, min(from, biggest.end.addingTimeInterval(-kind.length))), subline: nil)

        case .beforeSeated:
            let seatedStarts = blocks.compactMap { block -> Date? in
                if case .session(let virtual) = block.kind, virtual { return block.start }
                return nil
            }
            for start in seatedStarts.sorted() {
                if let gap = fits.first(where: { $0.end >= start && $0.start <= start.addingTimeInterval(-kind.length) }) {
                    return Slot(
                        start: min(start.addingTimeInterval(-kind.length), gap.end.addingTimeInterval(-kind.length)),
                        subline: "Before a seated session"
                    )
                }
            }
            guard let any = fits.max(by: { $0.length < $1.length }) else { return nil }
            return Slot(start: any.start, subline: nil)
        }
    }

    /// Trims gaps to the working windows, so a Thursday's 10:30-13:30 hole
    /// isn't offered as somewhere to put lunch.
    private func within(_ gaps: [Gap], _ windows: [DateInterval]) -> [Gap] {
        guard !windows.isEmpty else { return gaps }
        return gaps.flatMap { gap in
            windows.compactMap { window -> Gap? in
                let start = max(gap.start, window.start)
                let end = min(gap.end, window.end)
                return end > start ? Gap(start: start, end: end) : nil
            }
        }
    }

    private func gaps(around blocks: [PlanBlock], from dayStart: Date, to dayEnd: Date) -> [Gap] {
        let busy = blocks
            .filter { !isOpen($0) }
            .map { (start: $0.start, end: $0.end) }
            .sorted { $0.start < $1.start }

        var gaps: [Gap] = []
        var cursor = dayStart
        for block in busy {
            if block.start > cursor { gaps.append(Gap(start: cursor, end: min(block.start, dayEnd))) }
            cursor = max(cursor, block.end)
        }
        if cursor < dayEnd { gaps.append(Gap(start: cursor, end: dayEnd)) }
        return gaps.filter { $0.length > 0 }
    }

    private func isOpen(_ block: PlanBlock) -> Bool {
        if case .open = block.kind { return true }
        return false
    }
}
