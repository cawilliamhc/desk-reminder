import DeskCore
import SwiftUI

/// Settings, most-used first: the breaks and goals that decide what a day
/// looks like come before the desk and the calendars, because they're what
/// Carl actually opens this screen to change.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings").font(Theme.headline(24)).foregroundStyle(Theme.ink)
                    Text("Most-used first. Desk, calendars and the rest are further down.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 18)

                cardSection(
                    role: .dailyBreak,
                    title: "Daily breaks",
                    subtitle: "Placed for you on desk days, at least "
                        + "\(spelledMinutes(model.settings.bufferMinutes)) apart. "
                        + "The line under each name is what it's doing today.",
                    addLabel: "Add a break"
                )

                cardSection(
                    role: .weeklyGoal,
                    title: "Weekly goals",
                    subtitle: "A target for the week. Never placed for you. "
                        + "Put them on a day in Week, or into a gap on Plan.",
                    addLabel: "Add a goal"
                )

                section("Planning", "How the day gets laid out, and what happens when it changes.") {
                    row("Space between intermissions", "Breaks and goals never butt up against each other.") {
                        Picker("", selection: $model.settings.bufferMinutes) {
                            ForEach([0, 5, 10, 15], id: \.self) { Text($0 == 0 ? "None" : "\($0) minutes").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    row("When the calendar changes", "Offer options at the top of Plan. Nothing moves on its own.") {
                        Picker("", selection: $model.settings.onCalendarChange) {
                            Text("Ask me").tag(CalendarChange.ask)
                            Text("Leave the gap").tag(CalendarChange.leaveOpen)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    row("Offer the time back when you skip", "Skipping something shorter than this just leaves the gap.") {
                        Picker("", selection: $model.settings.rebalanceAfterSkipMinutes) {
                            Text("Always").tag(0)
                            ForEach([20, 30, 45], id: \.self) { Text("\($0) min or more").tag($0) }
                            Text("Never").tag(1000)
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    row("Be back before a session", "Intermissions end this long before the next hour starts.") {
                        Picker("", selection: $model.settings.settleMinutes) {
                            ForEach([0, 5, 10, 15], id: \.self) { Text($0 == 0 ? "No gap" : "\($0) minutes").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    row(
                        "Count idle as off the computer after",
                        "Screen lock counts immediately. Sleep and overnight never count as a break."
                    ) {
                        Picker("", selection: $model.settings.idleMinutes) {
                            ForEach([3, 6, 10], id: \.self) { Text("\($0) minutes").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    row("Ask what a break was", "On return from an unnamed break of 20 minutes or more.") {
                        Toggle("", isOn: $model.settings.askWhatABreakWas).labelsHidden().toggleStyle(.switch)
                    }
                    row("Morning plan", "Show the plan once on the first unlock of a desk day.") {
                        Toggle("", isOn: $model.settings.morningPlan).labelsHidden().toggleStyle(.switch)
                    }
                    row("Offer to plan tomorrow", "Ten minutes after your last session, with tomorrow in a sentence.") {
                        Toggle("", isOn: $model.settings.eveningPlan).labelsHidden().toggleStyle(.switch)
                    }
                }

                section("Desk", "What counts as standing. Reads from the dongle; never writes.") {
                    row("Standing height", "Counts as standing from \(fmt(model.settings.standingThreshold))″ and up.") {
                        HStack(spacing: 8) {
                            Picker("", selection: $model.settings.standingThreshold) {
                                ForEach([38.0, 40.0, 42.0, 44.0], id: \.self) { Text("\(fmt($0))″ and up").tag($0) }
                                if ![38.0, 40.0, 42.0, 44.0].contains(model.settings.standingThreshold) {
                                    Text("\(fmt(model.settings.standingThreshold))″ and up")
                                        .tag(model.settings.standingThreshold)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                            Button("Use current") { model.useCurrentHeightAsStanding() }
                                .disabled((model.height ?? 0) < 35)
                        }
                    }
                    row("Standing goal", "Share of at-desk time, sessions excluded.") {
                        HStack {
                            Slider(value: $model.settings.standingGoal, in: 0.1...0.8, step: 0.05)
                                .frame(width: 180)
                            Text("\(Int(model.settings.standingGoal * 100))%")
                                .font(Theme.ui(12)).monospacedDigit().foregroundStyle(Theme.muted)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    row("Weekly standing goal", "Average across desk days. Rest days don't count.") {
                        Picker("", selection: weeklyGoalBinding) {
                            Text("Same · \(Int(model.settings.standingGoal * 100))%").tag(-1.0)
                            ForEach([0.25, 0.30, 0.40], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    row("Listen to the desk", "Off, the port is closed and the height is whatever it last was.") {
                        Toggle("", isOn: $model.settings.listenToDesk).labelsHidden().toggleStyle(.switch)
                    }
                    row("Adapter", adapterDetail) { EmptyView() }
                }

                section("Notes", "The ten minutes after each session.") {
                    row("Remind me to raise the desk", "At session end, then once more after 5 minutes if still down.") {
                        Toggle("", isOn: $model.settings.remindForNotes).labelsHidden().toggleStyle(.switch)
                    }
                    row("Sound", "Play a sound with reminders.") {
                        Toggle("", isOn: $model.settings.sound).labelsHidden().toggleStyle(.switch)
                    }
                    row("End-of-day summary", "One notification after the last session.") {
                        Toggle("", isOn: $model.settings.endOfDaySummary).labelsHidden().toggleStyle(.switch)
                    }
                }

                section("Days", "Rest days never plan, nudge, or count against a streak.") {
                    row("Desk days", "Days this app pays attention to.") {
                        HStack(spacing: 4) {
                            ForEach(Weekday.weekOrder, id: \.self) { day in
                                dayChip(day)
                            }
                        }
                    }
                }

                section("Calendars", "Read-only. Events block the gaps intermissions would use.") {
                    row("Practice Studio", sessionsDetail) { EmptyView() }
                    if model.calendars.authorized {
                        ForEach(calendarsByAccount, id: \.account) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.account)
                                    .font(Theme.ui(11, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                ForEach(group.calendars) { calendar in
                                    HStack(spacing: 8) {
                                        Circle().fill(calendar.color).frame(width: 9, height: 9)
                                        Text(calendar.title).font(Theme.ui(13)).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Toggle("", isOn: Binding(
                                            get: { model.settings.calendarIDs.contains(calendar.id) },
                                            set: { on in
                                                if on { model.settings.calendarIDs.insert(calendar.id) }
                                                else { model.settings.calendarIDs.remove(calendar.id) }
                                            }
                                        ))
                                        .labelsHidden().toggleStyle(.switch)
                                    }
                                }
                            }
                            .padding(.bottom, 4)
                        }
                    } else {
                        row("Personal calendars", "Intermission hasn't been given access yet.") {
                            Button("Allow access") { Task { await model.calendars.requestAccess(); model.rebuildPlan() } }
                        }
                    }
                    row(
                        "Treat calendar events as",
                        "Video calls are at the computer; everything else counts as away. "
                            + "Any single event can be set on its own from the plan."
                    ) {
                        Picker("", selection: $model.settings.calendarEventMode) {
                            Text("Guess from title").tag(CalendarEventMode.guessFromTitle)
                            Text("On computer").tag(CalendarEventMode.onComputer)
                            Text("Off").tag(CalendarEventMode.offComputer)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }
                }

                section("Coach", "How the messages sound.") {
                    row("Tone", "Playful rotates its lines so they don't go stale.") {
                        Picker("", selection: $model.settings.tone) {
                            ForEach(Tone.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    row("Pause reminders", pauseDetail) {
                        HStack(spacing: 8) {
                            Button("For 1 hour") { model.pause(until: Date().addingTimeInterval(3600)) }
                            Button("For today") {
                                model.pause(until: Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)))
                            }
                            if model.settings.pausedUntil != nil {
                                Button("Resume") { model.resume() }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                section("App", "Where Intermission lives on this Mac.") {
                    row("Open at login", "Start quietly in the menu bar when you log in.") {
                        Toggle("", isOn: Binding(
                            get: { model.opensAtLogin },
                            set: { model.setOpensAtLogin($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    row("Notifications", "A Focus queues them silently unless Intermission is in its allowed apps.") {
                        Button("Open Focus settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                HStack {
                    Text("Intermission · data in ~/Library/Application Support/com.carlwilliamson.intermission")
                        .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .controlSize(.small)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .background(Theme.surface)
    }

    // MARK: - The break and goal cards

    private func cardSection(
        role: IntermissionKind.Role, title: String, subtitle: String, addLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.ui(15, weight: .medium)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(Theme.ui(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button(addLabel) { model.addIntermission(role: role) }
                    .controlSize(.small)
            }

            VStack(spacing: 10) {
                ForEach(rows(for: role), id: \.self) { row in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(row, id: \.self) { index in
                            card(at: index)
                        }
                        // A lone card on a row keeps its half of the grid
                        // rather than stretching across it.
                        if row.count == 1, !isEditing(row[0]) {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 26)
        .overlay(alignment: .bottom) { Divider() }
        .padding(.bottom, 22)
    }

    private func card(at index: Int) -> some View {
        IntermissionCard(
            kind: $model.settings.intermissions[index],
            model: model,
            isEditing: isEditing(index),
            onEdit: { model.editingIntermissionID = model.settings.intermissions[index].id },
            onDone: { model.editingIntermissionID = nil },
            onDelete: {
                let id = model.settings.intermissions[index].id
                model.editingIntermissionID = nil
                model.deleteIntermission(id)
            }
        )
    }

    private func isEditing(_ index: Int) -> Bool {
        guard model.settings.intermissions.indices.contains(index) else { return false }
        return model.editingIntermissionID == model.settings.intermissions[index].id
    }

    /// Two to a row, except the one being edited: its editor needs the width,
    /// so it takes the whole row.
    private func rows(for role: IntermissionKind.Role) -> [[Int]] {
        let indices = model.settings.intermissions.indices
            .filter { model.settings.intermissions[$0].role == role }
        var rows: [[Int]] = []
        var pending: [Int] = []
        for index in indices {
            if isEditing(index) {
                if !pending.isEmpty { rows.append(pending); pending = [] }
                rows.append([index])
                continue
            }
            pending.append(index)
            if pending.count == 2 { rows.append(pending); pending = [] }
        }
        if !pending.isEmpty { rows.append(pending) }
        return rows
    }

    // MARK: - Odds and ends

    private var weeklyGoalBinding: Binding<Double> {
        Binding(
            get: { model.settings.weeklyStandingGoal ?? -1 },
            set: { model.settings.weeklyStandingGoal = $0 < 0 ? nil : $0 }
        )
    }

    private func spelledMinutes(_ minutes: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                     "eleven", "twelve", "thirteen", "fourteen", "fifteen"]
        return words.indices.contains(minutes) ? "\(words[minutes]) minutes" : "\(minutes) minutes"
    }

    private func fmt(_ value: Double) -> String { String(format: "%.1f", value) }

    private var adapterDetail: String {
        var detail = model.adapterStatus.detail
        if let last = model.lastReport {
            detail += " · last report \(Int(Date().timeIntervalSince(last)))s ago"
        }
        return detail
    }

    /// Grouped by account, so two calendars called "Personal Calendar" are
    /// told apart by where they come from.
    private var calendarsByAccount: [(account: String, calendars: [CalendarInfo])] {
        Dictionary(grouping: model.calendars.available, by: \.account)
            .map { (account: $0.key, calendars: $0.value) }
            .sorted { $0.account < $1.account }
    }

    private var sessionsDetail: String {
        let sessions = model.plan.filter { if case .session = $0.kind { return true } else { return false } }
        let virtual = model.plan.filter { $0.kind == .session(virtual: true) }.count
        return "sessions.json · \(sessions.count) today, \(virtual) virtual · times and modality only"
    }

    private var pauseDetail: String {
        guard let until = model.settings.pausedUntil, until > Date() else { return "Reminders on." }
        return "Paused until \(until.formatted(date: .omitted, time: .shortened))."
    }

    private func dayChip(_ day: Weekday) -> some View {
        let on = model.settings.deskDays.contains(day)
        return Button {
            if on { model.settings.deskDays.remove(day) } else { model.settings.deskDays.insert(day) }
        } label: {
            Text(day.initial)
                .font(Theme.ui(12, weight: .medium))
                .frame(width: 26, height: 24)
                .background(on ? Theme.primary : Theme.surface)
                .foregroundStyle(on ? .white : Theme.muted)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? .clear : Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(day.shortName)
    }

    private func section<Content: View>(
        _ title: String, _ blurb: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(blurb).font(Theme.ui(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 180, alignment: .leading)

                VStack(alignment: .leading, spacing: 14) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 22)
            Divider().padding(.bottom, 22)
        }
    }

    private func row<Control: View>(
        _ label: String, _ helper: String, @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(helper).font(Theme.ui(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
