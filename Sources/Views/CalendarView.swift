import SwiftUI

private enum CalendarDisplayMode: String, CaseIterable, Identifiable {
  case day = "Day"
  case week = "Week"
  case list = "List"

  var id: String { rawValue }
}

struct CalendarView: View {
  @EnvironmentObject private var appRouter: AppRouter
  @EnvironmentObject private var calendarViewModel: CalendarViewModel
  @EnvironmentObject private var calendarStore: CalendarStore
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var googleAuthStore: GoogleAuthStore
  @EnvironmentObject private var notificationScheduler: NotificationScheduler
  @State private var iCalURL: String = ""
  @State private var selectedEvent: CalendarEvent?
  @State private var editingEvent: CalendarEvent?
  @State private var showCreateGoogleEvent = false
  @State private var selectedDay = Calendar.current.startOfDay(for: Date())
  @State private var displayMode: CalendarDisplayMode = .day

  var body: some View {
    NavigationStack {
      ScrollViewReader { scrollProxy in
        GeometryReader { proxy in
          let metrics = WorkspaceLayoutMetrics(width: proxy.size.width)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
              calendarHeroPanel(metrics: metrics)
              dayCalendarPanel(width: proxy.size.width)
              connectionPanel
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.regularPanelPadding)
            .frame(maxWidth: metrics.contentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .top)
          }
        }
        .onAppear {
          focusTargetEvent(using: scrollProxy)
        }
        .onChange(of: appRouter.route.nonce) { _ in
          focusTargetEvent(using: scrollProxy)
        }
        .onChange(of: calendarViewModel.state.groupedEvents.count) { _ in
          syncSelectedDayWithLoadedEvents()
          focusTargetEvent(using: scrollProxy)
        }
      }
      .background(WorkspaceBackground().equatable())
      .navigationTitle("Calendar")
      .safeAreaInset(edge: .bottom) {
        FooterMessageHost(message: footerMessage)
      }
    }
    .task(priority: .utility) {
      if iCalURL.isEmpty {
        iCalURL = configStore.config.externalIcalUrl
      }
      await calendarStore.prepareForCalendarScreen(icalURL: iCalURL)
    }
    .sheet(item: $selectedEvent) { event in
      NavigationStack {
        CalendarEventDetailView(event: event)
          .toolbar {
            if event.sourceType == .google {
              ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                  editingEvent = event
                  selectedEvent = nil
                }
              }
              ToolbarItem(placement: .secondaryAction) {
                Button("Delete", role: .destructive) {
                  selectedEvent = nil
                  Task { await calendarStore.deleteGoogleEvent(event) }
                }
              }
            }
          }
          .navigationTitle(event.summary.isEmpty ? "Event" : event.summary)
      }
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $showCreateGoogleEvent) {
      CreateGoogleEventSheet { summary, location, description, start, end in
        Task {
          await calendarStore.createGoogleEvent(
            summary: summary,
            location: location,
            description: description,
            start: start,
            end: end
          )
        }
      }
    }
    .sheet(item: $editingEvent) { event in
      EditGoogleEventSheet(event: event) { summary, location, description, start, end in
        Task {
          await calendarStore.updateGoogleEvent(
            event: event,
            summary: summary,
            location: location,
            description: description,
            start: start,
            end: end
          )
        }
      }
    }
    .instrumentedScreen("CalendarView")
  }

  private var connectionPanel: some View {
    WorkspacePanel(
      title: "Sources and actions",
      subtitle: "Manage Google auth, filters, notifications, and event creation from one control layer.",
      tint: WorkspacePalette.warning
    ) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 10) {
          Button(googleAuthStore.isAuthenticated ? "Reconnect Google" : "Connect Google") {
            Task { await googleAuthStore.signInInteractive() }
          }
          .buttonStyle(.borderedProminent)
          .tint(WorkspacePalette.accent)

          Button("Disconnect") {
            googleAuthStore.signOut()
            Task { await calendarStore.handleGoogleSignOut(icalURL: iCalURL) }
          }
          .buttonStyle(.bordered)
          .disabled(!googleAuthStore.isAuthenticated)

          Button("Notifications") {
            Task { await notificationScheduler.requestAuthorization() }
          }
          .buttonStyle(.bordered)

          Button("Create event") {
            showCreateGoogleEvent = true
          }
          .buttonStyle(.bordered)
        }

        VStack(alignment: .leading, spacing: 8) {
          TextField("External calendar feed", text: $iCalURL)
            .textFieldStyle(.roundedBorder)
            .font(.subheadline.monospaced())

          HStack(spacing: 10) {
            Button("Load all") {
              Task {
                configStore.update { $0.externalIcalUrl = iCalURL }
                await calendarStore.loadGoogleCalendars(force: true)
                await calendarStore.loadCombinedEvents(icalURL: iCalURL)
              }
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkspacePalette.warning)

            Button("Google only") {
              Task {
                await calendarStore.loadGoogleCalendars(force: true)
                await calendarStore.loadCombinedEvents(icalURL: "")
              }
            }
            .buttonStyle(.bordered)
          }
        }

        if googleAuthStore.isAuthenticated && !calendarStore.googleCalendars.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(calendarStore.googleCalendars) { cal in
                let selected = calendarStore.selectedCalendarIDs.contains(cal.id)
                Button {
                  Task {
                    await calendarStore.setCalendarSelected(
                      calendarID: cal.id,
                      isSelected: !selected,
                      icalURL: iCalURL
                    )
                  }
                } label: {
                  HStack(spacing: 8) {
                    Circle()
                      .fill(selected ? (WorkspaceColor.hex(cal.backgroundColor) ?? WorkspacePalette.accentSoft) : Color.white.opacity(0.35))
                      .frame(width: 8, height: 8)
                    Text(cal.name)
                      .font(.caption.weight(.semibold))
                  }
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(
                    selected
                      ? (WorkspaceColor.hex(cal.backgroundColor) ?? WorkspacePalette.accent).opacity(0.22)
                      : Color.white.opacity(0.08)
                  )
                  .foregroundStyle(selected ? (WorkspaceColor.hex(cal.foregroundColor) ?? WorkspacePalette.accentSoft) : Color.white.opacity(0.76))
                  .clipShape(Capsule())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        if !googleAuthStore.statusMessage.isEmpty || !calendarStore.statusMessage.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text(googleAuthStore.connectionSummary)
              .font(.caption)
              .foregroundStyle(Color.white.opacity(0.70))
            Text(calendarStore.googleSyncSummary)
              .font(.caption)
              .foregroundStyle(Color.white.opacity(0.70))
            if !calendarStore.statusMessage.isEmpty {
              Text(calendarStore.statusMessage)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.62))
            }
          }
        }
      }
    }
  }

  private func dayCalendarPanel(width: CGFloat) -> some View {
    WorkspacePanel(
      title: "Timeline lens",
      subtitle: "Switch between day, week, and list views without losing the active date context.",
      tint: WorkspacePalette.accentSoft
    ) {
      if calendarStore.isLoading {
        ProgressView("Loading calendar events...")
          .tint(.teal)
      } else if calendarViewModel.state.groupedEvents.isEmpty {
        calendarEmptyState(
          title: "No event loaded",
          message: "Connect Google Calendar or load an external iCal source to populate the feed."
        )
      } else {
        VStack(alignment: .leading, spacing: 18) {
          calendarHeader
          if displayMode != .list {
            dayPickerStrip
          }
          switch displayMode {
          case .day:
            CalendarDayTimelineView(
              day: selectedDay,
              events: events(for: selectedDay),
              highlightedEventID: appRouter.route.eventID,
              compact: width < 760,
              onSelectEvent: { event in selectedEvent = event }
            )
          case .week:
            CalendarWeekView(
              selectedDay: selectedDay,
              events: weekEvents(for: selectedDay),
              highlightedEventID: appRouter.route.eventID,
              onSelectDay: { selectedDay = Calendar.current.startOfDay(for: $0) },
              onSelectEvent: { selectedEvent = $0 }
            )
          case .list:
            calendarListView
          }
        }
      }
    }
    .id("calendar-event-feed")
  }

  private func calendarHeroPanel(metrics: WorkspaceLayoutMetrics) -> some View {
    WorkspaceHeroPanel(tint: WorkspacePalette.accent, padding: metrics.regularPanelPadding) {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 12) {
            Text("TIME OPERATIONS")
              .font(.caption2.weight(.bold))
              .tracking(1.8)
              .foregroundStyle(Color.white.opacity(0.70))

            Text("Timeline control.\nContext intact.")
              .font(.system(size: metrics.sizeClass == .wide ? 40 : 34, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)

            Text("Run the day through a single timeline with clearer source state, faster event actions, and less visual noise.")
              .font(.subheadline)
              .foregroundStyle(Color.white.opacity(0.72))
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)

          VStack(alignment: .trailing, spacing: 10) {
            WorkspaceBadge(text: displayMode.rawValue, tint: WorkspacePalette.accent)
            WorkspaceBadge(text: sourceCount == 0 ? "No sources" : "\(sourceCount) source\(sourceCount == 1 ? "" : "s")", tint: WorkspacePalette.accentSoft)
          }
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
          calendarMetric(title: "Today", value: "\(events(for: Calendar.current.startOfDay(for: Date())).count)", detail: "events in focus", tint: WorkspacePalette.accent)
          calendarMetric(title: "Week", value: "\(weekEvents(for: selectedDay).count)", detail: "events in active week", tint: WorkspacePalette.accentSoft)
          calendarMetric(title: "Sources", value: "\(sourceCount)", detail: sourceCount == 0 ? "nothing connected" : "feeds currently active", tint: WorkspacePalette.warning)
          calendarMetric(title: "Alerts", value: notificationCountLabel, detail: notificationStatusText.lowercased(), tint: WorkspacePalette.success)
        }
      }
    }
  }

  private var calendarHeader: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 12) {
        Picker("Calendar mode", selection: $displayMode) {
          ForEach(CalendarDisplayMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 260)

        Spacer()

        Button {
          Task {
            await calendarStore.loadGoogleCalendars(force: true)
            await calendarStore.loadCombinedEvents(icalURL: iCalURL)
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkspacePalette.accent)

        Button {
          showCreateGoogleEvent = true
        } label: {
          Label("Add event", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.bordered)
      }

      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(selectedDay.formatted(.dateTime.weekday(.wide)))
            .font(.caption.weight(.bold))
            .tracking(1.4)
            .foregroundStyle(Color.white.opacity(0.58))
          Text(selectedDay.formatted(.dateTime.month(.wide).day().year()))
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
        }
        Spacer()
        WorkspaceBadge(text: "\(events(for: selectedDay).count) events", tint: WorkspacePalette.accentSoft)
        WorkspaceBadge(text: todayRelationText(for: selectedDay), tint: Calendar.current.isDateInToday(selectedDay) ? WorkspacePalette.success : .white)
        HStack(spacing: 8) {
          Button {
            selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
          } label: {
            Image(systemName: "chevron.left")
          }
          .buttonStyle(.bordered)
          .accessibilityLabel("Previous day")

          Button("Today") {
            selectedDay = Calendar.current.startOfDay(for: Date())
          }
          .buttonStyle(.borderedProminent)
          .tint(WorkspacePalette.accent)

          Button {
            selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
          } label: {
            Image(systemName: "chevron.right")
          }
          .accessibilityLabel("Next day")
          .buttonStyle(.bordered)
        }
      }
    }
  }

  private var calendarListView: some View {
    LazyVStack(alignment: .leading, spacing: 10) {
      ForEach(calendarViewModel.state.groupedEvents) { group in
        VStack(alignment: .leading, spacing: 10) {
          Text(group.day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
          ForEach(group.items) { event in
            CalendarEventRow(
              event: event,
              isHighlighted: isEventHighlighted(event.id),
              onShowDetails: { selectedEvent = event }
            )
            .id(eventRowID(event.id))
          }
        }
        .padding(.vertical, 4)
      }
    }
  }

  private var dayPickerStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(calendarViewModel.state.groupedEvents.prefix(21)) { group in
          let isSelected = Calendar.current.isDate(group.day, inSameDayAs: selectedDay)
          Button {
            selectedDay = Calendar.current.startOfDay(for: group.day)
          } label: {
            VStack(spacing: 4) {
              Text(group.day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white.opacity(isSelected ? 0.82 : 0.56))
                .tracking(0.5)
              Text(group.day.formatted(.dateTime.day()))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
              Text("\(group.items.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.56))
            }
            .frame(width: 64)
            .padding(.vertical, 10)
            .background(isSelected ? WorkspacePalette.accent.opacity(0.30) : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.06), lineWidth: 1)
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func calendarMetric(title: String, value: String, detail: String, tint: Color) -> some View {
    WorkspaceMetricTile(title: title, value: value, detail: detail, tint: tint)
  }

  private func calendarEmptyState(title: String, message: String) -> some View {
    WorkspaceEmptyState(title: title, message: message, tint: WorkspacePalette.accentSoft, systemImage: "calendar.badge.exclamationmark")
  }

  private var sourceCount: Int {
    var count = 0
    if googleAuthStore.isAuthenticated { count += 1 }
    if !configStore.config.externalIcalUrl.isEmpty { count += 1 }
    return count
  }

  private var notificationStatusText: String {
    switch notificationScheduler.authorizationStatus {
    case .authorized, .provisional:
      return "Alerts on"
    case .denied:
      return "Alerts denied"
    case .notDetermined:
      return "Alerts pending"
    case .ephemeral:
      return "Alerts temporary"
    @unknown default:
      return "Alerts unknown"
    }
  }

  private var notificationCountLabel: String {
    switch notificationScheduler.authorizationStatus {
    case .authorized, .provisional:
      return "Ready"
    case .denied:
      return "Off"
    case .notDetermined:
      return "Ask"
    case .ephemeral:
      return "Temp"
    @unknown default:
      return "?"
    }
  }

  private func focusTargetEvent(using proxy: ScrollViewProxy) {
    guard appRouter.destination == .calendar else { return }
    guard let eventID = appRouter.route.eventID else { return }

    if let event = calendarViewModel.event(id: eventID) {
      selectedDay = Calendar.current.startOfDay(for: event.start)
      withAnimation(.snappy(duration: 0.26)) {
        proxy.scrollTo(eventRowID(eventID), anchor: .center)
      }
      selectedEvent = event
    } else {
      withAnimation(.snappy(duration: 0.26)) {
        proxy.scrollTo("calendar-event-feed", anchor: .top)
      }
    }
  }

  private func isEventHighlighted(_ eventID: String) -> Bool {
    appRouter.destination == .calendar && appRouter.route.eventID == eventID
  }

  private func eventRowID(_ eventID: String) -> String {
    "calendar-event-\(eventID)"
  }

  private func syncSelectedDayWithLoadedEvents() {
    if calendarViewModel.state.groupedEvents.contains(where: { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }) {
      return
    }
    if let today = calendarViewModel.state.groupedEvents.first(where: { Calendar.current.isDateInToday($0.day) }) {
      selectedDay = Calendar.current.startOfDay(for: today.day)
    } else if let first = calendarViewModel.state.groupedEvents.first {
      selectedDay = Calendar.current.startOfDay(for: first.day)
    }
  }

  private func events(for day: Date) -> [CalendarEvent] {
    calendarViewModel.state.groupedEvents.first { group in
      Calendar.current.isDate(group.day, inSameDayAs: day)
    }?.items ?? []
  }

  private func weekEvents(for day: Date) -> [CalendarEvent] {
    guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: day) else { return [] }
    return calendarStore.events.filter { event in
      event.start < interval.end && event.end > interval.start
    }
  }

  private func todayRelationText(for day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInTomorrow(day) { return "Tomorrow" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(.dateTime.weekday(.abbreviated))
  }

  private var footerMessage: String? {
    if !calendarStore.statusMessage.isEmpty {
      return calendarStore.statusMessage
    }
    if !googleAuthStore.statusMessage.isEmpty {
      return googleAuthStore.statusMessage
    }
    return nil
  }
}


struct CreateGoogleEventSheet: View {
  @Environment(\.dismiss) private var dismiss
  let onSave: (String, String, String, Date, Date) -> Void

  @State private var summary: String = ""
  @State private var location: String = ""
  @State private var description: String = ""
  @State private var start: Date = Date().addingTimeInterval(30 * 60)
  @State private var end: Date = Date().addingTimeInterval(90 * 60)

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          WorkspacePanel(title: "Event", subtitle: "Core details for the new Google Calendar entry.", tint: WorkspacePalette.accent, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
              TextField("Summary", text: $summary)
                .textFieldStyle(.roundedBorder)
              TextField("Location", text: $location)
                .textFieldStyle(.roundedBorder)
              TextField("Description", text: $description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
              DatePicker("Start", selection: $start)
              DatePicker("End", selection: $end)
            }
          }
        }
        .padding(18)
      }
      .background(WorkspaceBackground().equatable())
      .navigationTitle("Create Google event")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            onSave(summary.isEmpty ? "Event" : summary, location, description, start, end)
            dismiss()
          }
          .disabled(end <= start)
        }
      }
    }
    .frame(minWidth: 460, minHeight: 420)
  }
}

