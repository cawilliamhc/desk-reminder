import DeskCore
import SwiftUI

@main
struct IntermissionApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Intermission", id: "main") {
            HStack(spacing: 0) {
                SidebarView(model: model)
                Divider()
                Group {
                    switch model.selectedView {
                    case .today: TodayView(model: model)
                    case .settings: SettingsView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 860, minHeight: 560)
            .background(Theme.surface)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)

        MenuBarExtra(model.menuBarTitle) {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.height.map { String(format: "%.1f″", $0) } ?? "—")
                    .font(Theme.headline(28)).monospacedDigit()
                Text("\(Int((model.today.standingShare * 100).rounded()))% standing · \(hoursMinutes(model.today.standing)) up today")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
            }

            Divider()

            Button("I just finished a session") { model.finishedSessionNow() }
                .keyboardShortcut(.return, modifiers: .command)
            if model.settings.pausedUntil == nil {
                Button("Pause for 1 hour") { model.pause(until: Date().addingTimeInterval(3600)) }
                    .keyboardShortcut("p", modifiers: .command)
            } else {
                Button("Resume reminders") { model.resume() }
                    .keyboardShortcut("p", modifiers: .command)
            }

            Divider()

            Button("Open Intermission") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o", modifiers: .command)
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(width: 240)
    }
}
