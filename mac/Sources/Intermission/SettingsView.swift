import DeskCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").font(Theme.headline(24)).foregroundStyle(Theme.ink)
                    .padding(.bottom, 18)

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
                    row("Adapter", adapterDetail) { EmptyView() }
                }

                section("Notes", "The minutes after each session.") {
                    row("Remind me to raise the desk", "At session end, then once more after 5 minutes if still down.") {
                        Toggle("", isOn: $model.settings.remindForNotes).labelsHidden().toggleStyle(.switch)
                    }
                    row("Skip virtual sessions", "No nudge after a seated session; note windows still count.") {
                        Toggle("", isOn: $model.settings.skipVirtual).labelsHidden().toggleStyle(.switch)
                    }
                    row("Sound", "Play a sound with reminders.") {
                        Toggle("", isOn: $model.settings.sound).labelsHidden().toggleStyle(.switch)
                    }
                }

                section("Days", "Rest days never nudge, and never count against a streak.") {
                    row("Desk days", "Days this app pays attention to.") {
                        HStack(spacing: 4) {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                dayChip(day)
                            }
                        }
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

                Text("Intermission · data in ~/Library/Application Support/com.carlwilliamson.intermission")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .background(Theme.surface)
    }

    private func fmt(_ value: Double) -> String { String(format: "%.1f", value) }

    private var adapterDetail: String {
        var detail = model.adapterStatus.label
        if let last = model.lastReport {
            detail += " · last report \(Int(Date().timeIntervalSince(last)))s ago"
        }
        return detail
    }

    private var pauseDetail: String {
        guard let until = model.settings.pausedUntil, until > Date() else { return "Reminders on." }
        return "Paused until \(until.formatted(date: .omitted, time: .shortened))."
    }

    private func dayChip(_ day: Weekday) -> some View {
        let on = model.settings.deskDays.contains(day)
        let letter = ["S", "M", "T", "W", "T", "F", "S"][day.rawValue - 1]
        return Button {
            if on { model.settings.deskDays.remove(day) } else { model.settings.deskDays.insert(day) }
        } label: {
            Text(letter)
                .font(Theme.ui(12, weight: .medium))
                .frame(width: 26, height: 24)
                .background(on ? Theme.primary : Theme.surface)
                .foregroundStyle(on ? .white : Theme.muted)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? .clear : Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
