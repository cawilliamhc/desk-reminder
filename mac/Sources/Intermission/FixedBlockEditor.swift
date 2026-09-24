import DeskCore
import SwiftUI

/// The quiet Edit on a session or a calendar event.
///
/// Practice Studio stays the source: nothing here is written back, and none
/// of it outlives the day. It exists for the gap between what was published
/// and what happened - the client who didn't come, the hour that finished at
/// twenty to, the "call" in the calendar that turns out to be a walk.
struct FixedBlockEditor: View {
    let block: PlanBlock
    @Bindable var model: AppModel
    @Binding var isPresented: Bool

    private var target: PlanEdit.Target? { block.target }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(isSession ? "Session" : block.title) · \(times)")
                    .font(Theme.ui(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(isSession
                     ? "From Practice Studio, which stays the source. This changes \(dayWord)'s plan only."
                     : "Personal calendar, read-only. This changes \(dayWord)'s plan only.")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isSession {
                labelled("Ran") {
                    Picker("", selection: modeBinding) {
                        Text("In person").tag(false)
                        Text("Virtual").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                labelled("Ended") {
                    Picker("", selection: endedEarlyBinding) {
                        Text("On time").tag(0)
                        Text("10 early").tag(10)
                        Text("20 early").tag(20)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                labelled("Note after") {
                    HStack(spacing: 8) {
                        Toggle("", isOn: noteBinding).labelsHidden().toggleStyle(.switch)
                        Text("Standing, \(Planner.noteMinutes) min")
                            .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                        Spacer()
                    }
                }
            } else {
                labelled("You'll be") {
                    Picker("", selection: presenceBinding) {
                        Text("Off the computer").tag(false)
                        Text("On it").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            Divider()

            HStack {
                Button("Didn't happen") {
                    guard let target else { return }
                    model.apply(.didNotHappen, to: target)
                    isPresented = false
                }
                .controlSize(.small)
                Spacer()
                Text("Today only").font(Theme.ui(11)).foregroundStyle(Theme.muted)
            }

            if let target, !model.edits(for: target).isEmpty {
                Button("Put it back the way it was") {
                    model.clearEdits(for: target)
                    isPresented = false
                }
                .buttonStyle(.borderless)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var isSession: Bool {
        if case .session = block.kind { return true }
        return false
    }

    private var dayWord: String { model.planDay == .today ? "today" : "tomorrow" }

    private var times: String {
        "\(clockTime(block.start))–\(clockTime(block.end))"
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.muted)
                .frame(width: 76, alignment: .leading)
            content()
        }
    }

    // MARK: - Bindings, each one an edit on today's plan

    private var modeBinding: Binding<Bool> {
        Binding(
            get: {
                if case .session(let virtual) = block.kind { return virtual }
                return false
            },
            set: { virtual in
                guard let target else { return }
                model.apply(.mode(virtual ? "virtual" : "in-person"), to: target)
            }
        )
    }

    private var endedEarlyBinding: Binding<Int> {
        Binding(
            get: {
                guard let target else { return 0 }
                for edit in model.edits(for: target) {
                    if case .endedEarly(let minutes) = edit.change { return minutes }
                }
                return 0
            },
            set: { minutes in
                guard let target else { return }
                if minutes == 0 {
                    // Back to the published end: drop the edit rather than
                    // writing "ended early by nothing".
                    let kept = model.edits(for: target).filter {
                        if case .endedEarly = $0.change { return false }
                        return true
                    }
                    model.clearEdits(for: target)
                    for edit in kept { model.apply(edit.change, to: target) }
                } else {
                    model.apply(.endedEarly(minutes: minutes), to: target)
                }
            }
        )
    }

    private var noteBinding: Binding<Bool> {
        Binding(
            get: {
                guard let target else { return true }
                return !model.edits(for: target).contains { $0.change == .skipNote }
            },
            set: { wantsNote in
                guard let target else { return }
                if wantsNote {
                    let kept = model.edits(for: target).filter { $0.change != .skipNote }
                    model.clearEdits(for: target)
                    for edit in kept { model.apply(edit.change, to: target) }
                } else {
                    model.apply(.skipNote, to: target)
                }
            }
        )
    }

    private var presenceBinding: Binding<Bool> {
        Binding(
            get: {
                guard let target else { return false }
                for edit in model.edits(for: target) {
                    if case .presence(let onComputer) = edit.change { return onComputer }
                }
                return block.subline?.contains("on the computer") ?? false
            },
            set: { onComputer in
                guard let target else { return }
                model.apply(.presence(onComputer: onComputer), to: target)
            }
        )
    }
}
