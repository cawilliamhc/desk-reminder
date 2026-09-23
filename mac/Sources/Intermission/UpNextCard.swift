import DeskCore
import SwiftUI

/// Bottom right of Today: the next intermission, and the three things worth
/// doing about it.
struct UpNextCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let next = model.upNext {
                Text("Up next · \(next.start.formatted(date: .omitted, time: .shortened))\(inText)")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                Text("\(next.title), \(Int(next.length / 60)) minutes")
                    .font(Theme.headline(20)).foregroundStyle(Theme.ink)
                Text(helper(for: next))
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                // Only a break is Carl's to start, swap or skip; a session is
                // a session.
                if let id = model.intermissionID(of: next) {
                    HStack(spacing: 8) {
                        Button("I'm off — \(next.title.lowercased())") {
                            model.startIntermission(id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Menu("Swap") {
                            ForEach(model.swapCandidates.filter { $0.id != id }, id: \.id) { kind in
                                Button(kind.name) { model.apply(.swapped(for: kind.id), to: id) }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 58)
                        Button(model.isOneOff(id) ? "Remove" : "Skip") { model.removeFromPlan(id) }
                            .buttonStyle(.borderless)
                    }
                    .font(Theme.ui(11))
                }
            } else {
                Text("Up next").font(Theme.ui(11)).foregroundStyle(Theme.muted)
                Text(model.plan.isEmpty ? "Nothing planned today" : "That's the day")
                    .font(Theme.headline(20)).foregroundStyle(Theme.ink)
                Text(model.plan.isEmpty
                     ? "A day off, or no sessions on the books."
                     : "Nothing else on the plan after this.")
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

    /// How long until it starts, so "up next" means something at a glance.
    private var inText: String {
        guard let next = model.upNext else { return "" }
        let minutes = Int(next.start.timeIntervalSince(model.now) / 60)
        return minutes <= 0 ? " · now" : minutes < 60 ? " · in \(minutes) min" : ""
    }

    private func helper(for block: PlanBlock) -> String {
        switch block.kind {
        case .session(let virtual):
            return virtual ? "Virtual — seated, desk down." : "In person."
        case .note:
            return "Ten minutes on your feet, while it's fresh."
        case .calendarEvent:
            return "From your calendar."
        case .open:
            return ""
        case .intermission:
            switch model.kind(of: block)?.deskRule ?? .any {
            case .down: return "The desk can come down for this one. Locking the Mac starts it."
            case .up: return "On your feet for this one."
            case .unchanged: return "Desk stays where it is."
            case .any: return "Locking the Mac starts it. Or tap when you're off."
            }
        }
    }
}
