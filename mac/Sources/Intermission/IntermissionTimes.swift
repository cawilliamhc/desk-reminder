import DeskCore
import SwiftUI

/// When something is, and how long it runs — for one day.
///
/// Dragging an edge is fine when the plan is in front of you at a minute a
/// point; in Week a block is a stripe, and "the call ran to twenty past"
/// isn't something to mime. Both screens open this.
struct IntermissionTimes: View {
    let block: PlanBlock
    let day: Date
    @Bindable var model: AppModel
    @Binding var isPresented: Bool

    @State private var start = Date()
    @State private var minutes = 0

    /// Lengths worth offering, plus whatever it happens to be now.
    private var lengths: [Int] {
        let usual = [5, 10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90, 120]
        return usual.contains(minutes) ? usual : (usual + [minutes]).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title).font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Text("\(day.formatted(.dateTime.weekday(.wide).month().day())) · "
                     + "\(clockTime(start))–\(clockTime(start.addingTimeInterval(TimeInterval(minutes * 60))))")
                    .font(Theme.ui(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Starts").font(Theme.ui(12)).foregroundStyle(Theme.muted)
                    .frame(width: 54, alignment: .leading)
                DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .frame(width: 110)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Runs").font(Theme.ui(12)).foregroundStyle(Theme.muted)
                    .frame(width: 54, alignment: .leading)
                Picker("", selection: $minutes) {
                    ForEach(lengths, id: \.self) { Text("\($0) min").tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
            }

            if block.isGoal {
                Toggle("Count it as done", isOn: doneBinding)
                    .toggleStyle(.checkbox)
                    .font(Theme.ui(12))
            }

            Divider()

            HStack {
                Button("Save") {
                    model.setTimes(block, on: day, start: start, minutes: minutes)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return)

                Spacer()

                Button(removeLabel) {
                    if block.isGoal, let id = block.intermissionID {
                        model.removeGoal(id, on: day)
                    } else if let id = block.intermissionID {
                        model.clearEdits(for: .intermission(id), on: day)
                        if !model.isOneOff(id), model.isDeskDay(day) {
                            model.recordSkip(id, on: day)
                        }
                    }
                    isPresented = false
                }
                .buttonStyle(.borderless)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.calendar)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            start = block.start
            minutes = max(5, Int(block.length / 60))
        }
    }

    private var removeLabel: String {
        block.isGoal ? "Take it off this day" : (model.isOneOff(block.intermissionID ?? "") ? "Remove" : "Skip it")
    }

    private var doneBinding: Binding<Bool> {
        Binding(
            get: {
                guard let id = block.intermissionID, let slot = model.goalSlot(id, on: day) else { return false }
                return model.goalIsDone(slot)
            },
            set: { done in
                guard let id = block.intermissionID else { return }
                if model.goalSlot(id, on: day) == nil {
                    model.placeGoal(id, on: day, at: block.start)
                }
                model.markGoal(id, on: day, done: done)
            }
        )
    }
}
