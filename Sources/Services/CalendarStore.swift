import Foundation
import SwiftUI

private enum CalendarRefreshScope {
  case launch
  case calendarScreen
  case manual

  var pastDays: Int {
    switch self {
    case .launch:
      return 2
    case .calendarScreen:
      return 7
    case .manual:
      return 30
    }
  }

  var futureDays: Int {
    switch self {
    case .launch:
      return 45
    case .calendarScreen:
      return 120
    case .manual:
      return 365
    }
  }

  var staleInterval: TimeInterval {
    switch self {
    case .launch:
      return 10 * 60
    case .calendarScreen:
      return 5 * 60
    case .manual:
      return 0
    }
  }

  func dateInterval(relativeTo now: Date) -> DateInterval {
    DateInterval(
      start: now.addingDays(-pastDays),
      end: now.addingDays(futureDays)
    )
  }
}

private struct CalendarCacheSnapshot: Codable {
  var events: [CalendarEvent]
  var googleCalendars: [GoogleCalendarDescriptor]
  var lastRefreshDate: Date?
  var loadedFutureDays: Int
  var lastIcalSource: String
}

@MainActor
final class CalendarStore: ObservableObject {
  @Published private(set) var events: [CalendarEvent] = []
  @Published private(set) var googleCalendars: [GoogleCalendarDescriptor] = []
  @Published var isLoading: Bool = false
  @Published var statusMessage: String = ""
  @Published var selectedCalendarIDs: Set<String> = []
  @Published private(set) var lastRefreshDate: Date?
  @Published private(set) var groupedEvents: [CalendarEventGroup] = []
  @Published private(set) var upcomingEvents: [CalendarEvent] = []
  @Published private(set) var upcomingCount = 0
  @Published private(set) var todayCount = 0
  @Published private(set) var nextUpcomingEvent: CalendarEvent?
  @Published private(set) var calendarRevision: Int = 0
  @Published private(set) var dataRevision: Int = 0

  private let cacheStorageKey = "swift_notion_dashboard_calendar_cache_v2"
  private let defaults: UserDefaults
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let icsService: ICSService
  private let googleService: GoogleCalendarService
  private let persistenceScheduler = DebouncedWorkScheduler(
    label: "com.loldashboard.notiondashboard.calendar-store-persist",
    delay: 0.18
  )
  private weak var configStore: ConfigStore?
  private weak var googleAuthStore: GoogleAuthStore?
  private weak var notificationScheduler: NotificationScheduler?
  private weak var diagnostics: DiagnosticsStore?
  private let calendarRepository: CalendarRepository?
  private var isLoadingGoogleCalendars = false
  private var lastLoadedFutureDays: Int = 0
  private var lastIcalSource: String = ""
  private var lastReminderSignature: Int?

  init(
    configStore: ConfigStore,
    googleAuthStore: GoogleAuthStore,
    notificationScheduler: NotificationScheduler?,
    diagnostics: DiagnosticsStore?,
    calendarRepository: CalendarRepository? = nil,
    defaults: UserDefaults = .standard,
    icsService: ICSService = ICSService(),
    googleService: GoogleCalendarService = GoogleCalendarService()
  ) {
    self.configStore = configStore
    self.googleAuthStore = googleAuthStore
    self.notificationScheduler = notificationScheduler
    self.diagnostics = diagnostics
    self.calendarRepository = calendarRepository
    self.defaults = defaults
    self.icsService = icsService
    self.googleService = googleService
    self.selectedCalendarIDs = Set(configStore.config.googleSelectedCalendarIDs)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder

    loadCache()
  }

  func prepareForLaunch(icalURL: String?) async {
    await refreshCombinedEvents(icalURL: icalURL, scope: .launch, force: false)
  }

  func prepareForCalendarScreen(icalURL: String?) async {
    if googleAuthStore?.isAuthenticated == true {
      await loadGoogleCalendars(force: false)
    }
    await refreshCombinedEvents(icalURL: icalURL, scope: .calendarScreen, force: false)
  }

  func loadExternalCalendar(url: String) async {
    let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      applyEvents([], iCalSource: "", scope: .manual)
      statusMessage = "No iCal URL configured."
      return
    }

