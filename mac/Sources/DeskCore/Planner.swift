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
    /// Carl put this here, or moved it here. The plan doesn't take it back.
    public var isMine: Bool = false
    /// A weekly goal rather than a daily break.
    public var isGoal: Bool = false

    public var length: TimeInterval { end.timeIntervalSince(start) }
    public var isSuggestion: Bool {
        if case .intermission = kind { return true }
        return false
    }

    public var intermissionID: String? {
        if case .intermission(let id) = kind { return id }
        return nil
    }

    /// What an edit to this block would be about.
    public var target: PlanEdit.Target? {
        switch kind {
        case .intermission(let id): .intermission(id)
        case .session: .session(start: start)
        case .calendarEvent: .event(start: start, title: title)
        case .note, .open: nil
        }
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

    /// Whether he's at the computer during it. A video call is; a school
    /// pickup isn't. The guess is only ever a default - the Edit popover on
    /// the block is what settles it.
    public func isOnComputer(_ mode: CalendarEventMode) -> Bool {
        switch mode {
        case .onComputer: return true
        case .offComputer: return false
        case .guessFromTitle:
            let words = ["zoom", "meet", "call", "video", "hangout", "teams", "webinar", "screen share"]
            let lowercased = title.lowercased()
            return words.contains { lowercased.contains($0) }
        }
    }
}

