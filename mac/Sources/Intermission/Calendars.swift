import AppKit
import DeskCore
import EventKit
import Foundation
import SwiftUI

/// A calendar as Settings needs to show it: several accounts use the same
/// names ("Personal Calendar" twice, two US holiday feeds), so the account
/// and the calendar's own colour are what tell them apart.
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let account: String
    let color: Color
    /// Birthdays and subscribed feeds: all-day, never block a gap.
    let isSubscribed: Bool
}

/// Personal calendars, read-only, through EventKit.
///
/// Read-only in the strict sense: the app asks for access to events, never
/// writes one, and only ever takes a title and a time range. Which calendars
/// are read is Carl's choice, saved in settings.
@MainActor
final class Calendars {
    private let store = EKEventStore()
    private(set) var authorized = false
    private(set) var available: [CalendarInfo] = []

    func requestAccess() async {
        do {
            authorized = try await store.requestFullAccessToEvents()
        } catch {
            NSLog("Intermission: calendar access failed: %@", String(describing: error))
            authorized = false
        }
        refreshAvailable()
    }

    func refreshAvailable() {
        guard authorized else {
            available = []
            return
        }
        available = store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    account: calendar.source?.title ?? "Other",
                    color: calendar.cgColor.map { Color(nsColor: NSColor(cgColor: $0) ?? .gray) } ?? .gray,
                    isSubscribed: calendar.type == .subscription || calendar.type == .birthday
                )
            }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    /// Events on `day` from the chosen calendars. All-day events are left out:
    /// a holiday doesn't block a gap the way a dentist appointment does.
    func events(on day: Date, calendarIDs: Set<String>, calendar: Calendar = .current) -> [CalendarEvent] {
        guard authorized, !calendarIDs.isEmpty else { return [] }
        let chosen = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }

        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .map { CalendarEvent(start: $0.startDate, end: $0.endDate, title: $0.title ?? "Event") }
            .sorted { $0.start < $1.start }
    }
}
