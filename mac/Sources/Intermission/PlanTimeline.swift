import DeskCore
import SwiftUI

/// The day drawn to scale: an hour is an hour tall, so a gap looks like the
/// time it is. The list it replaced gave every block the same weight, which
/// made a ten-minute note and a fifty-minute lunch read the same.
struct PlanTimeline: View {
    @Bindable var model: AppModel

    /// A minute of the day, in points. An eight-hour day is about 700pt,
    /// which scrolls once rather than endlessly.
    static let pointsPerMinute: CGFloat = 1.4
    static let snapMinutes = 5
    private let gutter: CGFloat = 52

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(model.shownPlan) { block in
                    Group {
                        if block.kind == .open {
                            OpenSpace(block: block, model: model)
                        } else {
                            TimelineBlock(block: block, model: model)
                        }
                    }
                    .frame(height: height(of: block))
                    .padding(.leading, gutter)
                    .offset(y: y(block.start))
                }
                if model.planDay == .today, let y = nowY {
                    nowLine.offset(y: y)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: totalHeight, alignment: .top)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Geometry

    /// The hours the timeline covers. On today it always includes now, even
    /// before the day's first block - otherwise the red line has nowhere to
    /// be, which is why it kept not showing up first thing in the morning.
    private var window: DateInterval {
        guard let first = model.shownPlan.first?.start, let last = model.shownPlan.last?.end, last > first
        else { return DateInterval(start: model.shownDate, duration: 3600) }
        guard model.planDay == .today else { return DateInterval(start: first, end: last) }
        return DateInterval(
            start: min(first, model.now.addingTimeInterval(-15 * 60)),
            end: max(last, model.now.addingTimeInterval(15 * 60))
        )
    }

    private var totalHeight: CGFloat { CGFloat(window.duration / 60) * Self.pointsPerMinute }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(window.start) / 60) * Self.pointsPerMinute
    }

    private func height(of block: PlanBlock) -> CGFloat {
        max(14, CGFloat(block.length / 60) * Self.pointsPerMinute)
    }

    private var nowY: CGFloat? {
        guard model.now >= window.start, model.now <= window.end else { return nil }
        return y(model.now)
    }

    /// The hours, labelled down the left, so a block's place means something
    /// without reading its times.
    private var hourLines: some View {
        ForEach(hours, id: \.self) { hour in
            HStack(spacing: 8) {
                Text(clockTime(hour))
                    .font(Theme.ui(10))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .frame(width: gutter - 8, alignment: .trailing)
                Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
            }
            .offset(y: y(hour) - 5)
        }
    }

    private var hours: [Date] {
        var hours: [Date] = []
        var cursor = Calendar.current.date(
            bySetting: .minute, value: 0,
            of: Calendar.current.date(byAdding: .hour, value: 1, to: window.start) ?? window.start
        ) ?? window.start
        while cursor < window.end {
            hours.append(cursor)
            cursor = Calendar.current.date(byAdding: .hour, value: 1, to: cursor) ?? window.end
        }
        return hours
    }

    private var nowLine: some View {
        HStack(spacing: 0) {
            Circle().fill(Theme.now).frame(width: 7, height: 7)
            Rectangle().fill(Theme.now).frame(height: 1)
        }
        .padding(.leading, gutter - 3)
    }
}

/// An empty stretch, and the offer to put something in it.
struct OpenSpace: View {
    let block: PlanBlock
    @Bindable var model: AppModel
    @State private var isHovering = false

    /// The goal with the most left to do this week that would fit here, and
    /// the time it would start - which is now, not this morning, when the
    /// stretch has already begun.
    private var goalOnOffer: (kind: IntermissionKind, start: Date)? {
        guard model.rebalance == nil,                          // the banner owns this gap
              model.isWorkingDay(model.shownDate),
              block.end > model.now
        else { return nil }
        let remaining = model.goalsRemaining
        let onToday = Set(model.shownPlan.compactMap { $0.isGoal ? $0.intermissionID : nil })
        let stretch = DateInterval(start: block.start, end: block.end)
        return model.goals
            .filter { !onToday.contains($0.id) && (remaining[$0.id] ?? 0) > 0 }
            .compactMap { goal in model.start(for: goal, in: stretch).map { (goal, $0) } }
            .max { (remaining[$0.kind.id] ?? 0) < (remaining[$1.kind.id] ?? 0) }
    }

