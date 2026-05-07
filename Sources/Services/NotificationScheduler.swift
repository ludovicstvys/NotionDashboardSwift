import Foundation
import SwiftUI
import UserNotifications

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum NotificationActionID {
  static let snooze15 = "SNOOZE_15_MIN"
  static let snooze60 = "SNOOZE_60_MIN"
  static let snoozeTomorrow = "SNOOZE_TOMORROW"
  static let openLink = "OPEN_EVENT_LINK"
}

private enum NotificationCategoryID {
  static let calendarEvent = "CALENDAR_EVENT_CATEGORY"
  static let focusSession = "FOCUS_SESSION_CATEGORY"
}

private struct NotificationEventPayload: Sendable {
  var eventID: String
  var summary: String
  var startISO: String
  var sourceURL: String
  var meetingLink: String

  init(event: CalendarEvent) {
    eventID = event.id
    summary = event.summary
    startISO = event.start.iso8601String
    sourceURL = event.sourceUrl
    meetingLink = event.meetingLink
  }

  init(userInfo: [AnyHashable: Any]) {
    eventID = userInfo["eventID"] as? String ?? ""
    summary = userInfo["summary"] as? String ?? ""
    startISO = userInfo["startISO"] as? String ?? ""
    sourceURL = userInfo["sourceUrl"] as? String ?? ""
    meetingLink = userInfo["meetingLink"] as? String ?? ""
  }

  var userInfo: [String: String] {
    [
      "eventID": eventID,
      "summary": summary,
      "startISO": startISO,
      "sourceUrl": sourceURL,
      "meetingLink": meetingLink,
    ]
  }
}

private struct ScheduledReminderCandidate {
  var identifier: String
  var event: CalendarEvent
  var offset: Int
  var fireDate: Date

  var signatureFragment: String {
    "\(identifier)|\(Int(fireDate.timeIntervalSince1970))"
  }
}

@MainActor
final class NotificationScheduler: NSObject, ObservableObject {
  @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
  @Published var lastStatusMessage: String = ""

  private let center = UNUserNotificationCenter.current()
  private let reminderHorizon: TimeInterval = 30 * 24 * 60 * 60
  private let maxPendingEventReminders = 48
  private let dailySummaryIdentifier = "daily-summary"
  private weak var diagnostics: DiagnosticsStore?
  private weak var focusStore: FocusStore?
  private var lastScheduledSignature: String = ""

  init(diagnostics: DiagnosticsStore?, focusStore: FocusStore? = nil) {
    self.diagnostics = diagnostics
    self.focusStore = focusStore
    super.init()
    center.delegate = self
    registerCategory()
    Task {
      await refreshAuthorizationStatus()
    }
  }

  func schedulePomodoroCompletionNotification(workMinutes: Int, breakMinutes: Int) async {
    guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
      lastStatusMessage = "Notifications not authorized."
      return
    }

    let content = UNMutableNotificationContent()
    content.title = "Pomodoro complete"
    content.body = "Work session finished. Break for \(max(1, breakMinutes)) minute(s)."
    content.sound = .default
    content.categoryIdentifier = NotificationCategoryID.focusSession

