import DeskCore
import SwiftUI

/// The day as four stacked lanes: what was planned, the calendar, on/off the
/// computer, and what the desk did. A vertical line marks now.
struct DayLanes: View {
    @Bindable var model: AppModel

    private let startHour = Planner.dayStartHour
    private let endHour = Planner.dayEndHour

    /// Whatever the pointer is over, so the lanes can name it and pick it out.
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("The day so far").font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text(hovered ?? " ")
                    .font(Theme.ui(11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(hovered == nil ? .clear : Theme.background)
                    .clipShape(Capsule())
                    .animation(.easeOut(duration: 0.1), value: hovered)
            }
            .padding(.bottom, 2)
            lane("Planned", height: 12, dot: true) { width in
                ForEach(model.plan) { block in
                    bar(from: block.start, to: block.end, width: width,
                        color: model.color(for: block.kind).opacity(block.kind == .open ? 0 : 0.55),
                        tip: "\(block.title) · \(span(block.start, block.end))")
                }
            }
            lane("Calendar", height: 14) { width in
                ForEach(model.events, id: \.start) { event in
                    bar(from: event.start, to: event.end, width: width, color: Theme.calendar,
                        tip: "\(event.title) · \(span(event.start, event.end))")
                }
            }
            lane("Computer", height: 30) { width in
                ForEach(model.computer.segments(on: model.now, now: model.now)) { segment in
                    bar(from: segment.start, to: segment.end ?? model.now, width: width,
                        color: computerColor(segment),
                        tip: computerTip(segment))
                }
            }
            lane("Desk", height: 18) { width in
                ForEach(deskBars, id: \.start) { item in
                    bar(from: item.start, to: item.end, width: width, color: item.color, tip: item.tip)
                }
            }
            axis
            legend
        }
    }

    // MARK: - Pieces

    private func lane<Content: View>(
        _ title: String, height: CGFloat, dot: Bool = false,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title).font(Theme.ui(11)).foregroundStyle(Theme.muted)
                .frame(width: 66, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(Theme.background)
                    content(geometry.size.width)
                    nowLine(width: geometry.size.width, dot: dot).allowsHitTesting(false)
                }
            }
            .frame(height: height)
        }
    }

    private func bar(from start: Date, to end: Date, width: CGFloat, color: Color, tip: String) -> some View {
        let x = offset(start, width: width)
        let w = max(1, offset(end, width: width) - x)
        return RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.ink, lineWidth: hovered == tip ? 1.5 : 0)
            )
            .brightness(hovered == tip ? -0.06 : 0)
            .frame(width: w)
            // Hover and tooltip belong to the BAR, before it's put in a
            // full-width frame to position it. Attached after, every bar's
            // invisible full-width frame sat over its neighbours and swallowed
            // their hovers - so only the last one in a lane ever answered.
            .contentShape(RoundedRectangle(cornerRadius: 2))
            .onHover { hovering in
                hovered = hovering ? tip : (hovered == tip ? nil : hovered)
            }
            .help(tip)
            .offset(x: x)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(w > 1)
    }

    /// Where we are in the day. Red, with a dot at its head on the top lane,
    /// the same shape the Practice Studio calendar uses. Hidden outside the
    /// day's own hours rather than pinned to an edge, where it would claim
    /// the morning starts at whatever time it is now.
    @ViewBuilder
    private func nowLine(width: CGFloat, dot: Bool) -> some View {
        if model.now >= date(startHour), model.now <= date(endHour) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Theme.now)
                    .frame(width: 1)
                if dot {
                    Circle()
                        .fill(Theme.now)
                        .frame(width: 7, height: 7)
                        .offset(y: -4)
                }
            }
            .offset(x: offset(model.now, width: width))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var axis: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 66)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    ForEach(Array(stride(from: startHour, through: endHour, by: 2)), id: \.self) { hour in
                        Text(label(hour))
                            .font(Theme.ui(10))
                            .foregroundStyle(Theme.muted)
                            .offset(x: offset(date(hour), width: geometry.size.width))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 12)
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 54)
            swatch(Theme.ink.opacity(0.22), "On the computer")
            swatch(Theme.lunch, "Lunch")
            swatch(Theme.reading, "Reading")
            swatch(Theme.standing, "Standing")
            swatch(Theme.sitting, "Sitting")
            swatch(Theme.session, "In session")
            Spacer()
        }
        .padding(.top, 2)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(Theme.ui(11)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Data

    private func span(_ start: Date, _ end: Date) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(start.formatted(time))–\(end.formatted(time))"
    }

    private func computerTip(_ segment: ComputerSegment) -> String {
        let when = span(segment.start, segment.end ?? model.now)
        let what = segment.isOnComputer ? "On the computer" : (segment.label ?? "Away")
        return "\(what) · \(when) · \(minutesOnly(segment.duration(now: model.now)))"
    }

    private func computerColor(_ segment: ComputerSegment) -> Color {
        if segment.isOnComputer { return Theme.ink.opacity(0.22) }
        guard let label = segment.label else { return .clear }   // away, unnamed: a gap
        // Named breaks take their intermission's colour, so the Computer lane
        // and the Planned lane agree about what lunch looks like.
        if label == ComputerLog.sessionLabel { return Theme.session }
        guard let kind = model.settings.intermissions.first(where: { $0.name == label }) else {
            return Theme.primary
        }
        return Theme.color(token: kind.colorToken)
    }

    /// The desk lane: the actual stretches the desk spent up and down, with
    /// session time drawn over the top since the desk is down for those.
    private var deskBars: [(start: Date, end: Date, color: Color, tip: String)] {
        var bars: [(Date, Date, Color, String)] = model.heights
            .segments(on: model.now)
            .map { stretch in
                let end = stretch.end ?? model.now
                let what = stretch.isStanding ? "Standing" : "Sitting"
                return (
                    stretch.start, end,
                    stretch.isStanding ? Theme.standing : Theme.sitting,
                    "\(what) · \(span(stretch.start, end)) · \(minutesOnly(end.timeIntervalSince(stretch.start)))"
                )
            }
        for block in model.plan {
            if case .session = block.kind, block.start < model.now {
                let end = min(block.end, model.now)
                bars.append((block.start, end, Theme.session, "In session · \(span(block.start, block.end))"))
            }
        }
        return bars.map { (start: $0.0, end: $0.1, color: $0.2, tip: $0.3) }
    }

    private func date(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: model.now) ?? model.now
    }

    private func label(_ hour: Int) -> String {
        hour == 12 ? "12 pm" : hour > 12 ? "\(hour - 12)" : "\(hour) am"
    }

    private func offset(_ date: Date, width: CGFloat) -> CGFloat {
        let span = TimeInterval((endHour - startHour) * 3600)
        let into = date.timeIntervalSince(self.date(startHour))
        return max(0, min(width, width * CGFloat(into / span)))
    }
}
