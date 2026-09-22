import DeskCore
import SwiftUI

/// One intermission in Settings: what it is, how long, how often, and where
/// in the day it wants to sit.
struct IntermissionRow: View {
    @Binding var kind: IntermissionKind
    /// Only Carl's own are removable; the four defaults can be switched off.
    var onDelete: (() -> Void)?
    @State private var isPickingColor = false
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The colour swatch is also the colour picker. A popover rather
            // than a menu: AppKit draws menu images as flat black templates,
            // which made every swatch in the list look the same.
            Button { isPickingColor = true } label: {
                Circle()
                    .fill(Theme.color(token: kind.colorToken))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .popover(isPresented: $isPickingColor, arrowEdge: .bottom) {
                colorPicker
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.name).font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(kind.rule).font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            detail("Length", kind.minimumMinutes.map { "\(kind.minutes) min · \($0) least" } ?? "\(kind.minutes) min")
            detail("How often", cadence)
            detail("Prefers", preference)

            Toggle("", isOn: $kind.enabled).labelsHidden().toggleStyle(.switch)

            if kind.id.hasPrefix("custom-") {
                Button {
                    onDelete?()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(isHovering ? Theme.calendar : Theme.muted)
                }
                .buttonStyle(.plain)
                .help("Remove \(kind.name)")
            }
        }
        .onHover { isHovering = $0 }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(kind.enabled ? 1 : 0.55)
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(kind.name) colour").font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 4), spacing: 6) {
                ForEach(Theme.palette, id: \.token) { entry in
                    Button {
                        kind.colorToken = entry.token
                        isPickingColor = false
                    } label: {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().stroke(
                                    entry.token == kind.colorToken ? Theme.ink : Theme.border,
                                    lineWidth: entry.token == kind.colorToken ? 2 : 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(entry.name)
                }
            }
        }
        .padding(12)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(Theme.ui(10)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.ui(12)).foregroundStyle(Theme.ink)
        }
    }

    private var cadence: String {
        switch kind.cadence {
        case .daily: "Daily"
        case .twiceDaily: "2× daily"
        case .weekly(let day): "Weekly · \(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][day.rawValue - 1])"
        }
    }

    private var preference: String {
        switch kind.preference {
        case .around(let minutes): String(format: "%d:%02d", minutes / 60, minutes % 60)
        case .afternoon: "Afternoon"
        case .lateAfternoon: "Late afternoon"
        case .beforeSeated: "Before virtual"
        }
    }
}
