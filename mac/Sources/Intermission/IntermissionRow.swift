import DeskCore
import SwiftUI

/// One intermission in Settings: what it is, how long, how often, and where
/// in the day it wants to sit.
struct IntermissionRow: View {
    @Binding var kind: IntermissionKind

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The colour swatch is also the colour picker.
            Menu {
                ForEach(Theme.palette, id: \.token) { entry in
                    Button {
                        kind.colorToken = entry.token
                    } label: {
                        Label {
                            Text(entry.name + (entry.token == kind.colorToken ? " ✓" : ""))
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(entry.color)
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(Theme.color(token: kind.colorToken))
                    .frame(width: 12, height: 12)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.name).font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(kind.rule).font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            detail("Length", "\(kind.minutes) min")
            detail("How often", cadence)
            detail("Prefers", preference)

            Toggle("", isOn: $kind.enabled).labelsHidden().toggleStyle(.switch)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(kind.enabled ? 1 : 0.55)
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
