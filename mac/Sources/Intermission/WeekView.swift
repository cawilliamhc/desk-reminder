import DeskCore
import SwiftUI

/// The week as a grid, and the tray of goals waiting for a day.
///
/// Weekly goals are never placed for Carl, so somewhere has to exist for him
/// to place them - and a week is the only scale at which "three times a week"
/// is a thing you can see. Drag a goal onto a slot, or click it. A slot in
/// the past is how something he did but never planned gets on the record.
struct WeekView: View {
    @Bindable var model: AppModel

    /// The block the pointer is over, described in one line under the
    /// headline. At this scale a block is a stripe; the readout is what
    /// makes it legible.
    @State private var hovered: String?
    @State private var isTrayTargeted = false
    private let gutter: CGFloat = 34
    private let headerHeight: CGFloat = 34
    /// Below this a column stops being readable, so the grid scrolls instead.
    private let leastPointsPerMinute: CGFloat = 0.55

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker).font(Theme.ui(12)).foregroundStyle(Theme.muted)
                Text(headline)
                    .font(Theme.headline(22))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
                Text(hovered ?? hint)
                    .font(Theme.ui(12))
                    .foregroundStyle(hovered == nil ? Theme.muted : Theme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 16) {
                tray
                // The grid divides the day into the height it's given, so a
                // taller window is a taller week rather than the same small
                // one with space underneath it.
                GeometryReader { geometry in
                    let fitted = (geometry.size.height - headerHeight - 8) / CGFloat(hours.duration / 60)
                    let scale = max(leastPointsPerMinute, fitted)
                    ScrollView(.vertical) {
                        grid(pointsPerMinute: scale)
                    }
                    .scrollDisabled(fitted >= leastPointsPerMinute)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
    }

    private var kicker: String {
        let start = WeekPlan.weekStart(of: model.now)
        let days = model.weekDays.count { model.isDeskDay($0) }
        return "Week of \(start.formatted(.dateTime.month(.wide).day())) · \(spell(days)) desk days"
    }

    private var headline: String {
        let goals = model.goals
        guard !goals.isEmpty else { return "No weekly goals yet." }
        let parts = goals.map { goal -> String in
            let progress = model.goalProgress(goal.id)
            return "\(goal.name.lowercased()) \(progress.done + progress.planned) of \(progress.target)"
        }
        let joined = parts.joined(separator: ", ")
        let left = model.goalSlotsLeft
        return joined.prefix(1).uppercased() + joined.dropFirst() + ". "
            + (left == 0 ? "Every goal has a slot." : "\(spell(left).capitalized) still without a slot.")
    }

    // MARK: - Tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weekly goals").font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                if isTrayTargeted {
                    Text("drop to take off").font(Theme.ui(10)).foregroundStyle(Theme.primary)
                }
            }
            ForEach(model.goals) { goal in
                trayCard(goal)
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 2) {
                Divider().padding(.bottom, 6)
                Text("Standing this week").font(Theme.ui(11)).foregroundStyle(Theme.muted)
                Text(model.weekStandingShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(Theme.headline(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text("avg of days recorded · goal \(Int((model.weeklyStandingGoal * 100).rounded()))%")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 140)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTrayTargeted ? Theme.primary.opacity(0.08) : .clear)
                .padding(-6)
        )
        .dropDestination(for: String.self) { payloads, _ in takeOff(payloads) } isTargeted: { isTrayTargeted = $0 }
    }

    private var hint: String {
        guard let id = model.selectedGoalID,
              let goal = model.goals.first(where: { $0.id == id })
        else { return "Drag a goal onto a slot, or pick one and click. Hover a block to see what it is." }
        return "Now click a slot that fits \(goal.minutes) min. One in the past counts as done."
    }

    private func trayCard(_ goal: IntermissionKind) -> some View {
        let selected = model.selectedGoalID == goal.id
        let progress = model.goalProgress(goal.id)
        return Button {
            model.selectedGoalID = selected ? nil : goal.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.color(token: goal.colorToken))
                        .frame(width: 8, height: 8)
                    Text(goal.name).font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
                GoalPips(progress: progress, color: Theme.color(token: goal.colorToken))
                Text("\(progress.done + progress.planned) of \(progress.target) · \(goal.minutes) min")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.surface : Theme.background)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Theme.primary : Theme.border, lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            model.selectedGoalID = goal.id
            return NSItemProvider(object: "goal:\(goal.id)" as NSString)
        }
    }

    /// Dragging a placed goal back here takes it off the day.
    private func takeOff(_ payloads: [String]) -> Bool {
        guard let payload = payloads.first else { return false }
        let parts = payload.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "move", let stamp = TimeInterval(parts[2]) else { return false }
        model.removeGoal(parts[1], on: Date(timeIntervalSince1970: stamp))
        return true
    }

    // MARK: - Grid

    private var hours: DateInterval { model.weekHours }

    private func grid(pointsPerMinute scale: CGFloat) -> some View {
        let height = CGFloat(hours.duration / 60) * scale
        return HStack(alignment: .top, spacing: 6) {
            hourGutter(scale: scale, height: height)
            ForEach(model.weekDays, id: \.self) { day in
                dayColumn(day, scale: scale, height: height)
            }
        }
        // The hour lines run behind every column, so the eye can carry a
        // time across the week without counting blocks.
        .background(alignment: .top) {
            VStack(spacing: 0) {
                Spacer().frame(height: headerHeight)
                ZStack(alignment: .topLeading) {
                    ForEach(hourMarks, id: \.self) { mark in
                        Rectangle()
                            .fill(Theme.border.opacity(0.6))
                            .frame(height: 1)
                            .offset(y: y(mark, scale: scale))
                    }
                }
                .frame(height: height, alignment: .top)
            }
            .padding(.leading, gutter)
        }
    }

    private func hourGutter(scale: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: headerHeight)
            ZStack(alignment: .topTrailing) {
                Color.clear.frame(height: height)
                ForEach(hourMarks, id: \.self) { mark in
                    Text(clockTime(mark))
                        .font(Theme.ui(10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .offset(x: -6, y: y(mark, scale: scale) - 6)
                }
            }
        }
        .frame(width: gutter)
    }

    private var hourMarks: [Date] {
        var marks: [Date] = []
        var cursor = Calendar.current.date(
            bySetting: .minute, value: 0,
            of: Calendar.current.date(byAdding: .hour, value: 1, to: hours.start) ?? hours.start
        ) ?? hours.start
        while cursor < hours.end {
            marks.append(cursor)
            cursor = Calendar.current.date(byAdding: .hour, value: 1, to: cursor) ?? hours.end
        }
        return marks
    }

    private func y(_ date: Date, scale: CGFloat) -> CGFloat {
        CGFloat(sameDayMinutes(date)) * scale
    }

    /// Minutes from the top of the grid, using the clock rather than the date
    /// so every column can share one vertical scale.
    private func sameDayMinutes(_ date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.component(.hour, from: hours.start) * 60 + calendar.component(.minute, from: hours.start)
        let point = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return max(0, point - start)
    }

    private func dayColumn(_ day: Date, scale: CGFloat, height: CGFloat) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let rest = model.isRestDay(day)
        return VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
                        .font(Theme.ui(12, weight: isToday ? .semibold : .medium))
                        .foregroundStyle(Theme.ink)
                    if isToday { Text("Today").font(Theme.ui(10)).foregroundStyle(Theme.muted) }
                    Spacer(minLength: 0)
                }
                Text(dayMeta(day)).font(Theme.ui(10)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .frame(height: headerHeight - 4, alignment: .topLeading)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(rest ? Theme.background.opacity(0.7) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isToday ? Theme.ink.opacity(0.35) : Theme.border, lineWidth: isToday ? 1.5 : 1)
                    )
                if rest {
                    RestHatch().stroke(Theme.border, lineWidth: 2).opacity(0.7)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    ForEach(model.weekBlocks(on: day), id: \.id) { block in
                        WeekBlock(
                            block: block, day: day, model: model,
                            height: CGFloat(block.length / 60) * scale,
                            hovered: $hovered
                        )
                        .offset(y: y(block.start, scale: scale))
                        .padding(.horizontal, 2)
                    }
                }
                if isToday, let y = nowY(scale: scale) {
                    HStack(spacing: 0) {
                        Circle().fill(Theme.now).frame(width: 5, height: 5)
                        Rectangle().fill(Theme.now).frame(height: 1)
                    }
                    .offset(y: y - 2)
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(day < Calendar.current.startOfDay(for: model.now) ? 0.82 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func nowY(scale: CGFloat) -> CGFloat? {
        let y = y(model.now, scale: scale)
        let height = CGFloat(hours.duration / 60) * scale
        return y > 0 && y < height ? y : nil
    }

    /// The line under a day's name: how it went, or what's on it.
    private func dayMeta(_ day: Date) -> String {
        if model.isRestDay(day) { return "Time off" }
        let share = model.standingShare(on: day).map { "\(Int(($0 * 100).rounded()))%" }
        if Calendar.current.isDateInToday(day) {
            return share.map { "\($0) so far" } ?? "today"
        }
        if let share { return "stood \(share)" }
        let sessions = model.weekBlocks(on: day).count {
            if case .session = $0.kind { return true } else { return false }
        }
        if sessions > 0 { return "\(sessions) \(sessions == 1 ? "session" : "sessions")" }
        return model.isDeskDay(day) ? "desk day" : "no sessions"
    }

    private func spell(_ n: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven"]
        return words.indices.contains(n) ? words[n] : "\(n)"
    }
}

/// The diagonal hatch that marks time off.
struct RestHatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += 7
        }
        return path
    }
}

