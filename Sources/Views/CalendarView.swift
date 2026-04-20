import SwiftUI

struct CalendarView: View {
  @EnvironmentObject private var appRouter: AppRouter
  @EnvironmentObject private var calendarViewModel: CalendarViewModel
  @EnvironmentObject private var calendarStore: CalendarStore
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var googleAuthStore: GoogleAuthStore
  @EnvironmentObject private var notificationScheduler: NotificationScheduler
  @State private var iCalURL: String = ""
  @State private var selectedEvent: CalendarEvent?
  @State private var showCreateGoogleEvent = false

  var body: some View {
    NavigationStack {
      ScrollViewReader { scrollProxy in
        GeometryReader { proxy in
          let metrics = WorkspaceLayoutMetrics(width: proxy.size.width)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
              heroPanel(width: proxy.size.width, metrics: metrics)
              actionBar
              connectionPanel
              eventFeedPanel
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
    .instrumentedScreen("CalendarView")
  }

  private var actionBar: some View {
    WorkspaceCommandBar(
      title: "Calendar",
      subtitle: "Refresh sources, reconnect accounts, and create events from a single control bar."
    ) {
      Button {
        Task {
          await calendarStore.loadGoogleCalendars(force: true)
          await calendarStore.loadCombinedEvents(icalURL: iCalURL)
        }
      } label: {
        Label("Refresh feed", systemImage: "arrow.clockwise")
      }
      .buttonStyle(.borderedProminent)
      .tint(WorkspacePalette.accent)

      Button {
        Task { await googleAuthStore.signInInteractive() }
      } label: {
        Label(googleAuthStore.isAuthenticated ? "Reconnect" : "Connect", systemImage: "person.crop.circle.badge.checkmark")
      }
      .buttonStyle(.bordered)

      Button {
        showCreateGoogleEvent = true
      } label: {
        Label("Create event", systemImage: "plus.circle.fill")
      }
      .buttonStyle(.bordered)

      WorkspaceBadge(text: "\(calendarViewModel.state.groupedEvents.count) days", tint: WorkspacePalette.accentSoft)
    }
  }

  private func heroPanel(width: CGFloat, metrics: WorkspaceLayoutMetrics) -> some View {
    WorkspacePanel(tint: WorkspacePalette.accent, padding: metrics.regularPanelPadding) {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 12) {
            Text("CALENDAR")
              .font(.caption2.weight(.bold))
              .tracking(1.8)
              .foregroundStyle(Color.white.opacity(0.70))

            Text("Events, sources,\nand timing.")
              .font(.system(size: width >= 1_120 ? 42 : 34, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)
              .fixedSize(horizontal: false, vertical: true)

            Text("The calendar page is now cleaner and more operational: source state first, then the upcoming timeline grouped by day.")
              .font(.subheadline)
              .foregroundStyle(Color.white.opacity(0.72))
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)

          VStack(alignment: .trailing, spacing: 10) {
            WorkspaceBadge(text: googleAuthStore.isAuthenticated ? "Google connected" : "Google offline", tint: googleAuthStore.isAuthenticated ? WorkspacePalette.success : WorkspacePalette.warning)
            WorkspaceBadge(text: notificationStatusText, tint: .white)
          }
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
          calendarMetric(title: "Upcoming", value: "\(calendarViewModel.state.upcomingCount)", detail: "next items ahead", tint: WorkspacePalette.accent)
          calendarMetric(title: "Today", value: "\(calendarViewModel.state.todayCount)", detail: "scheduled today", tint: WorkspacePalette.accentSoft)
          calendarMetric(title: "Sources", value: "\(sourceCount)", detail: sourceCount == 0 ? "none connected" : "active feeds", tint: WorkspacePalette.warning)
          calendarMetric(title: "Alerts", value: notificationCountLabel, detail: "notification permission", tint: .white)
        }
      }
    }
  }

  private var connectionPanel: some View {
    WorkspacePanel(
      title: "Connections and sources",
      subtitle: "Manage Google auth, filters, notifications, and external calendars from one place.",
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
          TextField("https://.../agenda/ical/...", text: $iCalURL)
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
                  Text(cal.name)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selected ? WorkspacePalette.accent.opacity(0.20) : Color.white.opacity(0.08))
                    .foregroundStyle(selected ? WorkspacePalette.accentSoft : Color.white.opacity(0.76))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        if !googleAuthStore.statusMessage.isEmpty || !calendarStore.statusMessage.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text(googleAuthStore.statusMessage)
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

  private var eventFeedPanel: some View {
    WorkspacePanel(
      title: "Event feed",
      subtitle: "A grouped timeline of what is coming next, optimized for scanning.",
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
#if os(macOS)
        List {
          ForEach(calendarViewModel.state.groupedEvents) { group in
            Section {
              ForEach(group.items) { event in
                CalendarEventRow(event: event, isHighlighted: isEventHighlighted(event.id)) {
                  selectedEvent = event
                }
                .equatable()
                .id(eventRowID(event.id))
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
              }
            } header: {
              HStack {
                Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                  .font(.headline)
                  .foregroundStyle(.white)
                Spacer()
                WorkspaceBadge(text: "\(group.items.count)", tint: WorkspacePalette.accentSoft)
              }
              .padding(.top, 6)
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 520)
#else
        LazyVStack(spacing: 18) {
          ForEach(calendarViewModel.state.groupedEvents) { group in
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                  .font(.headline)
                  .foregroundStyle(.white)
                Spacer()
                WorkspaceBadge(text: "\(group.items.count)", tint: WorkspacePalette.accentSoft)
              }

              VStack(spacing: 12) {
                ForEach(group.items) { event in
                  CalendarEventRow(event: event, isHighlighted: isEventHighlighted(event.id)) {
                    selectedEvent = event
                  }
                  .equatable()
                  .id(eventRowID(event.id))
                }
              }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .workspaceInteractiveSurface(cornerRadius: 24, tint: WorkspacePalette.accentSoft, raised: false)
          }
        }
#endif
      }
    }
    .id("calendar-event-feed")
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
      Form {
        TextField("Summary", text: $summary)
        TextField("Location", text: $location)
        TextField("Description", text: $description, axis: .vertical)
          .lineLimit(3...8)
        DatePicker("Start", selection: $start)
        DatePicker("End", selection: $end)
      }
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
          if !event.calendarName.isEmpty {
            Text(event.calendarName)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(Color.teal)
              .lineLimit(1)
          }
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
        .fill(WorkspacePalette.panelBase.opacity(0.58))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(isHighlighted ? Color.white.opacity(0.18) : Color.white.opacity(0.06), lineWidth: 1)
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
            if !event.calendarName.isEmpty {
              eventChip(text: event.calendarName, tint: .teal)
            }
            if !event.location.isEmpty {
              eventChip(text: event.location, tint: .white, usesNeutralStyle: true)
            }
          }
        }
      }

      HStack(spacing: 8) {
        if !event.sourceUrl.isEmpty {
          ProtectedLinkButton(title: "Open", systemImage: "link", urlString: event.sourceUrl, tint: .teal)
        }

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
  let event: CalendarEvent

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        row("Calendar", event.calendarName)
        row("When", event.whenText)
        row("Location", event.location)
        row("Description", event.description)
        row("Attendees", event.attendees.joined(separator: ", "))
        row("Source", event.sourceUrl)
        row("Meeting", event.meetingLink)

        HStack(spacing: 8) {
          if !event.sourceUrl.isEmpty {
            ProtectedLinkButton(title: "Open source", systemImage: "link", urlString: event.sourceUrl, tint: .teal)
          }
          if !event.meetingLink.isEmpty {
            ProtectedLinkButton(title: "Open meeting", systemImage: "link", urlString: event.meetingLink, tint: .white)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
    }
    .background(WorkspaceBackground().equatable())
  }

  private func row(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value.isEmpty ? "-" : value)
        .font(.subheadline)
        .textSelection(.enabled)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(WorkspacePalette.innerCard)
    )
  }
}