/// Lays out the day: sessions and calendar events are fixed, a standing note
/// window follows each session, daily breaks go in the gaps that suit them,
/// and weekly goals go only where Carl has put them.
///
/// Made once in the morning and left alone. A plan that reshuffles itself
/// every time a session runs long is a plan you stop trusting - so when the
/// day slips, the plan stays put and the app offers the freed time back.
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
    /// Minutes to be back before a session starts. An intermission that runs
    /// up to the hour is one Carl arrives from, not one he comes back from.
    public var settleMinutes: Int
    /// Minutes of daylight between two intermissions.
    public var bufferMinutes: Int
    public var calendarEventMode: CalendarEventMode

    public init(
        calendar: Calendar = .current,
        intermissions: [IntermissionKind] = IntermissionKind.defaults,
        settleMinutes: Int = 10,
        bufferMinutes: Int = 10,
        calendarEventMode: CalendarEventMode = .guessFromTitle
    ) {
        self.calendar = calendar
        self.intermissions = intermissions
        self.settleMinutes = settleMinutes
        self.bufferMinutes = bufferMinutes
        self.calendarEventMode = calendarEventMode
    }

    public var breaks: [IntermissionKind] { intermissions.filter { !$0.isGoal } }
    public var goals: [IntermissionKind] { intermissions.filter(\.isGoal) }

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

    /// Today's daily breaks that couldn't be fitted anywhere. The plan is
    /// silent about them otherwise, and a silent absence reads as a bug.
    ///
    /// Goals are never in here: one that isn't on the day hasn't failed to
    /// fit, it simply wasn't asked for.
    public func unplaced(in blocks: [PlanBlock], on day: Date) -> [IntermissionKind] {
        breaks.filter { kind in
            kind.enabled && kind.runs(on: day, calendar: calendar)
                && !blocks.contains { $0.kind == .intermission(id: kind.id) }
        }
    }

    public func plan(
        sessions: [PublishedSession],
        events: [CalendarEvent] = [],
        on day: Date,
        edits: [PlanEdit] = [],
        goalSlots: [GoalSlot] = [],
        workday: DateInterval? = nil,
        configuredHours: DateInterval? = nil,
        workingWindows: [DateInterval] = []
    ) -> [PlanBlock] {
        let published = sessions.filter { calendar.isDate($0.start, inSameDayAs: day) }
        let publishedEvents = events.filter { calendar.isDate($0.start, inSameDayAs: day) }
        let today = Day(sessions: published, events: publishedEvents, edits: edits, calendar: calendar)
        // The day's hours come from what was booked, not from what survived
        // the edits: a cancelled eleven o'clock frees an hour of the day, and
        // an hour he's still in the office for.
        let window = workday ?? self.workday(
            sessions: published, events: publishedEvents,
            on: day, configuredHours: configuredHours
        )
        let dayStart = window.start
        let dayEnd = window.end

        var blocks = fixedBlocks(today, from: dayStart, to: dayEnd)

        // Carl's own changes first, so what's left lays out around them
        // rather than the other way round.
        let skipped = Set(edits.compactMap { edit -> String? in
            if case .skipped = edit.change { return edit.intermissionID }
            return nil
        })
        let swappedAway = Set(edits.compactMap { edit -> String? in
            if case .swapped = edit.change { return edit.intermissionID }
            return nil
        })

        // A length Carl set by hand, for today only.
        var resized: [String: Int] = [:]
        for edit in edits {
            if case .resized(let minutes) = edit.change, let id = edit.intermissionID {
                resized[id] = minutes
            }
        }
        func length(_ kind: IntermissionKind) -> TimeInterval {
            resized[kind.id].map { TimeInterval(max(5, $0) * 60) } ?? kind.length
        }

        // Up to one block per placement a kind is allowed. Stretch is twice a
        // day; everything else once, whatever route it took onto the plan.
        var placements: [String: Int] = [:]
        func claim(_ kind: IntermissionKind) -> Bool {
            let used = placements[kind.id] ?? 0
            guard used < max(1, kind.placementsPerDay) else { return false }
            placements[kind.id] = used + 1
            return true
        }

        func free() -> [Gap] {
            within(gaps(around: blocks, from: dayStart, to: dayEnd), workingWindows)
        }

        // What already has a place on this day, by his hand or by his
        // agreement when he started the day.
        let placedByHand = Set(edits.compactMap { edit -> String? in
            switch edit.change {
            case .moved, .added, .pinned: edit.intermissionID
            default: nil
            }
        })

        // An exact time is the most specific thing Carl can say, so moves and
        // one-offs are placed before a swap that might claim the same thing.
        let ordered = edits.filter { $0.intermissionID != nil }.sorted { a, b in
            func rank(_ change: PlanEdit.Change) -> Int {
                switch change {
                case .moved, .added, .pinned: 0
                case .swapped: 1
                default: 2                      // resize is applied above, not placed
                }
            }
            return rank(a.change) < rank(b.change)
        }

        for edit in ordered {
            guard let id = edit.intermissionID, !skipped.contains(id) else { continue }
            switch edit.change {
            case .moved(let start):
                guard let kind = intermissions.first(where: { $0.id == id }), claim(kind) else { continue }
                blocks.append(fixed(kind, at: start, length: length(kind), blocks: blocks, subline: "Moved by you"))
            case .pinned(let start):
                // Where this morning's plan put it. It stays there for the
                // rest of the day: a plan that re-lays itself out every time
                // a session moves is one he has to read twice.
                guard let kind = intermissions.first(where: { $0.id == id }), claim(kind) else { continue }
                blocks.append(fixed(kind, at: start, length: length(kind), blocks: blocks, subline: nil))
            case .added(let name, let minutes, let start):
                guard (placements[id] ?? 0) == 0 else { continue }
                placements[id] = 1
                blocks.append(PlanBlock(
                    kind: .intermission(id: id),
                    start: start,
                    end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                    title: name,
                    subline: collides(start, minutes: minutes, with: blocks) ? "Overlaps what's booked" : "Added by you",
                    badge: "Yours",
                    isMine: true
                ))
            case .swapped(let replacement):
                // Skipping the thing that was swapped IN takes it off the
                // plan too: the swap said "not stretch, reading instead", and
                // skipping reading means neither. And a replacement Carl has
                // since put somewhere himself is already on the day: the swap
                // asked for one of them, not two.
                guard !skipped.contains(replacement), !placedByHand.contains(replacement),
                      let kind = intermissions.first(where: { $0.id == replacement }),
                      claim(kind) else { continue }
                guard let (_, slot) = place(kind, in: free(), blocks: blocks, day: day, window: window)
                else { continue }
                let length = resized[kind.id].map { TimeInterval(max(5, $0) * 60) } ?? slot.length ?? kind.length
                blocks.append(PlanBlock(
                    kind: .intermission(id: kind.id),
                    start: slot.start,
                    end: slot.start.addingTimeInterval(length),
                    title: kind.name,
                    subline: subline("Swapped in by you", kind),
                    badge: badge(kind),
                    isShortened: length < kind.length,
                    isMine: true,
                    isGoal: kind.isGoal
                ))
            default:
                continue
            }
        }

        // Only the edits that PLACE something count as handled here. A resize
        // says how long, not where, so the suggestion still has to be laid out.
        let edited = Set(edits.compactMap { edit -> String? in
            switch edit.change {
            case .moved, .added, .swapped, .pinned: edit.intermissionID
            default: nil
            }
        })

        // Then the weekly goals Carl has put on this day. They're never
        // placed on their own: a goal with no slot simply isn't in the day.
        for slot in goalSlots where calendar.isDate(slot.day, inSameDayAs: day) {
            guard let kind = intermissions.first(where: { $0.id == slot.goalID }),
                  kind.enabled, kind.isGoal,
                  !skipped.contains(kind.id), !edited.contains(kind.id),
                  claim(kind) else { continue }
            let gaps = free()
            let wanted = slot.preferredStart
            // The slot he picked, if the day still has room for it there.
            if let wanted, gaps.contains(where: {
                $0.start <= wanted && $0.end >= wanted.addingTimeInterval(kind.length)
            }) {
                blocks.append(PlanBlock(
                    kind: .intermission(id: kind.id),
                    start: wanted,
                    end: wanted.addingTimeInterval(kind.length),
                    title: kind.name,
                    subline: subline("Weekly goal", kind),
                    badge: "Weekly goal",
                    isMine: true,
                    isGoal: true
                ))
                continue
            }
            guard let (_, best) = place(kind, in: gaps, blocks: blocks, day: day, window: window) else { continue }
            let length = best.length ?? kind.length
            let moved = wanted != nil && abs(best.start.timeIntervalSince(wanted!)) >= 60
            blocks.append(PlanBlock(
                kind: .intermission(id: kind.id),
                start: best.start,
                end: best.start.addingTimeInterval(length),
                title: kind.name,
                subline: subline(
                    moved ? "Moved from \(clock(wanted!)) — the day filled up" : "Weekly goal",
                    kind
                ),
                badge: "Weekly goal",
                isShortened: length < kind.length,
                isMine: true,
                isGoal: true
            ))
        }

        // And last, the daily breaks, into the gaps that are left. One to a
        // gap: two suggestions back to back in a ninety-minute hole is the
        // app filling the day rather than making room in it.
        var openGaps = free()
        for kind in breaks
        where kind.enabled && kind.runs(on: day, calendar: calendar)
            && !skipped.contains(kind.id) && !swappedAway.contains(kind.id)
            && !edited.contains(kind.id) {
            for _ in 0..<kind.placementsPerDay {
                guard (placements[kind.id] ?? 0) < kind.placementsPerDay,
                      let (index, slot) = place(kind, in: openGaps, blocks: blocks, day: day, window: window),
                      claim(kind) else { break }
                let length = resized[kind.id].map { TimeInterval(max(5, $0) * 60) } ?? slot.length ?? kind.length
                blocks.append(PlanBlock(
                    kind: .intermission(id: kind.id),
                    start: slot.start,
                    end: slot.start.addingTimeInterval(length),
                    title: kind.name,
                    subline: subline(slot.subline, kind),
                    badge: badge(kind),
                    isShortened: length < kind.length
                ))
                openGaps.remove(at: index)
            }
        }

        // Whatever is still empty, so the day reads as a whole. Time that
        // opened up is its own block rather than part of a longer hole: the
        // hour a session didn't happen in reads as an hour, not as "3:20
        // open" with a note attached.
        for gap in gaps(around: blocks, from: dayStart, to: dayEnd, buffered: false) {
            for piece in split(gap, around: today.freed) where piece.gap.length >= 300 {
                blocks.append(PlanBlock(
                    kind: .open, start: piece.gap.start, end: piece.gap.end,
                    title: piece.reason.map { "Open — \($0)" } ?? "Open",
                    subline: nil
                ))
            }
        }

        return blocks.sorted { $0.start < $1.start }
    }

    /// Cuts an empty stretch where freed time starts and stops, so each
    /// piece can say what it is.
    private func split(_ gap: Gap, around freed: [Freed]) -> [(gap: Gap, reason: String?)] {
        guard let overlap = freed.first(where: {
            $0.interval.start < gap.end && gap.start < $0.interval.end
        }) else { return [(gap, nil)] }

        var pieces: [(gap: Gap, reason: String?)] = []
        let middle = Gap(
            start: max(gap.start, overlap.interval.start),
            end: min(gap.end, overlap.interval.end)
        )
        if middle.start > gap.start {
            pieces += split(Gap(start: gap.start, end: middle.start), around: freed.filter { $0.reason != overlap.reason })
        }
        pieces.append((middle, overlap.reason))
        if gap.end > middle.end {
            pieces += split(Gap(start: middle.end, end: gap.end), around: freed.filter { $0.reason != overlap.reason })
        }
        return pieces
    }

    // MARK: - Today, as edited

    /// A session or event with today's edits folded in. The rest of the
    /// planner never sees the raw published version, so "didn't happen"
    /// can't half-apply.
    struct EditedSession {
        var published: PublishedSession
        var virtual: Bool
        var wantsNote: Bool
    }

    struct EditedEvent {
        var event: CalendarEvent
        var onComputer: Bool
    }

    struct Freed {
        var interval: DateInterval
        var reason: String
    }

    struct Day {
        var sessions: [EditedSession] = []
        var events: [EditedEvent] = []
        /// Time that opened up because something didn't happen or finished
        /// early. The open block over it says which.
        var freed: [Freed] = []

        init(sessions: [PublishedSession], events: [CalendarEvent], edits: [PlanEdit], calendar: Calendar) {
            for session in sessions.sorted(by: { $0.start < $1.start }) {
                let mine = edits.filter { $0.target == .session(start: session.start) }
                if mine.contains(where: { $0.change == .didNotHappen }) {
                    freed.append(Freed(
                        interval: DateInterval(start: session.start, end: session.end),
                        reason: "\(Self.clock(session.start, calendar)) session didn't happen"
                    ))
                    continue
                }
                var end = session.end
                var virtual = session.mode.isSeated
                var wantsNote = true
                for edit in mine {
                    switch edit.change {
                    case .endedEarly(let minutes):
                        let shortened = session.end.addingTimeInterval(TimeInterval(-minutes * 60))
                        if shortened > session.start {
                            end = shortened
                            freed.append(Freed(
                                interval: DateInterval(start: shortened, end: session.end),
                                reason: "\(Self.clock(session.start, calendar)) ended \(minutes) min early"
                            ))
                        }
                    case .mode(let raw):
                        virtual = PublishedSession.Mode(rawValue: raw)?.isSeated ?? virtual
                    case .skipNote:
                        wantsNote = false
                    default:
                        break
                    }
                }
                let edited = PublishedSession(
                    start: session.start, end: end,
                    mode: virtual ? .virtual : .inPerson
                )
                self.sessions.append(EditedSession(published: edited, virtual: virtual, wantsNote: wantsNote))
            }

            for event in events.sorted(by: { $0.start < $1.start }) {
                let mine = edits.filter { $0.target == .event(start: event.start, title: event.title) }
                if mine.contains(where: { $0.change == .didNotHappen }) {
                    freed.append(Freed(
                        interval: DateInterval(start: event.start, end: event.end),
                        reason: "\(event.title) is off"
                    ))
                    continue
                }
                var onComputer: Bool?
                for edit in mine {
                    if case .presence(let at) = edit.change { onComputer = at }
                }
                self.events.append(EditedEvent(event: event, onComputer: onComputer ?? false))
            }
        }

        static func clock(_ date: Date, _ calendar: Calendar) -> String {
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            return String(format: "%d:%02d", hour % 12 == 0 ? 12 : hour % 12, minute)
        }
    }

    private func fixedBlocks(_ today: Day, from dayStart: Date, to dayEnd: Date) -> [PlanBlock] {
        var blocks: [PlanBlock] = []
        let sessions = today.sessions
        for (index, session) in sessions.enumerated() {
            let published = session.published
            blocks.append(PlanBlock(
                kind: .session(virtual: session.virtual),
                start: published.start, end: published.end,
                title: "Session",
                subline: session.virtual ? "Virtual · seated" : "In person"
            ))

            // A note after every session, as close to it as the day allows -
            // Carl writes them while the session is still in his head. Back to
            // back, there's no room, and the plan says so by leaving it out.
            guard session.wantsNote else { continue }
            let wanted = published.end.addingTimeInterval(TimeInterval(Self.noteMinutes * 60))
            let nextFixed = [
                sessions.dropFirst(index + 1).first?.published.start,
                today.events.first { $0.event.start >= published.end }?.event.start,
                dayEnd,
            ].compactMap { $0 }.min() ?? dayEnd
            let noteEnd = min(wanted, nextFixed)
            if noteEnd.timeIntervalSince(published.end) >= TimeInterval(Self.minimumNoteMinutes * 60) {
                blocks.append(PlanBlock(
                    kind: .note, start: published.end, end: noteEnd,
                    title: "Note — standing", subline: nil
                ))
            }
        }

        for event in today.events {
            blocks.append(PlanBlock(
                kind: .calendarEvent, start: event.event.start, end: event.event.end,
                title: event.event.title,
                subline: event.onComputer ? "Personal calendar · on the computer" : "Personal calendar · off the computer",
                badge: "Calendar"
            ))
        }
        return blocks
    }

    // MARK: - Placing

    struct Gap {
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

    private func badge(_ kind: IntermissionKind) -> String {
        kind.isGoal ? "Weekly goal" : "Daily break"
    }

    /// The placement reason and the desk rule, the way the design has it:
    /// "Before a seated session · desk stays where it is".
    private func subline(_ reason: String?, _ kind: IntermissionKind) -> String? {
        let desk: String? = switch kind.deskRule {
        case .up: "desk up"
        case .down: "desk can come down"
        case .unchanged: "desk stays where it is"
        case .any: nil
        }
        let parts = [reason, desk].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "11:00". Shared with the rebalance copy, which quotes times constantly.
    func clock(_ date: Date) -> String {
        Day.clock(date, calendar)
    }

    /// A block Carl placed himself. It keeps its time even when the day has
    /// moved under it - the plan says it overlaps rather than quietly moving
    /// what he asked for.
    private func fixed(
        _ kind: IntermissionKind, at start: Date, length: TimeInterval,
        blocks: [PlanBlock], subline reason: String?
    ) -> PlanBlock {
        PlanBlock(
            kind: .intermission(id: kind.id),
            start: start,
            end: start.addingTimeInterval(length),
            title: kind.name,
            subline: collides(start, minutes: Int(length / 60), with: blocks)
                ? "Overlaps what's booked"
                : subline(reason, kind),
            badge: badge(kind),
            isMine: reason != nil,
            isGoal: kind.isGoal
        )
    }

    private func collides(_ start: Date, minutes: Int, with blocks: [PlanBlock]) -> Bool {
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        return blocks.contains { block in
            guard !isOpen(block) else { return false }
            return block.start < end && start < block.end
        }
    }

    private func place(
        _ kind: IntermissionKind, in gaps: [Gap], blocks: [PlanBlock], day: Date, window: DateInterval
    ) -> (index: Int, slot: Slot)? {
        let indexed = Array(gaps.enumerated())
        let full = indexed.filter { $0.element.length >= kind.length }
        // Nothing big enough: take the best of what's left, if it's still
        // long enough to be worth doing.
        guard !full.isEmpty else {
            guard kind.shortestLength < kind.length,
                  let best = indexed
                    .filter({ $0.element.length >= kind.shortestLength })
                    .max(by: { $0.element.length < $1.element.length })
            else { return nil }
            return (best.offset, Slot(
                start: best.element.start,
                subline: "\(Int(best.element.length / 60)) min — the gaps are tight today",
                length: best.element.length
            ))
        }

        switch kind.preference {
        case .around(let minutes):
            let target = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)!
            // The first gap from the target time on that fits, which is what
            // "from 12:00" means: lunch at noon, or as soon after as the day
            // allows.
            if let after = full
                .filter({ $0.element.end >= target.addingTimeInterval(kind.length) })
                .min(by: { $0.element.start < $1.element.start }) {
                let start = max(after.element.start, target)
                return (after.offset, Slot(
                    start: start,
                    subline: start > target.addingTimeInterval(60) ? "Later than usual — \(clock(target)) was busy" : nil
                ))
            }
            if let nearest = full.min(by: {
                abs($0.element.start.timeIntervalSince(target)) < abs($1.element.start.timeIntervalSince(target))
            }) {
                return (nearest.offset, Slot(
                    start: nearest.element.start,
                    subline: "Moved up — the usual time is busy"
                ))
            }
            return nil

        case .morning, .afternoon, .lateAfternoon:
            let hour = switch kind.preference {
            case .morning: 0
            case .lateAfternoon: 15
            default: 12
            }
            let from = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            let until = kind.preference == .morning
                ? calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
                : window.end
            let wanted = full.filter { $0.element.end > from && $0.element.start < until }
            // The largest gap, so a goal gets room to be worth starting.
            guard let biggest = (wanted.isEmpty ? full : wanted)
                .max(by: { $0.element.length < $1.element.length }) else { return nil }
            let gap = biggest.element
            return (biggest.offset, Slot(
                start: max(gap.start, min(from, gap.end.addingTimeInterval(-kind.length))),
                subline: wanted.isEmpty ? "The \(kind.preference == .morning ? "morning" : "afternoon") was full" : nil
            ))

        case .beforeSeated:
            let seatedStarts = blocks.compactMap { block -> Date? in
                if case .session(let virtual) = block.kind, virtual { return block.start }
                return nil
            }
            for start in seatedStarts.sorted() {
                // The gap stops short of the session by the settle time, so
                // "before a seated session" means before that edge.
                let edge = start.addingTimeInterval(-TimeInterval(settleMinutes * 60))
                if let gap = full.first(where: {
                    $0.element.end >= edge && $0.element.start <= edge.addingTimeInterval(-kind.length)
                }) {
                    return (gap.offset, Slot(
                        start: min(edge, gap.element.end).addingTimeInterval(-kind.length),
                        subline: "Before a seated session"
                    ))
                }
            }
            guard let any = full.max(by: { $0.element.length < $1.element.length }) else { return nil }
            return (any.offset, Slot(start: any.element.start, subline: nil))

        case .afterSitting(let minutes):
            // The planner can't know how long he's been sitting when the day
            // is laid out in the morning, so it reads the plan instead: the
            // first gap that comes far enough into the day to be a break from
            // sitting rather than part of the start of it.
            let earliest = window.start.addingTimeInterval(TimeInterval(minutes * 60))
            if let gap = full.filter({ $0.element.end >= earliest.addingTimeInterval(kind.length) })
                .min(by: { $0.element.start < $1.element.start }) {
                return (gap.offset, Slot(
                    start: max(gap.element.start, earliest),
                    subline: "After sitting a while"
                ))
            }
            guard let any = full.max(by: { $0.element.length < $1.element.length }) else { return nil }
            return (any.offset, Slot(start: any.element.start, subline: nil))
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

    /// The empty stretches of the day.
    ///
    /// `buffered` leaves `bufferMinutes` of daylight either side of an
    /// intermission, so the next one can't start the minute the last one
    /// ends. Lunch used to end at 3:05 and reading start at 3:05, which
    /// read as one long absence rather than two different things.
    func gaps(
        around blocks: [PlanBlock], from dayStart: Date, to dayEnd: Date, buffered: Bool = true
    ) -> [Gap] {
        let buffer = TimeInterval(buffered ? bufferMinutes * 60 : 0)
        let busy = blocks
            .filter { !isOpen($0) }
            .map { (start: $0.start, end: $0.end, isSession: isSession($0), isIntermission: $0.isSuggestion) }
            .sorted { $0.start < $1.start }

        var gaps: [Gap] = []
        var cursor = dayStart
        for block in busy {
            // Stop short of a session, so whatever fills the gap leaves time
            // to be back and settled before it starts.
            let edge = if block.isSession {
                block.start.addingTimeInterval(-TimeInterval(settleMinutes * 60))
            } else if block.isIntermission {
                block.start.addingTimeInterval(-buffer)
            } else {
                block.start
            }
            if edge > cursor { gaps.append(Gap(start: cursor, end: min(edge, dayEnd))) }
            cursor = max(cursor, block.isIntermission ? block.end.addingTimeInterval(buffer) : block.end)
        }
        if cursor < dayEnd { gaps.append(Gap(start: cursor, end: dayEnd)) }
        return gaps.filter { $0.length > 0 }
    }

    private func isSession(_ block: PlanBlock) -> Bool {
        if case .session = block.kind { return true }
        return false
    }

    private func isOpen(_ block: PlanBlock) -> Bool {
        if case .open = block.kind { return true }
        return false
    }
}
