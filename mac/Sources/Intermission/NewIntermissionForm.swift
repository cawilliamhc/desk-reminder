import DeskCore
import SwiftUI

/// Adding a recurring intermission of Carl's own — a walk, water, eyes off
/// screens. The regular list is his, not a fixed set of four.
struct NewIntermissionForm: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var minutes = 20
    @State private var cadence = 0          // 0 daily, 1 twice daily, 2 weekly
    @State private var weekday: Weekday = .thursday
    @State private var preference = 0       // 0 afternoon, 1 late afternoon, 2 a time
    @State private var time = 12 * 60 + 30
    @State private var deskRule: IntermissionKind.DeskRule = .any
    @State private var colorToken = "chart-4"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("What is it?", text: $name).textFieldStyle(.roundedBorder)

            HStack {
                Text("Minutes").font(Theme.ui(12)).foregroundStyle(Theme.muted)
                Spacer()
                Stepper("\(minutes)", value: $minutes, in: 5...180, step: 5).monospacedDigit()
            }

            Picker("How often", selection: $cadence) {
                Text("Daily").tag(0)
                Text("Twice daily").tag(1)
                Text("Weekly").tag(2)
            }
            if cadence == 2 {
                Picker("On", selection: $weekday) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Text(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day.rawValue - 1])
                            .tag(day)
                    }
                }
            }

            Picker("Prefers", selection: $preference) {
                Text("Afternoon").tag(0)
                Text("Late afternoon").tag(1)
                Text("Around a time").tag(2)
            }
            if preference == 2 {
                HStack {
                    Text("At").font(Theme.ui(12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Stepper(String(format: "%d:%02d", time / 60, time % 60), value: $time, in: 6 * 60...20 * 60, step: 15)
                        .monospacedDigit()
                }
            }

            Picker("Desk", selection: $deskRule) {
                Text("Any").tag(IntermissionKind.DeskRule.any)
                Text("Up").tag(IntermissionKind.DeskRule.up)
                Text("Down").tag(IntermissionKind.DeskRule.down)
                Text("Leave it").tag(IntermissionKind.DeskRule.unchanged)
            }

            HStack(spacing: 6) {
                ForEach(Theme.palette, id: \.token) { entry in
                    Button { colorToken = entry.token } label: {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(entry.token == colorToken ? Theme.ink : Theme.border,
                                                     lineWidth: entry.token == colorToken ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(entry.name)
                }
            }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Add") { add() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func add() {
        let kind = IntermissionKind(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: name.trimmingCharacters(in: .whitespaces),
            minutes: minutes,
            cadence: cadence == 0 ? .daily : cadence == 1 ? .twiceDaily : .weekly(weekday),
            preference: preference == 0 ? .afternoon : preference == 1 ? .lateAfternoon : .around(time),
            deskRule: deskRule,
            rule: "Yours. Placed in a gap that fits it.",
            colorToken: colorToken
        )
        model.settings.intermissions.append(kind)
        isPresented = false
    }
}