struct EditGoogleEventSheet: View {
  @Environment(\.dismiss) private var dismiss
  let event: CalendarEvent
  let onSave: (String, String, String, Date, Date) -> Void

  @State private var summary: String
  @State private var location: String
  @State private var description: String
  @State private var start: Date
  @State private var end: Date

  init(
    event: CalendarEvent,
    onSave: @escaping (String, String, String, Date, Date) -> Void
  ) {
    self.event = event
    self.onSave = onSave
    _summary = State(initialValue: event.summary)
    _location = State(initialValue: event.location)
    _description = State(initialValue: event.description)
    _start = State(initialValue: event.start)
    _end = State(initialValue: event.end)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          WorkspacePanel(title: "Event", subtitle: "Update timing, context, and Google Calendar metadata.", tint: WorkspacePalette.accent, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
              TextField("Summary", text: $summary)
                .textFieldStyle(.roundedBorder)
              TextField("Location", text: $location)
                .textFieldStyle(.roundedBorder)
              TextField("Description", text: $description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
              DatePicker("Start", selection: $start)
              DatePicker("End", selection: $end)
            }
          }
        }
        .padding(18)
      }
      .background(WorkspaceBackground().equatable())
      .navigationTitle("Edit Google event")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(summary.isEmpty ? "Event" : summary, location, description, start, end)
            dismiss()
          }
          .disabled(end <= start)
        }
      }
    }
    .frame(minWidth: 460, minHeight: 420)
  }
}

