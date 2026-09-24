import DeskCore
import SwiftUI

/// The week as a grid, and the tray of goals waiting for a day.
///
/// Weekly goals are never placed for Carl, so somewhere has to exist for him
/// to place them - and a week is the only scale at which "three times a week"
/// is a thing you can see. Drag a goal onto an open slot, or drag a placed
/// one back to the tray.
struct WeekView: View {
    @Bindable var model: AppModel

    /// A minute of the day, in points. Shorter than Plan's: a whole week has
    /// to fit at once or the grid stops being a grid.
    private let pointsPerMinute: CGFloat = 0.62
    private let gutter: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker).font(Theme.ui(12)).foregroundStyle(Theme.muted)
                Text(headline)
                    .font(Theme.headline(22))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
            }

            HStack(alignment: .top, spacing: 16) {
                tray
                grid
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
        let days = model.weekDays.count { model.isWorkingDay($0) }
        return "Week of \(start.formatted(.dateTime.month(.wide).day())) · \(spell(days)) desk days"
    }

    private var headline: String {
        let goals = model.goals
        guard !goals.isEmpty else { return "No weekly goals yet." }
        let parts = goals.map { goal -> String in
            let progress = model.goalProgress(goal.id)
            return "\(goal.name.lowercased()) \(progress.done + progress.planned) of \(progress.target)"
        }
        let sentence = parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst()
        let left = model.goalSlotsLeft
        return sentence + ". " + (left == 0
            ? "Every goal has a slot."
            : "\(spell(left).capitalized) still without a slot.")
    }

    // MARK: - Tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly goals").font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
            ForEach(model.goals) { goal in
                trayCard(goal)
            }
            Text(hint).font(Theme.ui(11)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 2) {
                Divider().padding(.bottom, 6)
                Text("Standing this week").font(Theme.ui(11)).foregroundStyle(Theme.muted)
                Text(model.weekStandingShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(Theme.headline(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text("avg of desk days · goal \(Int((model.weeklyStandingGoal * 100).rounded()))%")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 140)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var hint: String {
        guard let id = model.selectedGoalID,
              let goal = model.goals.first(where: { $0.id == id })
        else { return "Pick a goal, then an open slot. Click a planned goal to take it off." }
        return "Now click an open slot. Only slots that fit \(goal.minutes) min (plus the buffer) light up."
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
            return NSItemProvider(object: goal.id as NSString)
        }
    }

    // MARK: - Grid

    private var hours: DateInterval { model.weekHours }

    private var grid: some View {
        HStack(alignment: .top, spacing: 6) {
            hourGutter
            ForEach(model.weekDays, id: \.self) { day in
                dayColumn(day)
            }
        }
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 34)
            ZStack(alignment: .topTrailing) {
                Color.clear.frame(height: height(of: hours.duration))
                ForEach(hourMarks, id: \.self) { mark in
                    Text(mark.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted))))
                        .font(Theme.ui(10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .offset(y: y(mark) - 6)
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

    private func height(of duration: TimeInterval) -> CGFloat { CGFloat(duration / 60) * pointsPerMinute }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(sameDayMinutes(date)) * pointsPerMinute
    }

    /// Minutes from the top of the grid, using the clock rather than the date
    /// so every column can share one vertical scale.
    private func sameDayMinutes(_ date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.component(.hour, from: hours.start) * 60 + calendar.component(.minute, from: hours.start)
        let point = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return max(0, point - start)
    }

    private func dayColumn(_ day: Date) -> some View {
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
                Text(dayMeta(day)).font(Theme.ui(10)).foregroundStyle(Theme.muted)
            }
            .frame(height: 30, alignment: .topLeading)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(rest ? Theme.background : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isToday ? Theme.ink.opacity(0.35) : Theme.border, lineWidth: isToday ? 1.5 : 1)
                    )
                if rest {
                    RestHatch().stroke(Theme.border, lineWidth: 2).opacity(0.7)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    ForEach(blocks(on: day), id: \.id) { block in
                        WeekBlock(block: block, day: day, model: model, height: height(of: block.length))
                            .offset(y: y(block.start))
                            .padding(.horizontal, 2)
                    }
                }
            }
            .frame(height: height(of: hours.duration))
            .opacity(day < Calendar.current.startOfDay(for: model.now) ? 0.72 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func dayMeta(_ day: Date) -> String {
        if model.isRestDay(day) { return "Rest day" }
        guard let share = model.standingShare(on: day) else {
            return Calendar.current.isDateInToday(day) ? "today" : "no record"
        }
        let percent = Int((share * 100).rounded())
        return Calendar.current.isDateInToday(day) ? "\(percent)% so far" : "Stood \(percent)%"
    }

    /// Everything on a day, with the open stretches kept so they can be
    /// dropped into.
    private func blocks(on day: Date) -> [PlanBlock] {
        model.blocks(for: day)
    }

    private func spell(_ n: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven"]
        return words.indices.contains(n) ? words[n] : "\(n)"
    }
}

