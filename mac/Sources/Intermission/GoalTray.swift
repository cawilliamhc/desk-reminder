import DeskCore
import SwiftUI

/// The right-hand column of Plan: the goals waiting for somewhere to go.
///
/// It replaced "Today's shape", a list of what was already on the plan. The
/// shape of the day is the timeline's job; this column is for the one thing
/// the planner deliberately won't do by itself.
struct GoalTray: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Weekly goals").font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Button("Week") { model.selectedView = .week }
                    .buttonStyle(.borderless)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.primary)
            }

            if model.goals.isEmpty {
                Text("No weekly goals yet. Settings has a place to add one.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.goals) { goal in
                card(goal)
            }

            HStack {
                Text("Standing this week").font(Theme.ui(12)).foregroundStyle(Theme.ink)
                Spacer()
                Text(standing).font(Theme.ui(12)).monospacedDigit().foregroundStyle(Theme.muted)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(model.planDay == .today ? "Yesterday" : "Today so far")
                    .font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(yesterday).font(Theme.ui(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Streak over goal").font(Theme.ui(12)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(model.streak) \(model.streak == 1 ? "day" : "days")")
                        .font(Theme.ui(12)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }

            Spacer()

            VStack(spacing: 6) {
                Button(model.planDay == .today ? "Start the day with this plan" : "Save tomorrow's plan") {
                    model.commitShownPlan()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut("s", modifiers: .command)

                Button(model.planDay == .today ? "Skip planning today" : "Leave tomorrow unplanned") {
                    model.skipPlanning()
                }
                .buttonStyle(.borderless)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(20)
        .frame(width: 272)
        .frame(maxHeight: .infinity)
        .background(Theme.background)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    /// "today" or "tomorrow" - the column follows the day the plan is showing.
    private var dayWord: String { model.planDay == .today ? "today" : "tomorrow" }

    private var standing: String {
        let share = model.weekStandingShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        return "\(share) · goal \(Int((model.weeklyStandingGoal * 100).rounded()))%"
    }

    private func card(_ goal: IntermissionKind) -> some View {
        let progress = model.goalProgress(goal.id)
        let onToday = model.goalSlot(goal.id, on: model.shownDate)
        let fit = onToday == nil ? model.goalFit(goal, on: model.shownDate) : nil
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.color(token: goal.colorToken))
                    .frame(width: 8, height: 8)
                Text(goal.name).font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer(minLength: 6)
                Text("\(goal.minutes) min · \(goal.perWeek)× a week")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
            }
            GoalPips(progress: progress, color: Theme.color(token: goal.colorToken))
            Text(status(goal, progress: progress, onToday: onToday, fit: fit))
                .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if onToday != nil {
                Button("Take it off \(dayWord)") { model.removeGoal(goal.id, on: model.shownDate) }
                    .buttonStyle(.borderless)
                    .font(Theme.ui(11))
                    .frame(maxWidth: .infinity)
            } else if let fit {
                Button("Add at \(clockTime(fit))") {
                    model.placeGoal(goal.id, on: model.shownDate, at: fit)
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            } else {
                Button("Pick another day") { model.selectedView = .week }
                    .buttonStyle(.borderless)
                    .font(Theme.ui(11))
                    .frame(maxWidth: .infinity)
            }
        }
        .cardStyle(padding: 12)
    }

    private func status(
        _ goal: IntermissionKind,
        progress: (done: Int, planned: Int, target: Int),
        onToday: GoalSlot?,
        fit: Date?
    ) -> String {
        let counts = "\(progress.done) done, \(progress.planned) planned."
        if let onToday {
            let done = model.goalIsDone(onToday)
            let block = model.shownPlan.first { $0.intermissionID == goal.id }
            guard let block else { return counts + " On \(dayWord), but the day has no room for it." }
            return counts + (done
                ? " Done at \(clockTime(block.start))."
                : " \(dayWord.capitalized) at \(clockTime(block.start)).")
        }
        if let fit { return counts + " Fits \(clockTime(fit)) \(dayWord)." }
        return counts + " No gap fits \(dayWord)."
    }

    private var yesterday: String {
        let record = model.planDay == .today ? model.week.dropLast().last : model.week.last
        guard let record, record.isRecorded else {
            return "No desk time recorded — the app wasn't watching."
        }
        return "Stood \(Int((record.standingShare * 100).rounded()))% of "
            + "\(hoursMinutes(record.atDesk)) at the desk, "
            + "\(record.notesStanding) of \(record.notesTotal) notes standing."
    }
}