    do {
      try await center.add(
        UNNotificationRequest(
          identifier: "focus-complete-\(UUID().uuidString)",
          content: content,
          trigger: nil
        )
      )
      lastStatusMessage = "Pomodoro completion notification sent."
      diagnostics?.log(
        category: "notifications",
        message: lastStatusMessage,
        metadata: [
          "workMinutes": "\(max(1, workMinutes))",
          "breakMinutes": "\(max(1, breakMinutes))"
        ]
      )
    } catch {
      lastStatusMessage = "Unable to send pomodoro notification."
      diagnostics?.log(
        severity: .warning,
        category: "notifications",
        message: lastStatusMessage,
        metadata: ["error": error.localizedDescription]
      )
    }
  }

  func requestAuthorization() async {
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
      await refreshAuthorizationStatus()
      lastStatusMessage = granted ? "Notifications enabled." : "Notifications denied."
      diagnostics?.log(
        severity: granted ? .info : .warning,
        category: "notifications",
        message: lastStatusMessage
      )
    } catch {
      lastStatusMessage = "Notification auth failed: \(error.localizedDescription)"
      diagnostics?.log(
        severity: .error,
        category: "notifications",
        message: lastStatusMessage
      )
    }
  }

  func scheduleEventReminders(events: [CalendarEvent], prefs: ReminderPrefs) async {
    guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
      lastStatusMessage = "Notifications not authorized."
      return
    }

    let now = Date()
    let horizon = now.addingTimeInterval(reminderHorizon)
    var candidates: [ScheduledReminderCandidate] = []
    for event in events {
      let offsets = prefs.offsets(for: event.eventType)
      for offset in offsets {
        let fireDate = event.start.addingTimeInterval(TimeInterval(-offset * 60))
        if fireDate <= now || fireDate > horizon { continue }
        let id = "event|\(event.id)|m\(offset)"
        candidates.append(
          ScheduledReminderCandidate(
            identifier: id,
            event: event,
            offset: offset,
            fireDate: fireDate
          )
        )
      }
    }

    candidates.sort { $0.fireDate < $1.fireDate }
    if candidates.count > maxPendingEventReminders {
      candidates = Array(candidates.prefix(maxPendingEventReminders))
    }

    let signature = candidates.map(\.signatureFragment).joined(separator: "||")
    guard signature != lastScheduledSignature else {
      lastStatusMessage = "Reminders unchanged."
      return
    }

    await removeEventNotifications()

    var scheduled = 0
    for candidate in candidates {
      let payload = NotificationEventPayload(event: candidate.event)
      let offset = candidate.offset
      let event = candidate.event
      let fireDate = candidate.fireDate
      let id = candidate.identifier
      let content = UNMutableNotificationContent()
      content.title = offset >= 60 ? "Event in \(offset / 60)h" : "Event soon"
      content.body = "\(event.summary) (\(event.whenText))"
      content.sound = .default
      content.categoryIdentifier = NotificationCategoryID.calendarEvent
      content.userInfo = payload.userInfo
      let trigger = UNCalendarNotificationTrigger(
        dateMatching: Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute, .second],
          from: fireDate
        ),
        repeats: false
      )
      let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
      do {
        try await center.add(request)
        scheduled += 1
      } catch {
        diagnostics?.log(
          severity: .warning,
          category: "notifications",
          message: "Unable to schedule reminder.",
          metadata: ["eventID": event.id, "error": error.localizedDescription]
        )
      }
    }

    lastScheduledSignature = signature
    lastStatusMessage = scheduled == 0 ? "No reminder scheduled." : "Scheduled \(scheduled) reminder(s)."
    diagnostics?.log(category: "notifications", message: lastStatusMessage)
  }

  func scheduleDailySummary(events: [CalendarEvent]) async {
    guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
      lastStatusMessage = "Notifications not authorized."
      return
    }

    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
    let tomorrowEvents = events
      .filter { calendar.isDate($0.start, inSameDayAs: tomorrow) }
      .sorted { $0.start < $1.start }

    let content = UNMutableNotificationContent()
    content.title = "Tomorrow at a glance"
    if tomorrowEvents.isEmpty {
      content.body = "No calendar event is scheduled tomorrow."
    } else {
      let preview = tomorrowEvents.prefix(3).map { event in
        event.isAllDay ? "All day: \(event.summary)" : "\(event.start.formatted(.dateTime.hour().minute())) \(event.summary)"
      }.joined(separator: " • ")
      content.body = "\(tomorrowEvents.count) event(s): \(preview)"
    }
    content.sound = .default

    var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
    components.hour = 8
    components.minute = 0
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    center.removePendingNotificationRequests(withIdentifiers: [dailySummaryIdentifier])
    do {
      try await center.add(UNNotificationRequest(identifier: dailySummaryIdentifier, content: content, trigger: trigger))
      lastStatusMessage = "Daily summary scheduled for tomorrow at 08:00."
      diagnostics?.log(category: "notifications", message: lastStatusMessage)
    } catch {
      lastStatusMessage = "Daily summary failed: \(error.localizedDescription)"
      diagnostics?.log(severity: .warning, category: "notifications", message: lastStatusMessage)
    }
  }

  func removeEventNotifications() async {
    let pending = await center.pendingNotificationRequests()
    let ids = pending
      .map(\.identifier)
      .filter { $0.hasPrefix("event|") || $0.hasPrefix("snooze|") }
    center.removePendingNotificationRequests(withIdentifiers: ids)
    lastScheduledSignature = ""
  }

  func refreshAuthorizationStatus() async {
    let settings = await center.notificationSettings()
    authorizationStatus = settings.authorizationStatus
  }

  private func registerCategory() {
    let actions = [
      UNNotificationAction(
        identifier: NotificationActionID.snooze15,
        title: "Snooze 15m",
        options: []
      ),
      UNNotificationAction(
        identifier: NotificationActionID.snooze60,
        title: "Snooze 1h",
        options: []
      ),
      UNNotificationAction(
        identifier: NotificationActionID.snoozeTomorrow,
        title: "Snooze tomorrow",
        options: []
      ),
      UNNotificationAction(
        identifier: NotificationActionID.openLink,
        title: "Open link",
        options: [.foreground]
      ),
    ]
    let category = UNNotificationCategory(
      identifier: NotificationCategoryID.calendarEvent,
      actions: actions,
      intentIdentifiers: [],
      options: [.customDismissAction]
    )
    let focusCategory = UNNotificationCategory(
      identifier: NotificationCategoryID.focusSession,
      actions: [],
      intentIdentifiers: [],
      options: []
    )
    center.setNotificationCategories([category, focusCategory])
  }

  private func scheduleSnooze(from payload: NotificationEventPayload, minutes: Int) async {
    guard !payload.summary.isEmpty else { return }
    let id = "snooze|\(UUID().uuidString)"
    let content = UNMutableNotificationContent()
    content.title = "Reminder"
    content.body = payload.summary
    content.sound = .default
    content.categoryIdentifier = NotificationCategoryID.calendarEvent
    content.userInfo = payload.userInfo

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    do {
      try await center.add(request)
      diagnostics?.log(
        category: "notifications",
        message: "Snooze scheduled.",
        metadata: ["minutes": "\(minutes)"]
      )
    } catch {
      diagnostics?.log(
        severity: .warning,
        category: "notifications",
        message: "Unable to schedule snooze.",
        metadata: ["error": error.localizedDescription]
      )
    }
  }

  private func openEventLink(using payload: NotificationEventPayload) {
    let target = payload.meetingLink.isEmpty ? payload.sourceURL : payload.meetingLink
    guard let url = URL(string: target), !target.isEmpty else { return }
    if let focusStore, focusStore.isBlocked(url: url) {
      diagnostics?.log(
        severity: .warning,
        category: "notifications",
        message: "Open link blocked by focus mode.",
        metadata: ["url": target]
      )
      return
    }
#if os(iOS)
    UIApplication.shared.open(url)
#elseif os(macOS)
    NSWorkspace.shared.open(url)
#endif
  }
}

extension NotificationScheduler: UNUserNotificationCenterDelegate {
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let payload = NotificationEventPayload(userInfo: response.notification.request.content.userInfo)
    switch response.actionIdentifier {
    case NotificationActionID.snooze15:
      await scheduleSnooze(from: payload, minutes: 15)
    case NotificationActionID.snooze60:
      await scheduleSnooze(from: payload, minutes: 60)
    case NotificationActionID.snoozeTomorrow:
      await scheduleSnooze(from: payload, minutes: 24 * 60)
    case NotificationActionID.openLink, UNNotificationDefaultActionIdentifier:
      await MainActor.run {
        self.openEventLink(using: payload)
      }
    default:
      break
    }
  }
}
