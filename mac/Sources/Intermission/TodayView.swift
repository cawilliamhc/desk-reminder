import Charts
import DeskCore
import SwiftUI

struct TodayView: View {
    @Bindable var model: AppModel
    @State private var hoveredDay: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                DayLanes(model: model)
                statCards
                HStack(alignment: .top, spacing: 12) {
                    weekChart
                    UpNextCard(model: model)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
        }
        .background(Theme.surface)
    }

    private var percent: Int { Int((model.today.standingShare * 100).rounded()) }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 26) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Standing · goal \(Int(model.settings.standingGoal * 100))% · \(Date().formatted(.dateTime.weekday(.wide).hour().minute()))")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
                Text("\(percent)%")
                    .font(Theme.headline(60))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text("\(hoursMinutes(model.today.standing)) up · \(hoursMinutes(model.today.sitting)) down · \(model.switchesToday) switches")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
            }
            Text(coachLine)
                .font(Theme.headline(20))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: 480, alignment: .leading)
            Spacer()
        }
    }

    private var coachLine: String {
        if model.today.atDesk == 0 {
            return "Nothing logged yet today — the desk speaks up when it moves."
        }
        if model.today.standingShare >= model.settings.standingGoal {
            return "Goal cleared. Anything from here is showing off."
        }
        return "Under the line so far. The next note is a good one to take standing."
    }

    private var statCards: some View {
        HStack(spacing: 10) {
            StatCard(
                label: "NOTES STANDING",
                value: "\(model.today.notesStanding) of \(model.today.notesTotal)",
                hint: "so far · \(model.weekNotes.standing) of \(model.weekNotes.total) this week"
            )
            StatCard(
                label: "OFF THE COMPUTER",
                value: hoursMinutes(model.offComputerToday),
                hint: breakdown
            )
            StatCard(
                label: "INTERMISSIONS",
                value: "\(model.intermissionsDone) of \(model.intermissionsPlanned)",
                hint: upNextHint
            )
            StatCard(
                label: "IN SESSION",
                value: hoursMinutes(model.inSessionToday),
                hint: "of \(hoursMinutes(model.inSessionPlannedToday)) · seated, kept separate"
            )
        }
    }

    /// The day the pointer is over, and what it was.
    private var hoveredDayText: String? {
        guard let hoveredDay, let record = model.week.first(where: { $0.day == hoveredDay }) else { return nil }
        let weekday = record.day.formatted(.dateTime.weekday(.abbreviated))
        guard record.isRecorded else {
            return record.isDeskDay ? "\(weekday) · no desk time recorded" : "\(weekday) · rest day"
        }
        return "\(weekday) · \(Int((record.standingShare * 100).rounded()))% · \(hoursMinutes(record.standing)) up of \(hoursMinutes(record.atDesk))"
    }

    private func opacity(for day: DayRecord) -> Double {
        let base = day.isDeskDay ? 1.0 : 0.35
        guard let hoveredDay else { return base }
        return day.day == hoveredDay ? base : base * 0.45
    }

    private var breakdown: String {
        let named = model.breaksToday
            .sorted { $0.value > $1.value }
            .map { "\($0.key.lowercased()) \(Int($0.value / 60))" }
        return named.isEmpty ? "nothing named yet" : named.joined(separator: " · ")
    }

    private var upNextHint: String {
        switch model.phase {
        case .upcoming(let kind, let at):
            "\(kind.name.lowercased()) at \(at.formatted(date: .omitted, time: .shortened))"
        case .running(let kind, _):
            "\(kind.name.lowercased()) running now"
        default:
            model.intermissionsPlanned == 0 ? "none planned" : "nothing right now"
        }
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("This week").font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text(hoveredDayText ?? "\(model.week.filter { $0.isDeskDay }.count) desk days")
                    .font(Theme.ui(11))
                    .monospacedDigit()
                    .foregroundStyle(hoveredDay == nil ? Theme.muted : Theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(hoveredDay == nil ? .clear : Theme.background)
                    .clipShape(Capsule())
            }
            Chart {
                // A day with nothing logged draws nothing: a zero bar reads
                // as "you never stood", and the truth is "nobody was
                // watching".
                ForEach(model.week.filter(\.isRecorded), id: \.day) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Standing", day.standingShare * 100)
                    )
                    .foregroundStyle(
                        day.standingShare >= model.settings.standingGoal ? Theme.standing : Theme.reading
                    )
                    .opacity(opacity(for: day))
                }
                RuleMark(y: .value("Goal", model.settings.standingGoal * 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Theme.muted)
            }
            // Hovering a bar says what that day was, beside the heading.
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                guard let plot = proxy.plotFrame else { return }
                                let x = point.x - geometry[plot].origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                hoveredDay = model.week.min {
                                    abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date))
                                }?.day
                            case .ended:
                                hoveredDay = nil
                            }
                        }
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 160)
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.ui(10, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.6)
            Text(value)
                .font(Theme.headline(32))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(hint)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }
}
