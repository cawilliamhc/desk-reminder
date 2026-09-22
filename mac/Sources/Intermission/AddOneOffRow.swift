import DeskCore
import SwiftUI

/// "Add something" on the plan: a walk, an errand, a longer lunch — a one-off
/// that isn't in the regular list and only belongs to this day.
struct AddOneOffRow: View {
    @Bindable var model: AppModel
    @State private var isAdding = false
    @State private var name = ""
    @State private var minutes = 20
    @State private var start = Date()

    var body: some View {
        HStack {
            Button("Add something") {
                start = suggestedStart
                isAdding = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $isAdding) { form }
            Text("A walk, an errand, a longer lunch — just for this day.")
                .font(Theme.ui(11)).foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(.top, 6)
        .padding(.leading, 71)
    }

    /// The start of the day's longest open stretch: the likeliest place for it.
    private var suggestedStart: Date {
        model.shownPlan
            .filter { $0.kind == .open }
            .max { $0.length < $1.length }?
            .start ?? model.shownDate
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("What is it?", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Minutes").font(Theme.ui(12)).foregroundStyle(Theme.muted)
                Spacer()
                Stepper("\(minutes)", value: $minutes, in: 5...180, step: 5)
                    .monospacedDigit()
            }
            HStack {
                Text("Starts").font(Theme.ui(12)).foregroundStyle(Theme.muted)
                Spacer()
                DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
            }
            HStack {
                Button("Cancel") { isAdding = false }
                Spacer()
                Button("Add") {
                    model.addOneOff(name: name, minutes: minutes, at: start)
                    name = ""
                    isAdding = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