struct CalendarWeekView: View {
  let selectedDay: Date
  let events: [CalendarEvent]
  let highlightedEventID: String?
  let onSelectDay: (Date) -> Void
  let onSelectEvent: (CalendarEvent) -> Void

  private let headerHeight: CGFloat = 34
  private let allDayLaneHeight: CGFloat = 30
  private let timeColumnWidth: CGFloat = 34
  private let hourHeight: CGFloat = 52

  private var weekDays: [Date] {
    guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: selectedDay) else {
      return [selectedDay]
    }
    return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: interval.start) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        Color.clear.frame(width: timeColumnWidth, height: headerHeight)
        ForEach(weekDays, id: \.self) { day in
          dayHeader(day)
            .frame(maxWidth: .infinity, minHeight: headerHeight)
            .background(Calendar.current.isDate(day, inSameDayAs: selectedDay) ? Color.white.opacity(0.04) : Color.clear)
            .overlay(alignment: .leading) {
              Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
              withAnimation(.snappy(duration: 0.2)) { onSelectDay(day) }
            }
        }
      }

      allDayLane

      GeometryReader { proxy in
        let dayWidth = max(90, (proxy.size.width - timeColumnWidth) / 7.0)
        let gridHeight = hourHeight * 24
        ZStack(alignment: .topLeading) {
          weekGrid(dayWidth: dayWidth, gridHeight: gridHeight)
          ForEach(weekEventLayouts(dayWidth: dayWidth), id: \.event.id) { layout in
            weekEventBlock(layout.event, isHighlighted: layout.event.id == highlightedEventID)
              .frame(width: layout.width, height: layout.height, alignment: .topLeading)
              .offset(x: timeColumnWidth + layout.x, y: layout.y)
              .id("calendar-event-\(layout.event.id)")
          }
        }
        .frame(height: gridHeight)
      }
      .frame(minHeight: hourHeight * 24)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color.white.opacity(0.06), Color.black.opacity(0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    )
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(Color.white.opacity(0.06), lineWidth: 1)
    }
  }

  private func dayHeader(_ day: Date) -> some View {
    VStack(spacing: 2) {
      Text(day.formatted(.dateTime.weekday(.abbreviated)))
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.52))
      Text(day.formatted(.dateTime.day()))
        .font(.headline.weight(.semibold))
        .foregroundStyle(.white)
    }
    .frame(maxWidth: .infinity, minHeight: headerHeight)
  }

  private var allDayLane: some View {
    HStack(spacing: 0) {
      Rectangle()
        .fill(Color.white.opacity(0.02))
        .frame(width: timeColumnWidth, height: allDayLaneHeight)
      ForEach(weekDays, id: \.self) { day in
        let dayEvents = events(for: day).filter(\.isAllDay)
        ZStack(alignment: .topLeading) {
          if let event = dayEvents.first {
            Button {
              onSelectEvent(event)
            } label: {
              Text(event.summary.isEmpty ? "All day" : event.summary)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(red: 0.93, green: 0.84, blue: 0.62))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: allDayLaneHeight, alignment: .leading)
                .padding(.horizontal, 10)
                .background(
                  RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(red: 0.43, green: 0.36, blue: 0.27))
                )
            }
            .buttonStyle(.plain)
          }
        }
        .frame(maxWidth: .infinity, minHeight: allDayLaneHeight, alignment: .topLeading)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .leading) {
          Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
        }
      }
    }
  }

  private func weekEventLayouts(dayWidth: CGFloat) -> [WeekEventLayout] {
    let calendar = Calendar.current
    var layouts: [WeekEventLayout] = []

    for (dayIndex, day) in weekDays.enumerated() {
      let dayStart = calendar.startOfDay(for: day)
      guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
      let dayEvents = events
        .filter { !$0.isAllDay && $0.start < dayEnd && $0.end > dayStart }
        .sorted { lhs, rhs in
          if lhs.start == rhs.start { return lhs.end < rhs.end }
          return lhs.start < rhs.start
        }

      let dayInset: CGFloat = 6
      let columnGap: CGFloat = 4
      let usableDayWidth = max(54, dayWidth - dayInset * 2)
      let clusters = overlappingClusters(for: dayEvents)

      for cluster in clusters {
        let placements = columnPlacements(for: cluster)
        let columnCount = max(1, (placements.map(\.column).max() ?? 0) + 1)
        let totalGap = CGFloat(columnCount - 1) * columnGap
        let columnWidth = max(42, (usableDayWidth - totalGap) / CGFloat(columnCount))

        for placement in placements {
          let x = CGFloat(dayIndex) * dayWidth
            + dayInset
            + CGFloat(placement.column) * (columnWidth + columnGap)
          let layout = WeekEventLayout(
            event: placement.event,
            x: x,
            y: yOffset(for: placement.event, in: dayStart),
            width: columnWidth,
            height: durationHeight(for: placement.event, in: dayStart)
          )
          layouts.append(layout)
        }
      }
    }

    return layouts
  }

  private func weekGrid(dayWidth: CGFloat, gridHeight: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(0..<25, id: \.self) { hour in
        Rectangle()
          .fill(Color.white.opacity(hour % 6 == 0 ? 0.11 : 0.05))
          .frame(height: 1)
          .offset(x: timeColumnWidth, y: CGFloat(hour) * hourHeight)
      }
      ForEach(0..<7, id: \.self) { index in
        Rectangle()
          .fill(Color.white.opacity(0.05))
          .frame(width: 1, height: gridHeight)
          .offset(x: timeColumnWidth + CGFloat(index) * dayWidth, y: 0)
      }
      ForEach(0..<24, id: \.self) { hour in
        if hour.isMultiple(of: 3) {
          Text(hourLabel(hour))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.42))
            .frame(width: timeColumnWidth - 4, alignment: .trailing)
            .offset(x: 0, y: CGFloat(hour) * hourHeight - 7)
        }
      }
    }
    .frame(height: gridHeight)
  }

  private func weekEventBlock(_ event: CalendarEvent, isHighlighted: Bool) -> some View {
    Button {
      onSelectEvent(event)
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        Text(event.summary.isEmpty ? "Event" : event.summary)
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color(red: 0.95, green: 0.88, blue: 0.70))
          .lineLimit(2)
        Text(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(Color(red: 0.89, green: 0.78, blue: 0.58).opacity(0.90))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                eventTypeColor(for: event.eventType).opacity(isHighlighted ? 0.42 : 0.26),
                WorkspacePalette.panelBase.opacity(0.92)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(isHighlighted ? eventTypeColor(for: event.eventType).opacity(0.72) : Color.white.opacity(0.10), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
    .buttonStyle(.plain)
  }

  private func hourLabel(_ hour: Int) -> String {
    if hour == 0 { return "12a" }
    if hour == 12 { return "12p" }
    if hour < 12 { return "\(hour)a" }
    return "\(hour - 12)p"
  }

  private func yOffset(for event: CalendarEvent) -> CGFloat {
    yOffset(for: event, in: Calendar.current.startOfDay(for: event.start))
  }

  private func durationHeight(for event: CalendarEvent) -> CGFloat {
    durationHeight(for: event, in: Calendar.current.startOfDay(for: event.start))
  }

  private func yOffset(for event: CalendarEvent, in dayStart: Date) -> CGFloat {
    let eventStart = max(event.start, dayStart)
    let minutes = max(0, Calendar.current.dateComponents([.minute], from: dayStart, to: eventStart).minute ?? 0)
    return CGFloat(minutes) / 60.0 * hourHeight
  }

  private func durationHeight(for event: CalendarEvent, in dayStart: Date) -> CGFloat {
    let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
    let start = max(event.start, dayStart)
    let end = min(max(event.end, event.start.addingTimeInterval(30 * 60)), dayEnd)
    let minutes = max(30, Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 30)
    return max(34, CGFloat(minutes) / 60.0 * hourHeight - 2)
  }

  private func events(for day: Date) -> [CalendarEvent] {
    let dayStart = Calendar.current.startOfDay(for: day)
    let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
    return events.filter { $0.start < dayEnd && $0.end > dayStart }.sorted { $0.start < $1.start }
  }

  private func overlappingClusters(for events: [CalendarEvent]) -> [[CalendarEvent]] {
    var clusters: [[CalendarEvent]] = []
    var current: [CalendarEvent] = []
    var currentEnd: Date?

    for event in events {
      if let end = currentEnd, event.start < end {
        current.append(event)
        currentEnd = max(end, event.end)
      } else {
        if !current.isEmpty { clusters.append(current) }
        current = [event]
        currentEnd = event.end
      }
    }

    if !current.isEmpty { clusters.append(current) }
    return clusters
  }

  private func columnPlacements(for events: [CalendarEvent]) -> [CalendarColumnPlacement] {
    var columnEnds: [Date] = []
    var placements: [CalendarColumnPlacement] = []

    for event in events {
      let column = columnEnds.firstIndex(where: { $0 <= event.start }) ?? columnEnds.count
      if column == columnEnds.count {
        columnEnds.append(event.end)
      } else {
        columnEnds[column] = event.end
      }
      placements.append(CalendarColumnPlacement(event: event, column: column))
    }

    return placements
  }

  private func eventTypeColor(for type: EventType) -> Color {
    switch type {
    case .meeting:
      return WorkspacePalette.accent
    case .interview:
      return WorkspacePalette.warning
    case .deadline:
      return .red
    case .defaultType:
      return WorkspacePalette.accentSoft
    }
  }
}

private struct WeekEventLayout: Identifiable {
  let event: CalendarEvent
  let x: CGFloat
  let y: CGFloat
  let width: CGFloat
  let height: CGFloat

  var id: String { event.id }

  func overlaps(with other: CalendarEvent) -> Bool {
    event.start < other.end && event.end > other.start
  }
}

struct CalendarDayTimelineView: View {
  let day: Date
  let events: [CalendarEvent]
  let highlightedEventID: String?
  let compact: Bool
  let onSelectEvent: (CalendarEvent) -> Void

  private let hourHeight: CGFloat = 72
  private let allDayHeight: CGFloat = 44
  private let timeColumnWidth: CGFloat = 58

  var body: some View {
    let allDayEvents = events.filter(\.isAllDay)
    let timedEvents = events.filter { !$0.isAllDay }
    VStack(alignment: .leading, spacing: 14) {
      allDayLane(events: allDayEvents)

      ScrollView(.vertical, showsIndicators: true) {
        GeometryReader { proxy in
          let timelineWidth = max(220, proxy.size.width - timeColumnWidth - 14)
          ZStack(alignment: .topLeading) {
            hourGrid(timelineWidth: timelineWidth)
            ForEach(layoutItems(for: timedEvents, timelineWidth: timelineWidth)) { item in
              CalendarDayEventBlock(
                event: item.event,
                isHighlighted: item.event.id == highlightedEventID,
                compact: compact,
                onSelect: { onSelectEvent(item.event) }
              )
              .frame(width: item.width, height: item.height)
              .offset(x: timeColumnWidth + 14 + item.x, y: item.y)
              .id("calendar-event-\(item.event.id)")
            }

            if Calendar.current.isDateInToday(day) {
              currentTimeMarker(width: timelineWidth)
                .offset(x: timeColumnWidth + 14, y: currentTimeOffset())
            }
          }
          .frame(height: 24 * hourHeight)
        }
        .frame(height: 24 * hourHeight)
      }
      .frame(minHeight: 620, maxHeight: 820)
      .background(
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color.white.opacity(0.05), Color.black.opacity(0.14)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
      .overlay {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .stroke(Color.white.opacity(0.06), lineWidth: 1)
      }
    }
  }

  private func allDayLane(events: [CalendarEvent]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("All day")
          .font(.caption.weight(.bold))
          .foregroundStyle(Color.white.opacity(0.58))
        Spacer()
        if events.isEmpty {
          Text("No all-day events")
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.46))
        }
      }

      if !events.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 10) {
            ForEach(events) { event in
              Button {
                onSelectEvent(event)
              } label: {
                HStack(spacing: 8) {
                  Circle()
                    .fill(eventTypeColor(for: event.eventType))
                    .frame(width: 8, height: 8)
                  Text(event.summary.isEmpty ? "Event" : event.summary)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: allDayHeight)
                .background(eventTypeColor(for: event.eventType).opacity(0.18))
                .foregroundStyle(.white)
                .clipShape(Capsule())
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .padding(14)
    .workspaceInteractiveSurface(cornerRadius: 22, tint: WorkspacePalette.accentSoft, raised: false)
  }

  private func hourGrid(timelineWidth: CGFloat) -> some View {
    VStack(spacing: 0) {
      ForEach(0..<24, id: \.self) { hour in
        HStack(alignment: .top, spacing: 14) {
          Text(hourLabel(hour))
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(Color.white.opacity(hour % 6 == 0 ? 0.70 : 0.42))
            .frame(width: timeColumnWidth, alignment: .trailing)

          Rectangle()
            .fill(Color.white.opacity(hour % 6 == 0 ? 0.15 : 0.07))
            .frame(width: timelineWidth, height: 1)
            .padding(.top, 7)
        }
        .frame(height: hourHeight, alignment: .top)
      }
    }
    .padding(.top, 4)
  }

  private func currentTimeMarker(width: CGFloat) -> some View {
    HStack(spacing: 0) {
      Circle()
        .fill(WorkspacePalette.warning)
        .frame(width: 8, height: 8)
      Rectangle()
        .fill(WorkspacePalette.warning.opacity(0.88))
        .frame(width: width, height: 2)
    }
  }

  private func layoutItems(for events: [CalendarEvent], timelineWidth: CGFloat) -> [CalendarDayLayoutItem] {
    let sorted = events.sorted { lhs, rhs in
      if lhs.start == rhs.start { return lhs.end < rhs.end }
      return lhs.start < rhs.start
    }
    var items: [CalendarDayLayoutItem] = []

    for cluster in overlappingClusters(for: sorted) {
      let placements = columnPlacements(for: cluster)
      let columnCount = max(1, (placements.map(\.column).max() ?? 0) + 1)

      for placement in placements {
        items.append(
          CalendarDayLayoutItem(
            event: placement.event,
            y: yOffset(for: placement.event),
            height: max(40, durationHeight(for: placement.event)),
            column: placement.column,
            columnCount: columnCount,
            timelineWidth: timelineWidth
          )
        )
      }
    }

    return items.map { item in
      var copy = item
      copy.timelineWidth = timelineWidth
      return copy
    }
  }

  private func yOffset(for event: CalendarEvent) -> CGFloat {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: day)
    let eventStart = max(event.start, startOfDay)
    let minutes = max(0, calendar.dateComponents([.minute], from: startOfDay, to: eventStart).minute ?? 0)
    return CGFloat(minutes) / 60 * hourHeight + 4
  }

  private func durationHeight(for event: CalendarEvent) -> CGFloat {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: day)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? day.addingTimeInterval(86_400)
    let start = max(event.start, startOfDay)
    let end = min(max(event.end, event.start.addingTimeInterval(30 * 60)), endOfDay)
    let minutes = max(30, calendar.dateComponents([.minute], from: start, to: end).minute ?? 30)
    return CGFloat(minutes) / 60 * hourHeight - 4
  }

  private func currentTimeOffset() -> CGFloat {
    let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
    let minutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
    return minutes / 60 * hourHeight + 4
  }

  private func hourLabel(_ hour: Int) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    return formatter.string(from: date)
  }

  private func eventTypeColor(for type: EventType) -> Color {
    switch type {
    case .meeting:
      return WorkspacePalette.accent
    case .interview:
      return WorkspacePalette.warning
    case .deadline:
      return .red
    case .defaultType:
      return WorkspacePalette.accentSoft
    }
  }

  private func overlappingClusters(for events: [CalendarEvent]) -> [[CalendarEvent]] {
    var clusters: [[CalendarEvent]] = []
    var current: [CalendarEvent] = []
    var currentEnd: Date?

    for event in events {
      if let end = currentEnd, event.start < end {
        current.append(event)
        currentEnd = max(end, event.end)
      } else {
        if !current.isEmpty { clusters.append(current) }
        current = [event]
        currentEnd = event.end
      }
    }

    if !current.isEmpty { clusters.append(current) }
    return clusters
  }

  private func columnPlacements(for events: [CalendarEvent]) -> [CalendarColumnPlacement] {
    var columnEnds: [Date] = []
    var placements: [CalendarColumnPlacement] = []

    for event in events {
      let column = columnEnds.firstIndex(where: { $0 <= event.start }) ?? columnEnds.count
      if column == columnEnds.count {
        columnEnds.append(event.end)
      } else {
        columnEnds[column] = event.end
      }
      placements.append(CalendarColumnPlacement(event: event, column: column))
    }

    return placements
  }
}