/// The diagonal hatch that marks a day Carl doesn't work.
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

/// One block in the Week grid: fixed things are drawn and named on hover,
/// goals can be taken off, and open space can be dropped into.
struct WeekBlock: View {
    let block: PlanBlock
    let day: Date
    @Bindable var model: AppModel
    let height: CGFloat
    @State private var isHovering = false

    var body: some View {
        content
            .frame(height: max(3, height), alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { isHovering = $0 }
            .help(tooltip)
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

    private var fixed: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isHovering ? Theme.ink.opacity(0.3) : .clear, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if height >= 18, block.isSuggestion {
                    Text(block.title)
                        .font(Theme.ui(10, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .lineLimit(1)
                }
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
        let done = model.goalSlot(block.intermissionID ?? "", on: day).map { model.goalIsDone($0) } ?? false
        return RoundedRectangle(cornerRadius: 3)
            .fill(colour.opacity(isHovering ? 0.36 : 0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(colour, lineWidth: isHovering ? 2 : 1.5)
            )
            .overlay(alignment: .topLeading) {
                if height >= 16 {
                    Text(done ? "\(block.title) ✓" : block.title)
                        .font(Theme.ui(10, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .lineLimit(1)
                }
            }
            .onTapGesture {
                guard let id = block.intermissionID else { return }
                model.removeGoal(id, on: day)
            }
            .contextMenu {
                if let id = block.intermissionID {
                    Button(done ? "Mark as not done" : "Mark as done") { model.toggleGoalDone(id, on: day) }
                    Button("Take it off this day") { model.removeGoal(id, on: day) }
                }
            }
    }

    private var openSpace: some View {
        let droppable = canDrop
        return RoundedRectangle(cornerRadius: 3)
            .fill(droppable
                  ? Theme.primary.opacity(isHovering ? 0.2 : 0.08)
                  : Theme.ink.opacity(isHovering ? 0.045 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        droppable ? Theme.primary.opacity(isHovering ? 1 : 0.45) : Theme.border.opacity(isHovering ? 1 : 0),
                        lineWidth: droppable && isHovering ? 1.5 : 1
                    )
            )
            .overlay(alignment: .topLeading) {
                if droppable, height >= 14, let goal = selectedGoal {
                    Text("+ \(goal.name) \(block.start.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.ui(10))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .lineLimit(1)
                } else if isHovering, height >= 14 {
                    Text("\(Int(block.length / 60)) min open")
                        .font(Theme.ui(10))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { place() }
            .onDrop(of: [.text], isTargeted: nil) { providers in
                guard droppable else { return false }
                place()
                _ = providers
                return true
            }
    }

    private var selectedGoal: IntermissionKind? {
        model.goals.first { $0.id == model.selectedGoalID }
    }

    /// A slot can take the selected goal when it fits, the day is one he
    /// works, it hasn't happened yet, and the goal isn't already on it.
    private var canDrop: Bool {
        guard let goal = selectedGoal, model.isWorkingDay(day) else { return false }
        guard block.end > model.now else { return false }
        guard model.goalSlot(goal.id, on: day) == nil else { return false }
        return block.length >= goal.length
    }

    private func place() {
        guard canDrop, let goal = selectedGoal else { return }
        model.placeGoal(goal.id, on: day, at: block.start)
    }

    private var tooltip: String {
        let times = "\(block.start.formatted(date: .omitted, time: .shortened))"
            + "–\(block.end.formatted(date: .omitted, time: .shortened))"
        if block.kind == .open {
            guard let goal = selectedGoal, canDrop else {
                return "\(times) · \(Int(block.length / 60)) min open"
            }
            return "Put \(goal.name.lowercased()) here"
        }
        if block.isGoal {
            let done = model.goalSlot(block.intermissionID ?? "", on: day).map { model.goalIsDone($0) } ?? false
            return "\(block.title) · \(times)" + (done ? " · done" : " · click to take it off")
        }
        return "\(block.title) · \(times)"
    }
}
