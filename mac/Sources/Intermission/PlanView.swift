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
                Text(greeting)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
                Text(summary)
                    .font(Theme.headline(24))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                Text("Intermissions are placed in the gaps that fit them. Start, swap or skip any of them.")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(model.plan) { block in
                        PlanRow(block: block, model: model)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return "\(part) · \(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))"
    }

    /// The day in a sentence, built from what's actually on the plan.
    private var summary: String {
        let sessions = model.plan.filter { if case .session = $0.kind { return true } else { return false } }
        let virtual = model.plan.filter { $0.kind == .session(virtual: true) }.count
        let notes = model.plan.filter { $0.kind == .note }.count
        let suggestions = model.plan.filter(\.isSuggestion)

        if sessions.isEmpty && suggestions.isEmpty {
            return "Nothing on the books today."
        }
        var parts: [String] = []
        if !sessions.isEmpty {
            let count = sessions.count == 1 ? "One session" : "\(spell(sessions.count)) sessions"
            parts.append(virtual > 0 ? "\(count), \(spell(virtual)) virtual" : count)
        }
        if !model.events.isEmpty {
            parts.append(model.events.count == 1
                ? "one thing from your calendar"
                : "\(spell(model.events.count)) things from your calendar")
        }
        var sentence = parts.joined(separator: ", ") + "."
        if !suggestions.isEmpty {
            let placed = suggestions.map { "\($0.title.lowercased()) at \($0.start.formatted(date: .omitted, time: .shortened))" }
            sentence += " Room for " + list(placed) + "."
        }
        if notes > 0 {
            sentence += notes == 1 ? " One note standing." : " \(spell(notes)) notes standing."
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
            Text("Today's shape").font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)

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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Yesterday").font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(yesterday).font(Theme.ui(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Streak over goal").font(Theme.ui(12)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(model.streak) days").font(Theme.ui(12)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }

            Spacer()

            Button("Start the day with this plan") { model.selectedView = .today }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 272)
        .frame(maxHeight: .infinity)
        .background(Theme.background)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    private var shapeRows: [(label: String, value: String, color: Color)] {
        var rows: [(String, String, Color)] = []
        let sessions = model.plan.filter { if case .session = $0.kind { return true } else { return false } }
        if !sessions.isEmpty {
            rows.append(("In session", hoursMinutes(sessions.reduce(0) { $0 + $1.length }), Theme.session))
        }
        let notes = model.plan.filter { $0.kind == .note }
        if !notes.isEmpty {
            rows.append(("Notes, standing", "\(notes.count) × \(Planner.noteMinutes) min", Theme.standing))
        }
        if !model.events.isEmpty {
            rows.append(("Calendar", "\(model.events.count) · \(minutesOnly(model.events.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }))", Theme.calendar))
        }
        for block in model.plan where block.isSuggestion {
            rows.append((
                block.title,
                "\(block.start.formatted(date: .omitted, time: .shortened)) · \(minutesOnly(block.length))",
                PlanRow.color(for: block.kind)
            ))
        }
        let open = model.plan.filter { $0.kind == .open }.reduce(0) { $0 + $1.length }
        if open > 0 { rows.append(("Open", hoursMinutes(open), Theme.border)) }
        return rows.map { (label: $0.0, value: $0.1, color: $0.2) }
    }

    private var yesterday: String {
        let record = model.week.dropLast().last
        guard let record, record.atDesk > 0 else { return "No desk time logged." }
        return "Stood \(Int((record.standingShare * 100).rounded()))% of \(hoursMinutes(record.atDesk)) at the desk, \(record.notesStanding) of \(record.notesTotal) notes standing."
    }
}

struct PlanRow: View {
    let block: PlanBlock
    @Bindable var model: AppModel

    static func color(for kind: PlanBlock.Kind) -> Color {
        switch kind {
        case .session: Theme.session
        case .note: Theme.standing
        case .calendarEvent: Theme.calendar
        case .open: Theme.border
        case .intermission(let id):
            switch id {
            case "lunch": Theme.lunch
            case "reading": Theme.reading
            default: Theme.primary
            }
        }
    }

    private var isOpen: Bool { block.kind == .open }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(block.start.formatted(date: .omitted, time: .shortened))
                .font(Theme.ui(11)).monospacedDigit().foregroundStyle(Theme.muted)
                .frame(width: 58, alignment: .trailing)
                .padding(.trailing, 10)
                .padding(.top, 6)

            RoundedRectangle(cornerRadius: 1)
                .fill(Self.color(for: block.kind))
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
                    Button("Skip") { model.skipIntermission(id) }
                        .buttonStyle(.borderless)
                        .font(Theme.ui(11))
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(isOpen ? .clear : Self.color(for: block.kind).opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .opacity(isOpen ? 0.7 : 1)
        .frame(minHeight: max(block.length / 60 * 0.8, 32))
    }
}