private struct CalendarColumnPlacement {
  let event: CalendarEvent
  let column: Int
}

private struct CalendarDayLayoutItem: Identifiable {
  let event: CalendarEvent
  let y: CGFloat
  let height: CGFloat
  let column: Int
  var columnCount: Int
  var timelineWidth: CGFloat

  var id: String { event.id }

  var width: CGFloat {
    let gutter = CGFloat(max(0, columnCount - 1)) * 8
    return max(132, (timelineWidth - gutter) / CGFloat(max(1, columnCount)))
  }

  var x: CGFloat {
    CGFloat(column) * (width + 8)
  }
}

private struct CalendarDayEventBlock: View {
  let event: CalendarEvent
  let isHighlighted: Bool
  let compact: Bool
  let onSelect: () -> Void

  var body: some View {
    Button {
      onSelect()
    } label: {
      VStack(alignment: .leading, spacing: compact ? 3 : 5) {
        HStack(spacing: 6) {
          Circle()
            .fill(eventTypeColor(for: event.eventType))
            .frame(width: 7, height: 7)
          Text(event.summary.isEmpty ? "Event" : event.summary)
            .font(.caption.weight(.bold))
            .lineLimit(compact ? 1 : 2)
            .foregroundStyle(.white)
        }

        Text("\(event.start.formatted(.dateTime.hour().minute())) - \(event.end.formatted(.dateTime.hour().minute()))")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(Color.white.opacity(0.72))
          .lineLimit(1)

        if !compact, !event.location.isEmpty {
          Text(event.location)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.62))
            .lineLimit(1)
        }

      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(
        LinearGradient(
          colors: [
            eventTypeColor(for: event.eventType).opacity(0.42),
            WorkspacePalette.panelBase.opacity(0.78),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay(alignment: .leading) {
        Rectangle()
          .fill(eventTypeColor(for: event.eventType))
          .frame(width: 4)
      }
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(isHighlighted ? Color.white.opacity(0.80) : Color.white.opacity(0.12), lineWidth: isHighlighted ? 2 : 1)
      }
      .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
    }
    .buttonStyle(.plain)
  }

  private func eventTypeColor(for type: EventType) -> Color {
    switch type {
    case .meeting:
      return WorkspacePalette.accent
    case .interview:
      return WorkspacePalette.warning
    case .deadline:
      return .red
    case .defaultType:
      return WorkspacePalette.accentSoft
    }
  }
}

private extension CalendarEvent {
  func overlaps(_ other: CalendarEvent) -> Bool {
    start < other.end && other.start < end
  }
}

struct CalendarEventRow: View, Equatable {
  let event: CalendarEvent
  let isHighlighted: Bool
  let onShowDetails: () -> Void

