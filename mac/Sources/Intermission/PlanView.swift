import DeskCore
import SwiftUI

/// The morning face: what the day looks like, and where the breaks went.
struct PlanView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            agenda
            shape
        }
        .background(Theme.surface)
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Picker("", selection: $model.planDay) {
                        ForEach(AppModel.PlanDay.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    Spacer()
                    if model.isPlanCommitted {
                        Text("Planned").font(Theme.ui(11)).foregroundStyle(Theme.primary)
                    }
                }
                Text(greeting)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
                Text(summary)
                    .font(Theme.headline(24))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                Text("Intermissions are placed in the gaps that fit them. Drag one to move it, drag its bottom edge to make it longer or shorter, or swap and skip.")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
                if model.scheduleMovedSincePlanning {
                    HStack(spacing: 8) {
                        Text("The schedule has changed since you planned this day. Your changes are kept; the rest has been laid out again.")
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(8)
                    .background(Theme.reading.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(model.shownPlan) { block in
                        PlanRow(block: block, model: model)
                    }
                    AddOneOffRow(model: model)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let date = model.shownDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard model.planDay == .today else { return "Tomorrow · \(date)" }
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return "\(part) · \(date)"
    }

    /// The day in a sentence, built from what's actually on the plan.
    private var summary: String {
        let sessions = model.shownPlan.filter { if case .session = $0.kind { return true } else { return false } }
        let virtual = model.shownPlan.filter { $0.kind == .session(virtual: true) }.count
        let notes = model.shownPlan.filter { $0.kind == .note }.count
        let suggestions = model.shownPlan.filter(\.isSuggestion)

        if sessions.isEmpty && suggestions.isEmpty {
            return model.planDay == .today ? "Nothing on the books today." : "Nothing on the books tomorrow."
        }
        var parts: [String] = []
        if !sessions.isEmpty {
            let count = sessions.count == 1 ? "One session" : "\(spell(sessions.count)) sessions"
            parts.append(virtual > 0 ? "\(count), \(spell(virtual)) virtual" : count)
        }
        if !model.shownEvents.isEmpty {
            parts.append(model.shownEvents.count == 1
                ? "one thing from your calendar"
                : "\(spell(model.shownEvents.count)) things from your calendar")
        }
        var sentence = parts.joined(separator: ", ") + "."
        if !suggestions.isEmpty {
            let placed = suggestions.map { "\($0.title.lowercased()) at \($0.start.formatted(date: .omitted, time: .shortened))" }
            sentence += " Room for " + list(placed) + "."
        }
        if notes > 0 {
            sentence += notes == 1 ? " One note standing." : " \(spell(notes)) notes standing."
        }
        // A silent absence reads as a bug, so say what didn't fit.
        if model.planDay == .today, !model.unplacedToday.isEmpty {
            let names = list(model.unplacedToday.map { $0.name.lowercased() })
            sentence += " No room for \(names) today."
        }
        return sentence
    }

    private func spell(_ n: Int) -> String {
        ["zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
            .indices.contains(n) ? ["zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"][n] : "\(n)"
    }

    private func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    private var shape: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.planDay == .today ? "Today's shape" : "Tomorrow's shape")
                .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)

            VStack(spacing: 6) {
                ForEach(shapeRows, id: \.label) { row in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(row.color).frame(width: 8, height: 8)
                        Text(row.label).font(Theme.ui(12)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(row.value).font(Theme.ui(12)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                }
            }

            DayStrip(model: model, blocks: model.shownPlan)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(model.planDay == .today ? "Yesterday" : "Today so far")
                    .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(yesterday).font(Theme.ui(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Streak over goal").font(Theme.ui(12)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(model.streak) days").font(Theme.ui(12)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }

            Spacer()

            VStack(spacing: 6) {
                Button(model.planDay == .today ? "Start the day with this plan" : "Save tomorrow's plan") {
                    model.commitShownPlan()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut("s", modifiers: .command)

                Button(model.planDay == .today ? "Skip planning today" : "Leave tomorrow unplanned") {
                    model.skipPlanning()
                }
                .buttonStyle(.borderless)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(20)
        .frame(width: 272)
        .frame(maxHeight: .infinity)
        .background(Theme.background)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    private var shapeRows: [(label: String, value: String, color: Color)] {
        var rows: [(String, String, Color)] = []
        let sessions = model.shownPlan.filter { if case .session = $0.kind { return true } else { return false } }
        if !sessions.isEmpty {
            rows.append(("In session", hoursMinutes(sessions.reduce(0) { $0 + $1.length }), Theme.session))
        }
        let notes = model.shownPlan.filter { $0.kind == .note }
        if !notes.isEmpty {
            rows.append(("Notes, standing", "\(notes.count) × \(Planner.noteMinutes) min", Theme.standing))
        }
        if !model.shownEvents.isEmpty {
            rows.append(("Calendar", "\(model.shownEvents.count) · \(minutesOnly(model.shownEvents.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }))", Theme.calendar))
        }
        for block in model.shownPlan where block.isSuggestion {
            rows.append((
                block.title,
                "\(block.start.formatted(date: .omitted, time: .shortened)) · \(minutesOnly(block.length))",
                model.color(for: block.kind)
            ))
        }
        let open = model.shownPlan.filter { $0.kind == .open }.reduce(0) { $0 + $1.length }
        if open > 0 { rows.append(("Open", hoursMinutes(open), Theme.border)) }
        return rows.map { (label: $0.0, value: $0.1, color: $0.2) }
    }

    private var yesterday: String {
        let record = model.planDay == .today ? model.week.dropLast().last : model.week.last
        guard let record, record.atDesk > 0 else { return "No desk time logged." }
        return "Stood \(Int((record.standingShare * 100).rounded()))% of \(hoursMinutes(record.atDesk)) at the desk, \(record.notesStanding) of \(record.notesTotal) notes standing."
    }
}

struct PlanRow: View {
    let block: PlanBlock
    @Bindable var model: AppModel
    @State private var dragOffset: CGFloat = 0
    @State private var dragMinutes = 0
    @State private var resizeMinutes = 0

    private var isOpen: Bool { block.kind == .open }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(block.start.formatted(date: .omitted, time: .shortened))
                .font(Theme.ui(11)).monospacedDigit().foregroundStyle(Theme.muted)
                .frame(width: 58, alignment: .trailing)
                .padding(.trailing, 10)
                .padding(.top, 6)

            RoundedRectangle(cornerRadius: 1)
                .fill(model.color(for: block.kind))
                .frame(width: 3)
                .padding(.trailing, 10)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(block.title).font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                        if let badge = block.badge {
                            Text(badge)
                                .font(Theme.ui(10, weight: .medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.surface)
                                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                                .clipShape(Capsule())
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    if let subline = block.subline {
                        Text(subline).font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Text("\(block.start.formatted(date: .omitted, time: .shortened)) – \(block.end.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.ui(11)).monospacedDigit().foregroundStyle(Theme.muted)
                if case .intermission(let id) = block.kind {
                    Menu("Swap") {
                        ForEach(model.swapCandidates.filter { $0.id != id }, id: \.id) { kind in
                            Button(kind.name) { model.apply(.swapped(for: kind.id), to: id) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .font(Theme.ui(11))
                    .frame(width: 58)

                    Button("Skip") { model.apply(.skipped, to: id) }
                        .buttonStyle(.borderless)
                        .font(Theme.ui(11))

                    if block.badge == "Yours" || block.isShortened {
                        Button("Undo") { model.undoEdits(for: id) }
                            .buttonStyle(.borderless)
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(isOpen ? .clear : model.color(for: block.kind).opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) { if isDraggable { resizeHandle } }
            .overlay(alignment: .topTrailing) { if dragMinutes != 0 || resizeMinutes != 0 { liveLabel } }
            .offset(y: isDraggable ? dragOffset : 0)
            .gesture(isDraggable ? moveGesture : nil)
        }
        .opacity(isOpen ? 0.7 : 1)
        .frame(minHeight: max((block.length / 60 + Double(resizeMinutes)) * Self.pointsPerMinute, 32))
        .animation(.interactiveSpring, value: dragOffset)
    }

    // MARK: - Dragging

    /// The agenda's scale: a minute is this many points, so a drag can be
    /// read back as a time rather than a guess.
    static let pointsPerMinute: CGFloat = 0.8
    /// Times land on five-minute marks; nobody plans a break at 12:37.
    static let snapMinutes = 5

    private var isDraggable: Bool {
        if case .intermission = block.kind { return true }
        return false
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
            .frame(height: 8)
            .contentShape(Rectangle())
            .onHover { NSCursor.resizeUpDown.set(); if !$0 { NSCursor.arrow.set() } }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { resizeMinutes = snapped($0.translation.height) }
                    .onEnded { value in
                        let change = snapped(value.translation.height)
                        resizeMinutes = 0
                        guard change != 0, let id = intermissionID else { return }
                        let minutes = max(5, Int(block.length / 60) + change)
                        model.apply(.resized(minutes: minutes), to: id)
                    }
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(model.color(for: block.kind).opacity(0.5))
                    .frame(width: 28, height: 3)
                    .padding(.bottom, 1)
            }
    }

    /// What the drag currently means, shown on the block while it happens.
    private var liveLabel: some View {
        Text(labelText)
            .font(Theme.ui(10, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.ink)
            .foregroundStyle(Theme.surface)
            .clipShape(Capsule())
            .offset(x: -6, y: -8)
    }

    private var labelText: String {
        if resizeMinutes != 0 {
            let minutes = max(5, Int(block.length / 60) + resizeMinutes)
            return "\(minutes) min"
        }
        let moved = block.start.addingTimeInterval(TimeInterval(dragMinutes * 60))
        return moved.formatted(date: .omitted, time: .shortened)
    }

    private func snapped(_ translation: CGFloat) -> Int {
        let minutes = Int((translation / Self.pointsPerMinute).rounded())
        return (minutes / Self.snapMinutes) * Self.snapMinutes
    }
}
