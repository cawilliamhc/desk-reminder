import DeskCore
import SwiftUI

/// The day drawn to scale: an hour is an hour tall, so a gap looks like the
/// time it is. The list it replaced gave every block the same weight, which
/// made a ten-minute note and a fifty-minute lunch read the same.
struct PlanTimeline: View {
    @Bindable var model: AppModel

    /// A minute of the day, in points. An eight-hour day is about 700pt,
    /// which scrolls once rather than endlessly.
    static let pointsPerMinute: CGFloat = 1.4
    static let snapMinutes = 5
    private let gutter: CGFloat = 52

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(model.shownPlan) { block in
                    Group {
                        if block.kind == .open {
                            OpenSpace(block: block, model: model)
                        } else {
                            TimelineBlock(block: block, model: model)
                        }
                    }
                    .frame(height: height(of: block))
                    .padding(.leading, gutter)
                    .offset(y: y(block.start))
                }
                if model.planDay == .today, let y = nowY {
                    nowLine.offset(y: y)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: totalHeight, alignment: .top)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Geometry

    private var window: DateInterval {
        guard let first = model.shownPlan.first?.start, let last = model.shownPlan.last?.end, last > first
        else { return DateInterval(start: model.shownDate, duration: 3600) }
        return DateInterval(start: first, end: last)
    }

    private var totalHeight: CGFloat { CGFloat(window.duration / 60) * Self.pointsPerMinute }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(window.start) / 60) * Self.pointsPerMinute
    }

    private func height(of block: PlanBlock) -> CGFloat {
        max(14, CGFloat(block.length / 60) * Self.pointsPerMinute)
    }

    private var nowY: CGFloat? {
        guard model.now >= window.start, model.now <= window.end else { return nil }
        return y(model.now)
    }

    /// The hours, labelled down the left, so a block's place means something
    /// without reading its times.
    private var hourLines: some View {
        ForEach(hours, id: \.self) { hour in
            HStack(spacing: 8) {
                Text(hour.formatted(.dateTime.hour()))
                    .font(Theme.ui(10))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .frame(width: gutter - 8, alignment: .trailing)
                Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
            }
            .offset(y: y(hour) - 5)
        }
    }

    private var hours: [Date] {
        var hours: [Date] = []
        var cursor = Calendar.current.date(
            bySetting: .minute, value: 0,
            of: Calendar.current.date(byAdding: .hour, value: 1, to: window.start) ?? window.start
        ) ?? window.start
        while cursor < window.end {
            hours.append(cursor)
            cursor = Calendar.current.date(byAdding: .hour, value: 1, to: cursor) ?? window.end
        }
        return hours
    }

    private var nowLine: some View {
        HStack(spacing: 0) {
            Circle().fill(Theme.now).frame(width: 7, height: 7)
            Rectangle().fill(Theme.now).frame(height: 1)
        }
        .padding(.leading, gutter - 3)
    }
}

/// An empty stretch, and the offer to put something in it.
struct OpenSpace: View {
    let block: PlanBlock
    @Bindable var model: AppModel
    @State private var isHovering = false