  static func == (lhs: CalendarEventRow, rhs: CalendarEventRow) -> Bool {
    lhs.event == rhs.event && lhs.isHighlighted == rhs.isHighlighted
  }

  var body: some View {
#if os(macOS)
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()))
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
        Text(event.end.formatted(.dateTime.hour().minute()))
          .font(.caption2)
          .foregroundStyle(Color.white.opacity(0.58))
      }
      .frame(width: 64, alignment: .leading)

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(event.summary.isEmpty ? "Event" : event.summary)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)

          Spacer(minLength: 8)

          Circle()
            .fill(eventTypeColor(for: event.eventType))
            .frame(width: 8, height: 8)
        }

        Text(event.whenText)
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.68))
          .lineLimit(1)

        HStack(spacing: 8) {
          if !event.location.isEmpty {
            Text(event.location)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(Color.white.opacity(0.62))
              .lineLimit(1)
          }
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              eventTypeColor(for: event.eventType).opacity(0.08),
              WorkspacePalette.panelBase.opacity(0.58)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(isHighlighted ? eventTypeColor(for: event.eventType).opacity(0.34) : Color.white.opacity(0.06), lineWidth: 1)
    )
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .onTapGesture {
      onShowDetails()
    }
#else
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()))
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Text(event.end.formatted(.dateTime.hour().minute()))
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.58))
        }
        .frame(width: 72, alignment: .leading)

        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top) {
            Text(event.summary.isEmpty ? "Event" : event.summary)
              .font(.headline)
              .foregroundStyle(.white)
              .lineLimit(2)
            Spacer(minLength: 8)
            WorkspaceBadge(text: eventTypeLabel(for: event.eventType), tint: eventTypeColor(for: event.eventType))
          }

          Text(event.whenText)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.68))

          HStack(spacing: 8) {
            if !event.location.isEmpty {
              eventChip(text: event.location, tint: .white, usesNeutralStyle: true)
            }
          }
        }
      }

      HStack(spacing: 8) {
        Button("Details") {
          onShowDetails()
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
      }
    }
    .padding(18)
    .workspaceInteractiveSurface(cornerRadius: 22, tint: eventTypeColor(for: event.eventType))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(isHighlighted ? Color.white : Color.clear, lineWidth: 2)
    }
