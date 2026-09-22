import DeskCore
import Foundation

/// `Intermission --dump-plan` prints today's plan as text and exits.
///
/// Times only, never anything about who a session is with - so it can be
/// pasted into a bug report, or read over someone's shoulder, safely.
enum PlanDump {
    static func runIfAsked() {
        guard CommandLine.arguments.contains("--dump-plan") else { return }

        var schedule = SessionSchedule(url: Paths.sessions)
        schedule.reload()
        let settings = SettingsStore(url: Paths.support.appending(path: "settings.json")).load()
        let today = schedule.sessions(on: Date())

        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        print("sessions today: \(today.count)")
        for session in today {
            print("  \(session.start.formatted(time)) – \(session.end.formatted(time))  \(session.mode.rawValue)")
        }

        let windows = schedule.workingWindows(on: Date())
        print("\nworking windows: " + (windows.isEmpty ? "none configured" : windows
            .map { "\($0.start.formatted(time)) – \($0.end.formatted(time))" }
            .joined(separator: ", ")))
        if schedule.isDayOff(Date()) { print("today is a day off — no plan") }

        let plans = PlanStore(url: Paths.support.appending(path: "plans.json"))
        let saved = plans[Date()]
        if !saved.edits.isEmpty {
            print("\nyour edits: " + saved.edits.map { "\($0.intermissionID) \($0.change)" }.joined(separator: ", "))
        }

        let plan = Planner(intermissions: settings.intermissions).plan(
            sessions: schedule.sessions,
            on: Date(),
            edits: saved.edits,
            configuredHours: schedule.workingHours(on: Date()),
            workingWindows: windows
        )
        print("\nplan: \(plan.count) blocks")
        for block in plan {
            let kind = switch block.kind {
            case .session(let virtual): virtual ? "session(virtual)" : "session"
            case .note: "note"
            case .calendarEvent: "calendar"
            case .intermission(let id): "intermission(\(id))"
            case .open: "open"
            }
            print("  \(block.start.formatted(time)) – \(block.end.formatted(time))  \(kind)")
        }
        exit(0)
    }
}