/// One block in the Week grid: named when there's room, described in the
/// readout on hover, and - if it's a goal - removable or markable.
struct WeekBlock: View {
    let block: PlanBlock
    let day: Date
    @Bindable var model: AppModel
    let height: CGFloat
    @Binding var hovered: String?

    @State private var isHovering = false
    @State private var isTargeted = false
    @State private var isEditing = false

    var body: some View {
        content
            .frame(height: max(3, height), alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The times on the card itself, because that's where the eye
            // already is. The line under the headline says the rest.
            .overlay(alignment: .topLeading) {
                if isHovering, block.kind != .open {
                    Text("\(clockTime(block.start))–\(clockTime(block.end))")
                        .font(Theme.ui(10, weight: .medium))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.ink)
                        .foregroundStyle(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .offset(x: 2, y: height >= 26 ? 14 : -4)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(isHovering ? 2 : 0)
            .onHover { inside in
                isHovering = inside
                if inside {
                    hovered = readout
                } else if hovered == readout {
                    hovered = nil
                }
            }
            .help(readout)
    }

    /// A drop from the tray ("goal:id") or from another slot
    /// ("move:id:day"). Anything else, or anything that doesn't fit, is
    /// refused so the drag springs back.
    private func accept(_ payloads: [String]) -> Bool {
        guard let payload = payloads.first, model.isWorkingDay(day) else { return false }
        let parts = payload.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return false }
        let id = parts[1]

        // Something already on a day, dragged somewhere else. Anything can
        // move, whether or not it's been and gone: a call that ran at four
        // rather than three is still a call that happened.
        if parts[0] == "move", parts.count == 3, let stamp = TimeInterval(parts[2]) {
            let from = Date(timeIntervalSince1970: stamp)
            guard let moving = model.weekBlocks(on: from).first(where: { $0.intermissionID == id }),
                  block.length >= moving.length
            else { return false }
            model.move(moving, from: from, to: day, at: block.start)
            return true
        }

        // A goal from the tray.
        guard let goal = model.goals.first(where: { $0.id == id }),
              model.goalSlot(goal.id, on: day) == nil,
              block.length >= goal.length
        else { return false }
        model.placeGoal(goal.id, on: day, at: block.start)
        return true
    }

    @ViewBuilder
    private var content: some View {
        if block.kind == .open {
            openSpace
        } else if block.isGoal {
            goal
        } else {
            fixed
        }
    }

    /// The name, when the block is tall enough to hold it. Anything shorter
    /// is a stripe, and the readout says what it is.
    @ViewBuilder
    private func label(_ text: String, colour: Color = Theme.ink) -> some View {
        if height >= 15 {
            Text(text)
                .font(Theme.ui(10, weight: .medium))
                .foregroundStyle(colour)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .lineLimit(1)
        }
    }

    private var fixed: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isHovering ? Theme.ink.opacity(0.45) : .clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topLeading) { label(shortTitle, colour: labelColour) }
            .modifier(Editable(block: block, day: day, model: model, isEditing: $isEditing))
    }

