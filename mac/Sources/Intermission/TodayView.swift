import Charts
import DeskCore
import SwiftUI

struct TodayView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statCards
                weekChart
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
                Text("\(hoursMinutes(model.today.standing)) up · \(hoursMinutes(model.today.sitting)) down")
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
                hint: "so far today"
            )
            StatCard(
                label: "STANDING",
                value: hoursMinutes(model.today.standing),
                hint: "of \(hoursMinutes(model.today.atDesk)) at the desk"
            )
            StatCard(
                label: "STREAK",
                value: "\(model.streak)",
                hint: model.streak == 1 ? "day over goal" : "days over goal"
            )
            StatCard(
                label: "DESK",
                value: model.height.map { String(format: "%.1f″", $0) } ?? "—",
                hint: model.heightIsAssumed ? "last known" : model.adapterStatus.label
            )
        }
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("This week").font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(model.week.filter { $0.isDeskDay }.count) desk days")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
            }
            Chart {
                ForEach(model.week, id: \.day) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Standing", day.standingShare * 100)
                    )
                    .foregroundStyle(
                        day.standingShare >= model.settings.standingGoal ? Theme.standing : Theme.reading
                    )
                    .opacity(day.isDeskDay ? 1 : 0.35)
                }
                RuleMark(y: .value("Goal", model.settings.standingGoal * 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Theme.muted)
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
