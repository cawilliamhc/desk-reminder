import DeskCore
import SwiftUI

/// "Back after 48 minutes — what was that?" Asked once on return, and only
/// for breaks long enough to be worth naming.
///
/// The sidebar is 184pt wide, so the answers are a column: side by side they
/// came out as "L…", "Re…", "St…" and a wrapped "Neithe r".
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

            VStack(spacing: 4) {
                ForEach(model.settings.intermissions.filter(\.enabled).prefix(3), id: \.id) { kind in
                    Button {
                        model.labelBreak(segment, as: kind.name)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.color(token: kind.colorToken))
                                .frame(width: 7, height: 7)
                            Text(kind.name).font(Theme.ui(11))
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Neither") { model.dismissBreakPrompt() }
                .buttonStyle(.plain)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.muted)
                .padding(.top, 1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.reading.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