    private var shortTitle: String {
        switch block.kind {
        case .session(let virtual): virtual ? "Virtual" : "Session"
        case .note: "Note"
        default: block.title
        }
    }

    /// Sessions and calendar blocks are solid, so their labels go light.
    private var labelColour: Color {
        switch block.kind {
        case .session, .calendarEvent: Theme.surface
        default: Theme.ink
        }
    }

    private var fill: Color {
        switch block.kind {
        case .session: Theme.session
        case .note: Theme.standing
        case .calendarEvent: Theme.calendar
        default: model.color(for: block.kind).opacity(0.55)
        }
    }

    private var goal: some View {
        let colour = model.color(for: block.kind)
        return RoundedRectangle(cornerRadius: 3)
            .fill(colour.opacity(isHovering ? 0.36 : 0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(colour, lineWidth: isHovering ? 2 : 1.5)
            )
            .overlay(alignment: .topLeading) { label(isDone ? "\(block.title) ✓" : block.title) }
            .modifier(Editable(block: block, day: day, model: model, isEditing: $isEditing))
    }

    private var isDone: Bool {
        model.goalSlot(block.intermissionID ?? "", on: day).map { model.goalIsDone($0) } ?? false
    }

    private var openSpace: some View {
        let droppable = canDrop || isTargeted
        return RoundedRectangle(cornerRadius: 3)
            .fill(droppable
                  ? Theme.primary.opacity(isHovering || isTargeted ? 0.2 : 0.08)
                  : Theme.ink.opacity(isHovering ? 0.05 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        droppable
                            ? Theme.primary.opacity(isHovering || isTargeted ? 1 : 0.45)
                            : Theme.border.opacity(isHovering ? 1 : 0),
                        lineWidth: droppable && (isHovering || isTargeted) ? 1.5 : 1
                    )
            )
            .overlay(alignment: .topLeading) {
                if let goal = selectedGoal, canDrop {
                    label("+ \(goal.name) \(clockTime(block.start))", colour: Theme.primary)
                } else if isTargeted {
                    label(clockTime(block.start), colour: Theme.primary)
                } else if isHovering {
                    label("\(Int(block.length / 60)) min free", colour: Theme.muted)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { place() }
            .dropDestination(for: String.self) { payloads, _ in accept(payloads) } isTargeted: { isTargeted = $0 }
            // Putting something in after the fact: the log only knows the
            // breaks he named at the time, and Monday's lunch happened
            // whether or not anybody wrote it down.
            .contextMenu {
                if model.isWorkingDay(day) {
                    ForEach(model.breaks.filter(\.enabled), id: \.id) { kind in
                        Button("\(kind.name) at \(clockTime(block.start))") {
                            model.recordBreak(
                                kind.id, on: day, at: block.start,
                                minutes: min(kind.minutes, max(5, Int(block.length / 60)))
                            )
                        }
                    }
                    Divider()
                    ForEach(model.goals, id: \.id) { goal in
                        Button("\(goal.name) at \(clockTime(block.start))") {
                            model.placeGoal(goal.id, on: day, at: block.start)
                        }
                        .disabled(model.goalSlot(goal.id, on: day) != nil)
                    }
                }
            }
    }

    private var selectedGoal: IntermissionKind? {
        model.goals.first { $0.id == model.selectedGoalID }
    }

    /// A slot can take the selected goal when it fits, the day isn't time
    /// off, and the goal isn't already on that day. The past is allowed:
    /// it's how something he did but never planned gets on the record.
    private var canDrop: Bool {
        guard let goal = selectedGoal, model.isWorkingDay(day) else { return false }
        guard model.goalSlot(goal.id, on: day) == nil else { return false }
        return block.length >= goal.length
    }

    private func place() {
        guard canDrop, let goal = selectedGoal else { return }
        model.placeGoal(goal.id, on: day, at: block.start)
    }

    /// The line under the headline: which day, what it is, and when.
    private var readout: String {
        let times = "\(clockTime(block.start))–\(clockTime(block.end))"
        let dayName = day.formatted(.dateTime.weekday(.abbreviated).day())
        if block.kind == .open {
            guard let goal = selectedGoal, canDrop else {
                return "\(dayName) · \(times) · \(Int(block.length / 60)) min open"
            }
            let past = block.start < model.now
            return "\(dayName) · \(times) · put \(goal.name.lowercased()) here"
                + (past ? ", as one you did" : "")
        }
        var parts = ["\(dayName) · \(shortTitle) · \(times)"]
        if block.isGoal {
            parts.append(isDone ? "done" : "planned")
        } else if let subline = block.subline {
            parts.append(subline)
        }
        return parts.joined(separator: " · ")
    }
}

/// What an intermission on the Week grid can have done to it: picked up and
/// dropped on another slot, opened for its times, taken off the day.
///
/// Everything with an intermission on it gets this, done or not. A stretch
/// that already happened is exactly the one whose times were wrong.
private struct Editable: ViewModifier {
    let block: PlanBlock
    let day: Date
    @Bindable var model: AppModel
    @Binding var isEditing: Bool

    func body(content: Content) -> some View {
        guard let id = block.intermissionID else { return AnyView(content) }
        // A block the log produced is a record of where he actually was.
        // Dragging it somewhere else wouldn't make it true.
        guard block.badge != "Happened" else {
            return AnyView(content.contextMenu {
                Text("From your computer log")
            })
        }
        let isDone = block.isGoal && (model.goalSlot(id, on: day).map { model.goalIsDone($0) } ?? false)
        return AnyView(
            content
                .onDrag { NSItemProvider(object: "move:\(id):\(Int(day.timeIntervalSince1970))" as NSString) }
                .onTapGesture(count: 2) { isEditing = true }
                .popover(isPresented: $isEditing, arrowEdge: .trailing) {
                    IntermissionTimes(block: block, day: day, model: model, isPresented: $isEditing)
                }
                .contextMenu {
                    Button("Edit times…") { isEditing = true }
                    if block.isGoal {
                        Button(isDone ? "Mark as not done" : "Mark as done") {
                            model.toggleGoalDone(id, on: day)
                        }
                        Button("Take it off this day") { model.removeGoal(id, on: day) }
                    } else {
                        Button("Take it off this day") {
                            model.clearEdits(for: .intermission(id), on: day)
                            if !model.isOneOff(id), model.isDeskDay(day) { model.recordSkip(id, on: day) }
                        }
                    }
                }
        )
    }
}
