import DeskCore
import SwiftUI

/// One break or goal in Settings: what it is, what it's doing today, and -
/// open - every field that decides both.
///
/// The row this replaced could only change the colour and the switch. Every
/// other field existed, but only on the form for *adding* one, so a lunch
/// that wanted to be forty minutes had to be deleted and made again.
struct IntermissionCard: View {
    @Binding var kind: IntermissionKind
    @Bindable var model: AppModel
    var isEditing: Bool
    var onEdit: () -> Void
    var onDone: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(model.todayStatus(for: kind))
                .font(Theme.ui(12))
                .monospacedDigit()
                .foregroundStyle(isPlacedToday ? Theme.ink : Theme.muted)
            if kind.isGoal {
                GoalPips(progress: model.goalProgress(kind.id), color: Theme.color(token: kind.colorToken))
                    .padding(.leading, 22)
            }
            chips
            if isEditing {
                Divider()
                editor
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isEditing ? Theme.ink.opacity(0.35) : Theme.border, lineWidth: isEditing ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(kind.enabled ? 1 : 0.55)
    }

    private var isPlacedToday: Bool {
        model.plan.contains { $0.intermissionID == kind.id }
    }

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.color(token: kind.colorToken))
                .frame(width: 12, height: 12)
            Text(kind.name).font(Theme.ui(15, weight: .medium)).foregroundStyle(Theme.ink)
            if let family = Theme.family(for: kind.colorToken) {
                Text(family.name).font(Theme.ui(11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Toggle("", isOn: $kind.enabled).labelsHidden().toggleStyle(.switch)
        }
    }

    // MARK: - Chips

    private var chips: some View {
        HStack(spacing: 5) {
            ForEach(chipLabels, id: \.self) { label in
                Button(action: onEdit) {
                    Text(label)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.background)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            Button(isEditing ? "Done" : "Edit", action: isEditing ? onDone : onEdit)
                .buttonStyle(.borderless)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.primary)
        }
        .padding(.leading, 22)
    }

    private var chipLabels: [String] {
        var labels = [lengthChip]
        labels.append(cadenceChip)
        labels.append(whereChip)
        labels.append(deskChip)
        return labels
    }

    private var lengthChip: String {
        guard let least = kind.minimumMinutes, least < kind.minutes else { return "\(kind.minutes) min" }
        return "\(kind.minutes) min, or \(least)"
    }

    private var cadenceChip: String {
        guard !kind.isGoal else { return "\(kind.perWeek)× a week" }
        switch kind.cadence {
        case .daily: return "Daily"
        case .twiceDaily: return "Up to 2× daily"
        case .days(let days):
            return days.isEmpty
                ? "No days"
                : days.sorted { $0.weekIndex < $1.weekIndex }.map(\.shortName).joined(separator: ", ")
        }
    }

    private var whereChip: String {
        switch kind.preference {
        case .around(let minutes):
            "From \(String(format: "%d:%02d", minutes / 60 % 12 == 0 ? 12 : minutes / 60 % 12, minutes % 60))"
        case .morning: "Mornings"
        case .afternoon: "Afternoons"
        case .lateAfternoon: "Late afternoons"
        case .beforeSeated: "Before virtual"
        case .afterSitting(let minutes): "After \(minutes) min sitting"
        }
    }

    private var deskChip: String {
        switch kind.deskRule {
        case .up: "Desk up"
        case .down: "Desk down"
        case .unchanged: "Desk stays"
        case .any: "Desk: any"
        }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 18) {
                field("Name") {
                    TextField("", text: $kind.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                field("Kind") {
                    Picker("", selection: roleBinding) {
                        Text("Daily break").tag(IntermissionKind.Role.dailyBreak)
                        Text("Weekly goal").tag(IntermissionKind.Role.weeklyGoal)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
                Spacer()
            }

            colors

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("When").font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
                    if kind.isGoal {
                        field("Per week") {
                            Picker("", selection: $kind.perWeek) {
                                ForEach(1...5, id: \.self) { count in
                                    Text(count == 1 ? "Once" : "\(count)×").tag(count)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 110)
                        }
                    } else {
                        field("How often") {
                            Picker("", selection: cadenceChoice) {
                                Text("Daily").tag(0)
                                Text("Twice a day").tag(1)
                                Text("Some days").tag(2)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 260)
                        }
                        if case .days = kind.cadence { dayChips }
                    }
                    field("Goes") {
                        Picker("", selection: preferenceChoice) {
                            Text("Around a time").tag(0)
                            Text("Morning").tag(1)
                            Text("Afternoon").tag(2)
                            Text("Late afternoon").tag(3)
                            Text("Before a seated session").tag(4)
                            Text("After sitting a while").tag(5)
                        }
                        .labelsHidden()
                        .frame(width: 210)
                    }
                    if case .around = kind.preference { timePicker }
                    if case .afterSitting = kind.preference { sittingPicker }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Length and desk").font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
                    field("Length") {
                        HStack(spacing: 6) {
                            Picker("", selection: $kind.minutes) {
                                ForEach(lengthChoices, id: \.self) { Text("\($0) min").tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 92)
                            Text("or").font(Theme.ui(11)).foregroundStyle(Theme.muted)
                            Picker("", selection: shortestBinding) {
                                ForEach(lengthChoices, id: \.self) { Text("\($0) min").tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 92)
                        }
                    }
                    Text("The second is the shortest worth doing on a tight day.")
                        .font(Theme.ui(10)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    field("Desk") {
                        Picker("", selection: $kind.deskRule) {
                            Text("Up").tag(IntermissionKind.DeskRule.up)
                            Text("Down").tag(IntermissionKind.DeskRule.down)
                            Text("Leave it").tag(IntermissionKind.DeskRule.unchanged)
                            Text("Any").tag(IntermissionKind.DeskRule.any)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 230)
                    }
                }
                .frame(width: 250, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.rule).font(Theme.ui(12)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.todayStatus(for: kind)).font(Theme.ui(11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Spacer()
                if kind.builtIn != nil {
                    Button("Reset to default") { model.resetIntermission(kind.id) }
                        .buttonStyle(.borderless)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.muted)
                } else {
                    Button("Delete", action: onDelete)
                        .buttonStyle(.borderless)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.calendar)
                }
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.ui(11)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private var lengthChoices: [Int] { [5, 10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90] }

    private var colors: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Colour").font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text("Green, terracotta and blue stay reserved for standing, calendar and sessions.")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                ForEach(Theme.families) { family in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(family.name).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
                        Text(family.hint).font(Theme.ui(10)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            ForEach(family.tokens, id: \.self) { token in
                                Button { kind.colorToken = token } label: {
                                    Circle()
                                        .fill(Theme.color(token: token))
                                        .frame(width: 18, height: 18)
                                        .overlay(Circle().stroke(Theme.ink.opacity(0.12), lineWidth: 1))
                                        .overlay {
                                            if token == kind.colorToken {
                                                Circle().stroke(Theme.surface, lineWidth: 2)
                                                    .padding(1)
                                                    .background(
                                                        Circle().stroke(Theme.ink, lineWidth: 1.5).padding(-1)
                                                    )
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .help(Theme.name(token: token))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(family.tokens.contains(kind.colorToken) ? Theme.surface : Theme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                family.tokens.contains(kind.colorToken) ? Theme.ink.opacity(0.3) : .clear,
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var dayChips: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.weekOrder.prefix(5), id: \.self) { day in
                let on = selectedDays.contains(day)
                Button {
                    var days = selectedDays
                    if on { days.remove(day) } else { days.insert(day) }
                    kind.cadence = .days(days)
                } label: {
                    Text(day.initial)
                        .font(Theme.ui(11, weight: .medium))
                        .frame(width: 32, height: 26)
                        .background(on ? Theme.primary : Theme.surface)
                        .foregroundStyle(on ? Theme.surface : Theme.ink)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(on ? .clear : Theme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedDays: Set<Weekday> {
        if case .days(let days) = kind.cadence { return days }
        return []
    }

    private var timePicker: some View {
        field("At") {
            Picker("", selection: timeBinding) {
                ForEach(Array(stride(from: 10 * 60, through: 15 * 60, by: 30)), id: \.self) { minutes in
                    Text(String(
                        format: "%d:%02d",
                        minutes / 60 % 12 == 0 ? 12 : minutes / 60 % 12,
                        minutes % 60
                    )).tag(minutes)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
    }

    private var sittingPicker: some View {
        field("After") {
            Picker("", selection: sittingBinding) {
                ForEach([60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
            }
            .labelsHidden()
            .frame(width: 110)
        }
    }

    // MARK: - Bindings that keep the model honest

    private var roleBinding: Binding<IntermissionKind.Role> {
        Binding(
            get: { kind.role },
            set: { role in
                kind.role = role
                // A goal has no cadence and a break has no weekly count, so
                // switching sort gives it something sensible rather than
                // leaving the other field's leftovers showing.
                if role == .weeklyGoal, case .twiceDaily = kind.cadence { kind.cadence = .daily }
            }
        )
    }

    private var cadenceChoice: Binding<Int> {
        Binding(
            get: {
                switch kind.cadence {
                case .daily: 0
                case .twiceDaily: 1
                case .days: 2
                }
            },
            set: { choice in
                switch choice {
                case 0: kind.cadence = .daily
                case 1: kind.cadence = .twiceDaily
                default: kind.cadence = .days(selectedDays.isEmpty ? [.monday, .wednesday, .friday] : selectedDays)
                }
            }
        )
    }

    private var preferenceChoice: Binding<Int> {
        Binding(
            get: {
                switch kind.preference {
                case .around: 0
                case .morning: 1
                case .afternoon: 2
                case .lateAfternoon: 3
                case .beforeSeated: 4
                case .afterSitting: 5
                }
            },
            set: { choice in
                switch choice {
                case 0: kind.preference = .around(12 * 60)
                case 1: kind.preference = .morning
                case 2: kind.preference = .afternoon
                case 3: kind.preference = .lateAfternoon
                case 4: kind.preference = .beforeSeated
                default: kind.preference = .afterSitting(minutes: 90)
                }
            }
        )
    }

    private var timeBinding: Binding<Int> {
        Binding(
            get: { if case .around(let minutes) = kind.preference { minutes } else { 12 * 60 } },
            set: { kind.preference = .around($0) }
        )
    }

    private var sittingBinding: Binding<Int> {
        Binding(
            get: { if case .afterSitting(let minutes) = kind.preference { minutes } else { 90 } },
            set: { kind.preference = .afterSitting(minutes: $0) }
        )
    }

    /// The shortest can't be longer than the length: a 30-minute lunch with a
    /// 50-minute floor is a rule that can never be met.
    private var shortestBinding: Binding<Int> {
        Binding(
            get: { min(kind.minimumMinutes ?? kind.minutes, kind.minutes) },
            set: { kind.minimumMinutes = min($0, kind.minutes) }
        )
    }
}

/// One bar per slot in a goal's week: done, planned, or still to come.
struct GoalPips: View {
    var progress: (done: Int, planned: Int, target: Int)
    var color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(progress.target, 1), id: \.self) { index in
                Capsule()
                    .fill(fill(index))
                    .frame(height: 4)
            }
        }
    }

    private func fill(_ index: Int) -> Color {
        if index < progress.done { return color }
        if index < progress.done + progress.planned { return color.opacity(0.35) }
        return Theme.border
    }
}