    await refreshCombinedEvents(icalURL: clean, scope: .calendarScreen, force: true)
  }

  func loadGoogleCalendars(force: Bool = false) async {
    guard let googleAuthStore else { return }
    guard googleAuthStore.isAuthenticated else { return }
    guard !isLoadingGoogleCalendars else { return }

    if !force, !googleCalendars.isEmpty {
      hydrateSelectedCalendars(from: googleCalendars)
      return
    }

    isLoadingGoogleCalendars = true
    defer { isLoadingGoogleCalendars = false }

    do {
      let token = try await googleAuthStore.validAccessToken()
      let calendars = try await googleService.listCalendars(accessToken: token)
      googleCalendars = calendars
      hydrateSelectedCalendars(from: calendars)
      persistCache()
      statusMessage = "Google calendars loaded (\(calendars.count))."
      diagnostics?.log(category: "calendar-google", message: statusMessage)
    } catch {
      statusMessage = "Google calendars error: \(error.localizedDescription)"
      diagnostics?.log(
        severity: .warning,
        category: "calendar-google",
        message: statusMessage
      )
    }
  }

  func setCalendarSelected(calendarID: String, isSelected: Bool, icalURL: String? = nil) async {
    if isSelected {
      selectedCalendarIDs.insert(calendarID)
    } else {
      selectedCalendarIDs.remove(calendarID)
    }
    configStore?.update { config in
      config.googleSelectedCalendarIDs = Array(selectedCalendarIDs).sorted()
    }
    persistCache()
    await refreshCombinedEvents(icalURL: icalURL, scope: .calendarScreen, force: true)
  }

  func handleGoogleSignOut(icalURL: String? = nil) async {
    googleCalendars = []
    selectedCalendarIDs = []
    events.removeAll { $0.sourceType == .google }
    lastRefreshDate = Date()
    statusMessage = "Google disconnected."
    configStore?.update { config in
      config.googleSelectedCalendarIDs = []
      config.googleDefaultCalendarID = ""
    }
    lastReminderSignature = nil
    persistCache()
    await maybeScheduleRemindersIfNeeded(prefs: configStore?.config.reminderPrefs ?? .defaults)
    await refreshCombinedEvents(icalURL: icalURL, scope: .calendarScreen, force: true)
  }

  func loadCombinedEvents(icalURL: String?) async {
    await refreshCombinedEvents(icalURL: icalURL, scope: .manual, force: true)
  }

  private func refreshCombinedEvents(
    icalURL: String?,
    scope: CalendarRefreshScope,
    force: Bool
  ) async {
    guard let configStore else { return }
    guard !isLoading else { return }

    let iCalSource = (icalURL ?? configStore.config.externalIcalUrl).trimmingCharacters(in: .whitespacesAndNewlines)
    guard force || shouldRefresh(scope: scope, iCalSource: iCalSource) else { return }

    isLoading = true
    defer { isLoading = false }

    let range = scope.dateInterval(relativeTo: Date())
    let effectiveCalendarIDs = selectedCalendarIDs.isEmpty
      ? configStore.config.googleSelectedCalendarIDs
      : Array(selectedCalendarIDs)

    async let icalResult = loadICSResult(source: iCalSource, range: range)
    async let googleResult = loadGoogleResult(range: range, calendarIDs: effectiveCalendarIDs)

    let resolvedICS = await icalResult
    let resolvedGoogle = await googleResult

    var merged: [CalendarEvent] = []
    var fragments: [String] = []

    switch resolvedICS {
    case let .success(items):
      merged.append(contentsOf: items)
      fragments.append("iCal: \(items.count)")
    case let .failure(error):
      fragments.append("iCal error")
      diagnostics?.log(
        severity: .warning,
        category: "calendar-ical",
        message: "iCal load failed in combined refresh.",
        metadata: ["error": error.localizedDescription]
      )
    case .none:
      break
    }

    switch resolvedGoogle {
    case let .success(items):
      merged.append(contentsOf: items)
      fragments.append("Google: \(items.count)")
    case let .failure(error):
      fragments.append("Google error")
      diagnostics?.log(
        severity: .warning,
        category: "calendar-google",
        message: "Google events refresh failed.",
        metadata: ["error": error.localizedDescription]
      )
    case .none:
      break
    }

    let normalized = merged.sorted { $0.start < $1.start }
    applyEvents(normalized, iCalSource: iCalSource, scope: scope)

    let prefix = fragments.isEmpty ? "No source." : fragments.joined(separator: " | ")
    statusMessage = "\(prefix) | total: \(events.count)"
    diagnostics?.log(category: "calendar", message: statusMessage)

    await maybeScheduleRemindersIfNeeded(prefs: configStore.config.reminderPrefs)
  }

  func classifyEventType(summary: String, description: String, location: String) -> EventType {
    let combined = "\(summary) \(description) \(location)".normalizedToken
    if combined.contains("deadline") || combined.contains("date limite") || combined.contains("due") {
      return .deadline
    }
    if combined.contains("entretien") || combined.contains("interview") {
      return .interview
    }
    if combined.contains("meet") || combined.contains("zoom") || combined.contains("teams") {
      return .meeting
    }
    return .defaultType
  }

  func addLocalEvent(_ event: CalendarEvent) async {
    var copy = event
    copy.eventType = classifyEventType(summary: event.summary, description: event.description, location: event.location)
    applyEvents((events + [copy]).sorted { $0.start < $1.start }, iCalSource: lastIcalSource, scope: .calendarScreen)
    if let prefs = configStore?.config.reminderPrefs {
      await maybeScheduleRemindersIfNeeded(prefs: prefs)
    }
  }

  func createGoogleEvent(
    summary: String,
    location: String,
    description: String,
    start: Date,
    end: Date
  ) async {
    guard let configStore else { return }
    do {
      let token = try await googleAuthStore?.validAccessToken() ?? ""
      guard !token.isEmpty else {
        statusMessage = "Google auth required."
        return
      }
      let calendarID = configStore.config.googleDefaultCalendarID.isEmpty
        ? (googleCalendars.first(where: \.isPrimary)?.id ?? "primary")
        : configStore.config.googleDefaultCalendarID
      _ = try await googleService.createEvent(
        accessToken: token,
        calendarID: calendarID,
        summary: summary,
        location: location,
        description: description,
        start: start,
        end: end
      )
      diagnostics?.log(
        category: "calendar-google",
        message: "Google event created.",
        metadata: ["calendarID": calendarID]
      )
      await refreshCombinedEvents(
        icalURL: configStore.config.externalIcalUrl,
        scope: .calendarScreen,
        force: true
      )
    } catch {
      statusMessage = "Google create event error: \(error.localizedDescription)"
      diagnostics?.log(
        severity: .warning,
        category: "calendar-google",
        message: statusMessage
      )
    }
  }

  private func shouldRefresh(scope: CalendarRefreshScope, iCalSource: String) -> Bool {
    if events.isEmpty {
      return true
    }
    if iCalSource != lastIcalSource {
      return true
    }
    if scope.futureDays > lastLoadedFutureDays {
      return true
    }
    guard let lastRefreshDate else { return true }
    return Date().timeIntervalSince(lastRefreshDate) >= scope.staleInterval
  }

  private func hydrateSelectedCalendars(from calendars: [GoogleCalendarDescriptor]) {
    guard selectedCalendarIDs.isEmpty else { return }
    let defaults = calendars.filter(\.isPrimary).map(\.id)
    selectedCalendarIDs = Set(defaults.isEmpty ? calendars.prefix(2).map(\.id) : defaults)
    configStore?.update { config in
      config.googleSelectedCalendarIDs = Array(selectedCalendarIDs).sorted()
    }
  }

  private func loadICSResult(
    source: String,
    range: DateInterval
  ) async -> Result<[CalendarEvent], Error>? {
    guard !source.isEmpty else { return nil }
    do {
      return .success(try await icsService.fetchEvents(from: source, range: range))
    } catch {
      return .failure(error)
    }
  }

  private func loadGoogleResult(
    range: DateInterval,
    calendarIDs: [String]
  ) async -> Result<[CalendarEvent], Error>? {
    guard let googleAuthStore, googleAuthStore.isAuthenticated else { return nil }
    do {
      let token = try await googleAuthStore.validAccessToken()
      return .success(
        try await googleService.fetchEvents(
          accessToken: token,
          calendarIDs: calendarIDs,
          timeMin: range.start,
          timeMax: range.end
        )
      )
    } catch {
      return .failure(error)
    }
  }

  private func applyEvents(
    _ loadedEvents: [CalendarEvent],
    iCalSource: String,
    scope: CalendarRefreshScope
  ) {
    let previous = events.reduce(into: [String: CalendarEvent]()) { partialResult, event in
      partialResult[event.id] = event
    }
    let next = loadedEvents.reduce(into: [String: CalendarEvent]()) { partialResult, event in
      partialResult[event.id] = event
    }
    let deletedIDs = Set(previous.keys).subtracting(next.keys)
    let upsertedEvents = next.compactMap { key, value -> CalendarEvent? in
      guard previous[key] != value else { return nil }
      return value
    }

    events = loadedEvents
    lastRefreshDate = Date()
    lastLoadedFutureDays = max(lastLoadedFutureDays, scope.futureDays)
    lastIcalSource = iCalSource
    refreshDerivedState()
    if !deletedIDs.isEmpty {
      calendarRepository?.deleteEvents(ids: deletedIDs)
    }
    if !upsertedEvents.isEmpty {
      calendarRepository?.upsertEvents(upsertedEvents)
    }
    bumpCalendarRevision()
    persistCache()
  }

  private func loadCache() {
    guard
      let data = defaults.data(forKey: cacheStorageKey),
      let snapshot = try? decoder.decode(CalendarCacheSnapshot.self, from: data)
    else {
      return
    }

    events = snapshot.events.sorted { $0.start < $1.start }
    googleCalendars = snapshot.googleCalendars
    lastRefreshDate = snapshot.lastRefreshDate
    lastLoadedFutureDays = snapshot.loadedFutureDays
    lastIcalSource = snapshot.lastIcalSource
    refreshDerivedState()
    calendarRepository?.replaceEvents(events)
    bumpCalendarRevision()
    WidgetSnapshotSync.syncEvents(events)
  }

  private func persistCache() {
    let snapshot = CalendarCacheSnapshot(
      events: events,
      googleCalendars: googleCalendars,
      lastRefreshDate: lastRefreshDate,
      loadedFutureDays: lastLoadedFutureDays,
      lastIcalSource: lastIcalSource
    )
    let defaults = self.defaults
    let cacheStorageKey = self.cacheStorageKey
    let events = self.events
    persistenceScheduler.schedule {
      let start = CFAbsoluteTimeGetCurrent()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      guard let data = try? encoder.encode(snapshot) else { return }
      defaults.set(data, forKey: cacheStorageKey)
      let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
      PerformanceMonitor.recordPersistence(label: "CalendarStore.persistCache", durationMs: durationMs)
    }
    WidgetSnapshotSync.syncEvents(events)
  }

  private func refreshDerivedState() {
    let calendar = Calendar.current
    let now = Date()
    let threshold = now.addingTimeInterval(-3_600)
    var nextUpcoming: [CalendarEvent] = []
    var nextUpcomingCount = 0
    var nextTodayCount = 0
    var grouped: [Date: [CalendarEvent]] = [:]
    grouped.reserveCapacity(max(events.count / 2, 8))

    for event in events {
      if event.end >= now {
        nextUpcomingCount += 1
      }
      if calendar.isDateInToday(event.start) {
        nextTodayCount += 1
      }
      if event.end >= threshold {
        nextUpcoming.append(event)
      }
      let day = calendar.startOfDay(for: event.start)
      grouped[day, default: []].append(event)
    }

    upcomingEvents = nextUpcoming
    upcomingCount = nextUpcomingCount
    todayCount = nextTodayCount
    nextUpcomingEvent = nextUpcoming.first
    groupedEvents = grouped.keys.sorted().map { day in
      CalendarEventGroup(day: day, items: grouped[day] ?? [])
    }
  }

  private func maybeScheduleRemindersIfNeeded(prefs: ReminderPrefs) async {
    let signature = remindersSignature(events: events, prefs: prefs)
    guard signature != lastReminderSignature else { return }
    lastReminderSignature = signature
    await notificationScheduler?.scheduleEventReminders(events: events, prefs: prefs)
  }

  private func remindersSignature(events: [CalendarEvent], prefs: ReminderPrefs) -> Int {
    var hasher = Hasher()
    hasher.combine(prefs)
    hasher.combine(events.count)
    for event in events {
      hasher.combine(event.id)
      hasher.combine(event.start.timeIntervalSince1970)
      hasher.combine(event.end.timeIntervalSince1970)
      hasher.combine(event.eventType.rawValue)
    }
    return hasher.finalize()
  }

  private func bumpCalendarRevision() {
    calendarRevision &+= 1
    dataRevision &+= 1
  }
}
