import DeskCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intermission")
                .font(Theme.headline(20))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 4)

            navItem(
                .plan, label: "Plan",
                meta: model.planCommittedAt.map { $0.formatted(date: .omitted, time: .shortened) }
            )
            navItem(.today, label: "Today", meta: "\(Int((model.today.standingShare * 100).rounded()))%")
            navItem(.settings, label: "Settings", meta: nil)

            Spacer()

            if let segment = model.breakToLabel {
                BreakPrompt(segment: segment, model: model)
            }
            NowCard(model: model)
            deskCard
            Button("I just finished a session") { model.finishedSessionNow() }
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(width: 184)
        .background(Theme.background)
    }

    private func navItem(_ view: AppModel.View, label: String, meta: String?) -> some View {
        let selected = model.selectedView == view
        return Button { model.selectedView = view } label: {
            HStack {
                Text(label).font(Theme.ui(13, weight: selected ? .medium : .regular))
                Spacer()
                if let meta { Text(meta).font(Theme.ui(12)).foregroundStyle(Theme.muted) }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(selected ? Theme.surface : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Theme.border : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(selected ? Theme.ink : Theme.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var deskCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Desk").font(Theme.ui(11)).foregroundStyle(Theme.muted)
            Text(model.height.map { String(format: "%.1f″", $0) } ?? "—")
                .font(Theme.headline(24))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(deskSubtitle)
                .font(Theme.ui(11))
                .foregroundStyle(model.adapterStatus == .adapterNotFound ? Theme.calendar : Theme.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var deskSubtitle: String {
        let state = switch (model.isStanding, model.heightIsAssumed) {
        case (nil, _): "No reading yet"
        case (true?, false): "Standing"
        case (false?, false): "Sitting"
        default: "Last known"      // assumed: the desk hasn't moved since launch
        }
        return "\(state) · \(model.adapterStatus.label)"
    }
}