    var body: some View {
        let candidates = model.candidates(for: block)
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.background.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .overlay {
                if block.length >= 15 * 60 {
                    HStack(spacing: 6) {
                        Text("\(minutesOnly(block.length)) open")
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.muted)
                        if isHovering, !candidates.isEmpty {
                            Menu("Fill it") {
                                ForEach(candidates, id: \.id) { kind in
                                    Button("\(kind.name) · \(Int(min(kind.length, block.length) / 60)) min") {
                                        model.fill(block, with: kind)
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 60)
                            .font(Theme.ui(11))
                        }
                    }
                }
            }
            .onHover { isHovering = $0 }
    }
}

/// A block on the timeline. Intermissions can be dragged to move and their
/// bottom edge dragged to stretch or shorten; everything else is fixed.
struct TimelineBlock: View {
    let block: PlanBlock
    @Bindable var model: AppModel
    @State private var dragOffset: CGFloat = 0
    @State private var dragMinutes = 0
    @State private var resizeMinutes = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(model.color(for: block.kind))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(block.title).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
                    if let badge = block.badge, block.length >= 20 * 60 {
                        Text(badge)
                            .font(Theme.ui(9, weight: .medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.surface)
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                            .clipShape(Capsule())
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(times).font(Theme.ui(10)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                if let subline = block.subline, block.length >= 25 * 60 {
                    Text(subline).font(Theme.ui(10)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                if isDraggable, block.length >= 30 * 60, let id = intermissionID {
                    HStack(spacing: 8) {
                        Menu("Swap") {
                            ForEach(model.swapCandidates.filter { $0.id != id }, id: \.id) { kind in
                                Button(kind.name) { model.apply(.swapped(for: kind.id), to: id) }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 52)
                        Button(model.isOneOff(id) ? "Remove" : "Skip") { model.removeFromPlan(id) }
                            .buttonStyle(.borderless)
                        if block.badge == "Yours", !model.isOneOff(id) {
                            Button("Undo") { model.undoEdits(for: id) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }
                    .font(Theme.ui(10))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.color(for: block.kind).opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) { if isDraggable { resizeHandle } }
        .overlay(alignment: .topTrailing) { if dragMinutes != 0 || resizeMinutes != 0 { liveLabel } }
        .offset(y: isDraggable ? dragOffset : 0)
        .gesture(isDraggable ? moveGesture : nil)
        .animation(.interactiveSpring, value: dragOffset)
        // Short blocks have no room for buttons, so every block's actions are
        // here too - a ten-minute stretch was impossible to remove otherwise.
        .contextMenu {
            if let id = intermissionID {
                Button(model.isOneOff(id) ? "Remove" : "Skip today") { model.removeFromPlan(id) }
                Menu("Swap for") {
                    ForEach(model.swapCandidates.filter { $0.id != id }, id: \.id) { kind in
                        Button(kind.name) { model.apply(.swapped(for: kind.id), to: id) }
                    }
                }
                Divider()
                Button("Back to the suggestion") { model.undoEdits(for: id) }
            }
        }
    }

    private var times: String {
        "\(block.start.formatted(date: .omitted, time: .shortened)) – \(block.end.formatted(date: .omitted, time: .shortened))"
    }

    private var isDraggable: Bool { intermissionID != nil }

    private var intermissionID: String? {
        if case .intermission(let id) = block.kind { return id }
        return nil
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                dragOffset = value.translation.height
                dragMinutes = snapped(value.translation.height)
            }
            .onEnded { value in
                let minutes = snapped(value.translation.height)
                dragOffset = 0
                dragMinutes = 0
                guard minutes != 0, let id = intermissionID else { return }
                model.apply(.moved(to: block.start.addingTimeInterval(TimeInterval(minutes * 60))), to: id)
            }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 7)
            .contentShape(Rectangle())
            .onHover { $0 ? NSCursor.resizeUpDown.set() : NSCursor.arrow.set() }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { resizeMinutes = snapped($0.translation.height) }
                    .onEnded { value in
                        let change = snapped(value.translation.height)
                        resizeMinutes = 0
                        guard change != 0, let id = intermissionID else { return }
                        model.apply(.resized(minutes: max(5, Int(block.length / 60) + change)), to: id)
                    }
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(model.color(for: block.kind).opacity(0.6))
                    .frame(width: 26, height: 3)
            }
    }

    private var liveLabel: some View {
        Text(labelText)
            .font(Theme.ui(10, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.ink)
            .foregroundStyle(Theme.surface)
            .clipShape(Capsule())
            .offset(x: -6, y: -8)
    }

    private var labelText: String {
        if resizeMinutes != 0 {
            return "\(max(5, Int(block.length / 60) + resizeMinutes)) min"
        }
        return block.start
            .addingTimeInterval(TimeInterval(dragMinutes * 60))
            .formatted(date: .omitted, time: .shortened)
    }

    private func snapped(_ translation: CGFloat) -> Int {
        let minutes = Int((translation / PlanTimeline.pointsPerMinute).rounded())
        return (minutes / PlanTimeline.snapMinutes) * PlanTimeline.snapMinutes
    }
}
