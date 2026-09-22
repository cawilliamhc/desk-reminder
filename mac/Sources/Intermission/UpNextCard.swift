import DeskCore
import SwiftUI

/// Bottom right of Today: the next intermission, and the three things worth
/// doing about it.
struct UpNextCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let next = model.upNext {
                Text("Up next · \(next.at.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                Text("\(next.kind.name), \(next.kind.minutes) minutes")
                    .font(Theme.headline(20)).foregroundStyle(Theme.ink)
                Text(helper(next.kind))
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("I'm off — \(next.kind.name.lowercased())") {
                        model.startIntermission(next.kind.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Menu("Swap") {
                        ForEach(model.swapCandidates.filter { $0.id != next.kind.id }, id: \.id) { kind in
                            Button(kind.name) { model.apply(.swapped(for: kind.id), to: next.kind.id) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 58)
                    Button("Skip") { model.apply(.skipped, to: next.kind.id) }
                        .buttonStyle(.borderless)
                }
                .font(Theme.ui(11))
            } else {
                Text("Up next").font(Theme.ui(11)).foregroundStyle(Theme.muted)
                Text(model.plan.isEmpty ? "Nothing planned today" : "Nothing left today")
                    .font(Theme.headline(20)).foregroundStyle(Theme.ink)
                Text(model.plan.isEmpty
                     ? "A day off, or no sessions on the books."
                     : "Every intermission is done, skipped or behind you.")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func helper(_ kind: IntermissionKind) -> String {
        switch kind.deskRule {
        case .down: "The desk can come down for this one. Locking the Mac starts it."
        case .up: "On your feet for this one."
        case .unchanged: "Desk stays where it is."
        case .any: "Locking the Mac starts it. Or tap when you're off."
        }
    }
}
