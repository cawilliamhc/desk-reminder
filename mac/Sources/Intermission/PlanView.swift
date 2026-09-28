import DeskCore
import SwiftUI

/// The morning face: what the day looks like, and where the breaks went.
struct PlanView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            agenda
            GoalTray(model: model)
        }
        .background(Theme.surface)
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Picker("", selection: $model.planDay) {
                        ForEach(AppModel.PlanDay.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    Spacer()
                    if model.isPlanCommitted {
                        Text("Planned").font(Theme.ui(11)).foregroundStyle(Theme.primary)
                    }
                }
                Text(greeting)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
                Text(summary)
                    .font(Theme.headline(24))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                Text(helper)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.muted)
                if let trouble = model.calendarTrouble {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 12))
                            .foregroundStyle(model.calendarColor)
                        Text(trouble.text).font(Theme.ui(12)).foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        Button(trouble.action) { model.fixCalendarTrouble() }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(model.calendarColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .padding(.top, 4)
                }
                if let rebalance = model.rebalance {
                    RebalanceBanner(rebalance: rebalance, model: model)
                        .padding(.top, 4)
                } else if let strip = model.rebalanceStrip {
                    RebalanceStrip(strip: strip, model: model)
                        .padding(.top, 4)
                }
                if model.scheduleMovedSincePlanning {
                    HStack(spacing: 8) {
                        Text("The schedule has changed since you planned this day. Your changes are kept; the rest has been laid out again.")
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(8)
                    .background(Theme.reading.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 8)

            PlanTimeline(model: model)
            AddOneOffRow(model: model)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let date = model.shownDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard model.planDay == .today else { return "Tomorrow · \(date)" }
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        // When the day was planned, which is the one fact about the plan
        // that isn't already on the timeline.
        let planned = model.planCommittedAt.map { " · \(clockTime($0))" } ?? ""
        return "\(part) · \(date)\(planned)"
    }

    /// The day in a sentence, built from what's actually on the plan.
    ///
    /// Two sentences: what's fixed, then what the planner put in. It names at
    /// most two breaks, because a list of five is something you skim rather
    /// than read.
    private var summary: String {
        if let rebalance = model.rebalance {
            return "\(rebalance.title.split(separator: ".").first.map(String.init) ?? rebalance.title). "
                + "\(rebalance.minutes) minutes opened up."
        }

        let sessions = model.shownPlan.filter { if case .session = $0.kind { return true } else { return false } }
        let virtual = model.shownPlan.filter { $0.kind == .session(virtual: true) }.count
        let placed = model.shownPlan.filter { $0.isSuggestion && !$0.isGoal }.sorted { $0.start < $1.start }
        let goals = model.shownPlan.filter(\.isGoal).sorted { $0.start < $1.start }

        if sessions.isEmpty && placed.isEmpty && goals.isEmpty && model.shownEvents.isEmpty {
            return model.planDay == .today ? "Nothing on the books today." : "Nothing on the books tomorrow."
        }

        var sentences: [String] = []

        // What's fixed.
        var fixed: [String] = []
        if !sessions.isEmpty {
            let count = sessions.count == 1 ? "One session" : "\(spell(sessions.count, capitalised: true)) sessions"
            fixed.append(virtual > 0 ? "\(count), \(spell(virtual)) virtual" : count)
        }
        for event in model.shownEvents.prefix(2) {
            let time = clockTime(event.start)
            fixed.append("a \(time) \(eventNoun(event.title))")
        }
        if model.shownEvents.count > 2 {
            fixed.append("\(spell(model.shownEvents.count - 2)) more from your calendar")
        }
        if !fixed.isEmpty { sentences.append(list(fixed) + ".") }

        // What the planner put in.
        if !placed.isEmpty {
            let named = placed.prefix(2).enumerated().map { index, block -> String in
                let name = index == 0 ? block.title : "a \(block.title.lowercased())"
                return "\(name) at \(clockTime(block.start))"
            }
            var sentence = list(named)
            if placed.count > 2 { sentence += " and \(placed.count - 2) more" }
            sentences.append(sentence + (placed.count == 1 ? " is in." : " are in."))
        }

        // A silent absence reads as a bug, so say what didn't fit.
        if model.planDay == .today, !model.unplacedToday.isEmpty {
            sentences.append("No room for \(list(model.unplacedToday.map { $0.name.lowercased() })) today.")
        }

        if goals.isEmpty {
            sentences.append("The rest stays open.")
        } else {
            let named = goals.map { "\($0.title.lowercased()) at \(clockTime($0.start))" }
            sentences.append("You added \(list(named)).")
        }
        return sentences.joined(separator: " ")
    }

    /// "Call with Dana" is a call. The first word is the one that says what
    /// a calendar event is; the rest is usually who it's with.
    private func eventNoun(_ title: String) -> String {
        let first = title.split(separator: " ").first.map(String.init) ?? "thing"
        return first.lowercased()
    }

    /// What the day is for. On a day he doesn't work the planner keeps its
    /// hands off, and saying so is the difference between an empty plan and
    /// a broken one.
    private var helper: String {
        guard model.isDeskDay(model.shownDate) else {
            let day = model.shownDate.formatted(.dateTime.weekday(.wide))
            return "\(day) isn't a desk day, so nothing is placed for you. "
                + "Add what you like, or put a goal in from the right."
        }
        return "Daily breaks are placed for you, \(spelledBuffer) apart. "
            + "Weekly goals wait on the right until you add one."
    }

    private var spelledBuffer: String {
        let minutes = model.settings.bufferMinutes
        return minutes == 0 ? "back to back" : "\(spell(minutes)) minutes"
    }

    private func spell(_ n: Int, capitalised: Bool = false) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                     "eleven", "twelve", "thirteen", "fourteen", "fifteen"]
        guard words.indices.contains(n) else { return "\(n)" }
        return capitalised ? words[n].prefix(1).uppercased() + words[n].dropFirst() : words[n]
    }

    private func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

}
