import DeskCore
import SwiftUI

/// The one thing to be doing now, how long is left, and what the desk should
/// be doing about it.
///
/// Shortcuts: ⌘⏎ is always the main action, ⌘⌫ skips.
struct NowCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(Theme.ui(11, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text(until).font(Theme.ui(10)).foregroundStyle(Theme.ink.opacity(0.7))
            }

            if let remaining = model.phase.remaining(at: model.now) {
                Text(countdown(remaining))
                    .font(Theme.headline(32))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }

            Text(aim).font(Theme.ui(12)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let progress {
                // A bar under the countdown, so the time left has a shape.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.ink.opacity(0.15))
                        Capsule().fill(Theme.ink).frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 3)
                .padding(.vertical, 2)
            }

            if let desk = deskLine {
                HStack(spacing: 6) {
                    Image(systemName: desk.symbol).font(.system(size: 11, weight: .medium))
                    Text(desk.text).font(Theme.ui(11)).foregroundStyle(Theme.ink)
                }
            }

            if !actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(actions, id: \.title) { action in
                        Button(action.title) { action.run() }
                            .font(Theme.ui(11, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .keyboardShortcut(action.shortcut, modifiers: .command)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - What the phase says

    private var label: String {
        switch model.phase {
        case .session(_, let virtual): virtual ? "In session · virtual" : "In session"
        case .note: "Note — standing"
        case .upcoming(let kind, _): "Up next · \(kind.name)"
        case .running(let kind, _): kind.name
        case .open: "Open"
        }
    }

    private var until: String {
        switch model.phase {
        case .session(let until, _), .note(let until), .running(_, let until):
            "until \(until.formatted(date: .omitted, time: .shortened))"
        case .upcoming(_, let at):
            "at \(at.formatted(date: .omitted, time: .shortened))"
        case .open:
            ""
        }
    }

    private var aim: String {
        switch model.phase {
        case .session(_, let virtual):
            virtual ? "Quiet until the note window. No nudges." : "Nothing until this one's done."
        case .note:
            "Write the note on your feet."
        case .upcoming(let kind, _):
            "\(kind.name), \(kind.minutes) minutes. Off the computer."
        case .running(let kind, _):
            "\(kind.name) is running. Unlocking the Mac ends it."
        case .open:
            model.plan.isEmpty ? "No plan today." : "Nothing scheduled right now."
        }
    }

    private var deskLine: (symbol: String, text: String)? {
        guard let rule = model.phase.deskRule else { return nil }
        let height = model.height.map { String(format: "%.1f″", $0) } ?? "—"
        // An assumed height is still a height: the desk hasn't moved since
        // the app started, so 44.5" means the desk is up. Telling him to
        // raise a desk that is already up is the one thing this must not do.
        let unconfirmed = model.heightIsAssumed ? " (last known)" : ""
        switch rule {
        case .up:
            return model.isStanding == true
                ? ("arrow.up", "Desk up · \(height)\(unconfirmed)")
                : ("arrow.up", "Raise the desk — \(height) now")
        case .down:
            return model.isStanding == false
                ? ("arrow.down", "Desk down · \(height)\(unconfirmed)")
                : ("arrow.down", "Bring the desk down for this one")
        case .unchanged:
            return ("equal", "Desk stays where it is")
        case .any:
            return nil
        }
    }

    /// How far through the current block we are, 0 to 1.
    private var progress: Double? {
        guard let block = model.currentBlock, block.length > 0 else { return nil }
        if case .open = block.kind { return nil }
        return min(1, max(0, model.now.timeIntervalSince(block.start) / block.length))
    }

    private struct Action {
        let title: String
        let shortcut: KeyEquivalent
        let run: () -> Void
    }

    private var actions: [Action] {
        switch model.phase {
        case .upcoming(let kind, _):
            [
                Action(title: "Start now", shortcut: .return) { model.startIntermission(kind.id) },
                Action(title: "Skip", shortcut: .delete) { model.skipIntermission(kind.id) },
            ]
        case .running(let kind, _):
            [Action(title: "I'm back", shortcut: .return) { model.finishIntermission(kind.id) }]
        case .note:
            [Action(title: "Done", shortcut: .return) { model.noteDone() }]
        case .session:
            // The phase moves on by itself when the published hour ends;
            // this is for the hour that ended early.
            [Action(title: "Skip ahead", shortcut: .return) { model.endSessionEarly() }]
        case .open:
            []
        }
    }

    private var tint: Color {
        switch model.phase {
        case .note: Theme.standing.opacity(0.22)
        case .session: Theme.session.opacity(0.3)
        case .upcoming(let kind, _), .running(let kind, _):
            model.color(for: .intermission(id: kind.id)).opacity(0.28)
        case .open: Theme.background
        }
    }

    private func countdown(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