    /// "45 min", "3h 20m" - four hundred and eighty minutes is not a length
    /// anybody reads as a number of hours.
    private func spanned(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 120 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    var body: some View {
        let candidates = model.candidates(for: block)
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.background.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .overlay {
                if block.length >= 15 * 60 {
                    HStack(spacing: 6) {
                        Text(block.title == "Open" ? "\(spanned(block.length)) open" : block.title)
                            .font(Theme.ui(11))
                            .foregroundStyle(isHovering ? Theme.ink : Theme.muted)
                        Spacer(minLength: 8)
                        // A goal with a week still to fill, and room here for
                        // it. Offered, never placed - that's the whole point
                        // of a goal.
                        if let goal = goalOnOffer {
                            Button {
                                model.placeGoal(goal.kind.id, on: model.shownDate, at: goal.start)
                            } label: {
                                Text("+ \(goal.kind.name) at \(clockTime(goal.start))")
                                    .font(Theme.ui(11))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Theme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isHovering ? Theme.ink.opacity(0.45) : Theme.border, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                        if !candidates.isEmpty {
                            Menu("Fill it") {
                                ForEach(candidates, id: \.id) { kind in
                                    // The whole gap; drag the edge to shrink it.
                                    Button("\(kind.name) · \(Int(block.length / 60)) min") {
                                        model.fill(block, with: kind)
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 60)
                            .font(Theme.ui(11))
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .onHover { isHovering = $0 }
    }
}

/// A block on the timeline. Intermissions can be dragged to move and their
/// bottom edge dragged to stretch or shorten; everything else is fixed.
struct TimelineBlock: View {
    let block: PlanBlock
    @Bindable var model: AppModel
    @State private var dragOffset: CGFloat = 0
    @State private var dragMinutes = 0
    @State private var resizeMinutes = 0
    @State private var isEditing = false
    @State private var isEditingTimes = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(model.color(for: block.kind))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(block.title).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
                    if let badge = block.badge, block.length >= 20 * 60 {
                        Text(badge)
                            .font(Theme.ui(9, weight: .medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.surface)
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                            .clipShape(Capsule())
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(times).font(Theme.ui(10)).monospacedDigit().foregroundStyle(Theme.muted)
                    // Every fixed block can be edited, however short: the
                    // ten-minute one is exactly the one that didn't happen.
                    if isFixed {
                        Button("Edit") { isEditing = true }
                            .buttonStyle(.plain)
                            .font(Theme.ui(12))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(isEditing ? Theme.background : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .popover(isPresented: $isEditing, arrowEdge: .trailing) {
                                FixedBlockEditor(block: block, model: model, isPresented: $isEditing)
                            }
                    }
                }
                if let subline, block.length >= 25 * 60 {
                    Text(subline).font(Theme.ui(10)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                if isDraggable, block.length >= 30 * 60, let id = intermissionID {
                    HStack(spacing: 8) {
                        if block.isGoal {
                            Button("Remove") { model.removeFromPlan(id) }
                                .buttonStyle(.borderless)
                            Button(isGoalDone ? "Not done" : "Done") {
                                model.toggleGoalDone(id, on: model.shownDate)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Theme.muted)
                            Button("Edit times") { isEditingTimes = true }
                                .buttonStyle(.borderless)
                        } else {
                            Button("Edit times") { isEditingTimes = true }
                                .buttonStyle(.borderless)
                            Menu("Swap") {
                                ForEach(model.swapCandidates.filter { $0.id != id }, id: \.id) { kind in
                                    Button(kind.name) { model.apply(.swapped(for: kind.id), to: id) }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 52)
                            Button(model.isOneOff(id) ? "Remove" : "Skip") { model.removeFromPlan(id) }
                                .buttonStyle(.borderless)
                            if block.isMine, !model.isOneOff(id) {
                                Button("Undo") { model.undoEdits(for: id) }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                    }
                    .font(Theme.ui(10))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.color(for: block.kind).opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) { if isDraggable { resizeHandle } }
        .overlay(alignment: .topTrailing) { if dragMinutes != 0 || resizeMinutes != 0 { liveLabel } }
        .offset(y: isDraggable ? dragOffset : 0)
        .gesture(isDraggable ? moveGesture : nil)
        .animation(.interactiveSpring, value: dragOffset)
        // Short blocks have no room for buttons, so every block's actions are
        // here too - a ten-minute stretch was impossible to remove otherwise.
        .popover(isPresented: $isEditingTimes, arrowEdge: .trailing) {
            IntermissionTimes(
                block: block, day: model.shownDate, model: model, isPresented: $isEditingTimes
            )
        }
        .onTapGesture(count: 2) { if isDraggable { isEditingTimes = true } }
        .contextMenu {
            if let id = intermissionID {
                Button("Edit times…") { isEditingTimes = true }
                Divider()
                if block.isGoal {
                    Button("Take it off today") { model.removeFromPlan(id) }
                    Button(isGoalDone ? "Mark as not done" : "Mark as done") {
                        model.toggleGoalDone(id, on: model.shownDate)
                    }
                } else {
                    Button(model.isOneOff(id) ? "Remove" : "Skip today") { model.removeFromPlan(id) }
                    Menu("Swap for") {
                        ForEach(model.swapCandidates.filter { $0.id != id }, id: \.id) { kind in
                            Button(kind.name) { model.apply(.swapped(for: kind.id), to: id) }
                        }
                    }
                    Divider()
                    Button("Back to the suggestion") { model.undoEdits(for: id) }
                }
            } else if isFixed {
                Button("Edit…") { isEditing = true }
                Button("Didn't happen") {
                    if let target = block.target { model.apply(.didNotHappen, to: target) }
                }
            }
        }
    }

    /// A goal's line leads with where it is in the week, because that's the
    /// thing it's for: "2 of 3 this week · desk can come down".
    private var subline: String? {
        guard block.isGoal, let id = intermissionID else { return block.subline }
        let progress = model.goalProgress(id)
        let week = "\(progress.done + progress.planned) of \(progress.target) this week"
        guard let existing = block.subline, existing != "Weekly goal" else { return week }
        return "\(week) · \(existing.replacingOccurrences(of: "Weekly goal · ", with: ""))"
    }

    private var times: String {
        "\(clockTime(block.start)) – \(clockTime(block.end))"
    }

    private var isDraggable: Bool { intermissionID != nil }

    /// Sessions and calendar events: the day as it was handed to him.
    private var isFixed: Bool {
        switch block.kind {
        case .session, .calendarEvent: true
        default: false
        }
    }

    private var isGoalDone: Bool {
        guard let id = intermissionID, let slot = model.goalSlot(id, on: model.shownDate) else { return false }
        return model.goalIsDone(slot)
    }

    private var intermissionID: String? {
        if case .intermission(let id) = block.kind { return id }
        return nil
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                dragOffset = value.translation.height
                dragMinutes = snapped(value.translation.height)
            }
            .onEnded { value in
                let minutes = snapped(value.translation.height)
                dragOffset = 0
                dragMinutes = 0
                guard minutes != 0, let id = intermissionID else { return }
                model.apply(.moved(to: block.start.addingTimeInterval(TimeInterval(minutes * 60))), to: id)
            }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 7)
            .contentShape(Rectangle())
            .onHover { $0 ? NSCursor.resizeUpDown.set() : NSCursor.arrow.set() }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { resizeMinutes = snapped($0.translation.height) }
                    .onEnded { value in
                        let change = snapped(value.translation.height)
                        resizeMinutes = 0
                        guard change != 0, let id = intermissionID else { return }
                        model.apply(.resized(minutes: max(5, Int(block.length / 60) + change)), to: id)
                    }
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(model.color(for: block.kind).opacity(0.6))
                    .frame(width: 26, height: 3)
            }
    }

    private var liveLabel: some View {
        Text(labelText)
            .font(Theme.ui(10, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.ink)
            .foregroundStyle(Theme.surface)
            .clipShape(Capsule())
            .offset(x: -6, y: -8)
    }

    private var labelText: String {
        if resizeMinutes != 0 {
            return "\(max(5, Int(block.length / 60) + resizeMinutes)) min"
        }
        return clockTime(block.start.addingTimeInterval(TimeInterval(dragMinutes * 60)))
    }

    private func snapped(_ translation: CGFloat) -> Int {
        let minutes = Int((translation / PlanTimeline.pointsPerMinute).rounded())
        return (minutes / PlanTimeline.snapMinutes) * PlanTimeline.snapMinutes
    }
}
