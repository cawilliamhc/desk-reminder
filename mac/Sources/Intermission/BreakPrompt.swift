import DeskCore
import SwiftUI

/// "Back after 51 minutes — what was that?" Asked once, on return, and only
/// for breaks long enough to be worth naming.
struct BreakPrompt: View {
    let segment: ComputerSegment
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Back after \(minutesOnly(segment.duration(now: segment.end ?? model.now)))")
                .font(Theme.ui(12, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("What was that?")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 4) {
                ForEach(model.settings.intermissions.prefix(3), id: \.id) { kind in
                    Button(kind.name) { model.labelBreak(segment, as: kind.name) }
                        .font(Theme.ui(11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button("Neither") { model.dismissBreakPrompt() }
                    .font(Theme.ui(11))
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.reading.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