#endif
  }

  private func eventChip(text: String, tint: Color, usesNeutralStyle: Bool = false) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background((usesNeutralStyle ? Color.white : tint).opacity(usesNeutralStyle ? 0.08 : 0.18))
      .foregroundStyle(usesNeutralStyle ? Color.white.opacity(0.72) : tint)
      .clipShape(Capsule())
  }

  private func eventTypeColor(for type: EventType) -> Color {
    switch type {
    case .meeting:
      return WorkspacePalette.accent
    case .interview:
      return WorkspacePalette.warning
    case .deadline:
      return .red
    case .defaultType:
      return WorkspacePalette.accentSoft
    }
  }

  private func eventTypeLabel(for type: EventType) -> String {
    switch type {
    case .meeting:
      return "Meeting"
    case .interview:
      return "Interview"
    case .deadline:
      return "Deadline"
    case .defaultType:
      return "Event"
    }
  }
}

struct CalendarEventDetailView: View {
  @Environment(\.dismiss) private var dismiss
  let event: CalendarEvent

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        WorkspacePanel(title: event.summary.isEmpty ? "Event" : event.summary, subtitle: event.whenText, tint: eventTypeColor(for: event.eventType), padding: 20) {
          VStack(alignment: .leading, spacing: 12) {
            row("Calendar", event.calendarName)
            row("When", event.whenText)
            row("Location", event.location)
            row("Description", event.description)
            row("Attendees", event.attendees.joined(separator: ", "))
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
    }
    .background(WorkspaceBackground().equatable())
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
      }
    }
  }

  private func row(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value.isEmpty ? "-" : value)
        .font(.subheadline)
        .foregroundStyle(.white)
        .textSelection(.enabled)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .workspaceInteractiveSurface(cornerRadius: 16, tint: .white, raised: false)
  }

  private func eventTypeColor(for type: EventType) -> Color {
    switch type {
    case .meeting:
      return WorkspacePalette.accent
    case .interview:
      return WorkspacePalette.warning
    case .deadline:
      return .red
    case .defaultType:
      return WorkspacePalette.accentSoft
    }
  }
}
