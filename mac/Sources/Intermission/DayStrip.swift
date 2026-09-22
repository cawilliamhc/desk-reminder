import DeskCore
import SwiftUI

/// The whole day as one thin bar, under "Today's shape": a glance at how
/// full it is and where the gaps fall, without reading the agenda.
struct DayStrip: View {
    @Bindable var model: AppModel
    let blocks: [PlanBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.surface)
                    ForEach(blocks) { block in
                        if block.kind != .open {
                            Rectangle()
                                .fill(model.color(for: block.kind))
                                .frame(width: width(of: block, in: geometry.size.width))
                                .offset(x: x(block.start, in: geometry.size.width))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 10)

            HStack {
                Text(label(window.start))
                Spacer()
                Text(label(window.start.addingTimeInterval(window.duration / 2)))
                Spacer()
                Text(label(window.end))
            }
            .font(Theme.ui(10))
            .foregroundStyle(Theme.muted)
        }
    }

    private var window: DateInterval {
        guard let first = blocks.first?.start, let last = blocks.last?.end, last > first else {
            return DateInterval(start: model.now, duration: 3600)
        }
        return DateInterval(start: first, end: last)
    }

    private func x(_ date: Date, in width: CGFloat) -> CGFloat {
        width * CGFloat(date.timeIntervalSince(window.start) / window.duration)
    }

    private func width(of block: PlanBlock, in width: CGFloat) -> CGFloat {
        max(1, width * CGFloat(block.length / window.duration))
    }

    private func label(_ date: Date) -> String {
        date.formatted(.dateTime.hour())
    }
}
