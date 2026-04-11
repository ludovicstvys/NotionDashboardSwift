import SwiftUI

struct CalendarView: View {
  @EnvironmentObject private var calendarStore: CalendarStore
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var googleAuthStore: GoogleAuthStore
  @EnvironmentObject private var notificationScheduler: NotificationScheduler
  @State private var iCalURL: String = ""
  @State private var selectedEvent: CalendarEvent?
  @State private var showCreateGoogleEvent = false

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            heroPanel(width: proxy.size.width)
            actionBar
            connectionPanel
            eventFeedPanel
          }
          .padding(.horizontal, horizontalPadding(for: proxy.size.width))
          .padding(.vertical, 28)
          .frame(maxWidth: 1_440)
          .frame(maxWidth: .infinity, alignment: .top)
        }
      }
      .background(WorkspaceBackground())
      .navigationTitle("Calendar")
      .animation(.snappy(duration: 0.26), value: calendarStore.events.count)
      .animation(.snappy(duration: 0.26), value: calendarStore.googleCalendars.count)
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
  }

  private var actionBar: some View {
    WorkspaceCommandBar(
      title: "Flow",
      subtitle: "Keep source refresh, calendar loading, and event creation close to the feed."
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
      .tint(.teal)

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

      WorkspaceBadge(text: "\(groupedEvents.count) days", tint: .blue)
    }
  }

  private func heroPanel(width: CGFloat) -> some View {
    WorkspacePanel(tint: .teal, padding: width >= 900 ? 28 : 22) {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 12) {
            Text("CALENDAR CONTROL")
              .font(.caption2.weight(.bold))
              .tracking(2.4)
              .foregroundStyle(Color.white.opacity(0.70))

            Text("Connections, reminders,\nand event flow.")
              .font(.system(size: width >= 1_120 ? 44 : 36, weight: .bold, design: .serif))
              .foregroundStyle(.white)
              .fixedSize(horizontal: false, vertical: true)

            Text("Calendar now follows the same language as Home: connection state first, then the events that matter, grouped by day and easier to scan.")
              .font(.subheadline)
              .foregroundStyle(Color.white.opacity(0.72))
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)

          VStack(alignment: .trailing, spacing: 10) {
            WorkspaceBadge(text: googleAuthStore.isAuthenticated ? "Google live" : "Google off", tint: googleAuthStore.isAuthenticated ? .green : .orange)
            WorkspaceBadge(text: notificationStatusText, tint: .pink)
          }
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
          calendarMetric(title: "Upcoming", value: "\(upcomingCount)", detail: "next items ahead", tint: .teal)
          calendarMetric(title: "Today", value: "\(todayCount)", detail: "scheduled today", tint: .blue)
          calendarMetric(title: "Sources", value: "\(sourceCount)", detail: sourceCount == 0 ? "none connected" : "active feeds", tint: .orange)
          calendarMetric(title: "Alerts", value: notificationCountLabel, detail: "notification permission", tint: .pink)
        }
      }
    }
  }

  private var connectionPanel: some View {
    WorkspacePanel(
      title: "Connections and actions",
      subtitle: "Google auth, calendar filtering, reminder authorization, and iCal loading live in the same control surface.",
      tint: .orange
    ) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 10) {
          Button(googleAuthStore.isAuthenticated ? "Reconnect Google" : "Connect Google") {
            Task { await googleAuthStore.signInInteractive() }
          }
          .buttonStyle(.borderedProminent)
          .tint(.teal)

          Button("Disconnect") {
            googleAuthStore.signOut()
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
            .tint(.orange)

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
                  calendarStore.setCalendarSelected(calendarID: cal.id, isSelected: !selected)
                } label: {
                  Text(cal.name)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selected ? Color.teal.opacity(0.20) : Color.white.opacity(0.08))
                    .foregroundStyle(selected ? Color.teal : Color.white.opacity(0.76))
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
      subtitle: "Grouped by day, with the same visual hierarchy as the rest of the workspace.",
      tint: .blue
    ) {
      if calendarStore.isLoading {
        ProgressView("Loading calendar events...")
          .tint(.teal)
      } else if groupedEvents.isEmpty {
        calendarEmptyState(
          title: "No event loaded",
          message: "Connect Google Calendar or load an external iCal source to populate the feed."
        )
      } else {
        LazyVStack(spacing: 18) {
          ForEach(groupedEvents, id: \.day) { group in
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                  .font(.headline)
                  .foregroundStyle(.white)
                Spacer()
                WorkspaceBadge(text: "\(group.items.count)", tint: .blue)
              }

              VStack(spacing: 12) {
                ForEach(group.items) { event in
                  CalendarEventRow(event: event) {
                    selectedEvent = event
                  }
                }
              }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .workspaceInteractiveSurface(cornerRadius: 24, tint: .blue, raised: false)
          }
        }
      }
    }
  }

  private func calendarMetric(title: String, value: String, detail: String, tint: Color) -> some View {
    WorkspaceMetricTile(title: title, value: value, detail: detail, tint: tint)
  }

  private func calendarEmptyState(title: String, message: String) -> some View {
    WorkspaceEmptyState(title: title, message: message, tint: .blue, systemImage: "calendar.badge.exclamationmark")
  }

  private func horizontalPadding(for width: CGFloat) -> CGFloat {
    width >= 900 ? 28 : 18
  }

  private var groupedEvents: [(day: Date, items: [CalendarEvent])] {
    let grouped = Dictionary(grouping: calendarStore.events) { event in
      Calendar.current.startOfDay(for: event.start)
    }
    return grouped.keys.sorted().map { day in
      let items = (grouped[day] ?? []).sorted { $0.start < $1.start }
      return (day: day, items: items)
    }
  }

  private var upcomingCount: Int {
    let now = Date()
    return calendarStore.events.filter { $0.end >= now }.count
  }

  private var todayCount: Int {
    let calendar = Calendar.current
    return calendarStore.events.filter { calendar.isDateInToday($0.start) }.count
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

struct CalendarEventRow: View {
  let event: CalendarEvent
  let onShowDetails: () -> Void
  @Environment(\.openURL) private var openURL
  @EnvironmentObject private var focusStore: FocusStore
  @State private var blockedMessage: String = ""

  var body: some View {
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
          Button {
            guard let url = URL(string: event.sourceUrl) else { return }
            if focusStore.isBlocked(url: url) {
              blockedMessage = focusStore.blockedReason(for: url)
              return
            }
            openURL(url)
          } label: {
            Label("Open", systemImage: "link")
          }
          .font(.caption.weight(.semibold))
          .buttonStyle(.bordered)
          .tint(.teal)
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
    .alert("Blocked", isPresented: Binding(get: { !blockedMessage.isEmpty }, set: { if !$0 { blockedMessage = "" } })) {
      Button("OK", role: .cancel) { blockedMessage = "" }
    } message: {
      Text(blockedMessage)
    }
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
      return .teal
    case .interview:
      return .orange
    case .deadline:
      return .red
    case .defaultType:
      return .blue
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
  @Environment(\.openURL) private var openURL
  @EnvironmentObject private var focusStore: FocusStore
  @State private var blockedMessage: String = ""

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
            Button("Open source") {
              guard let url = URL(string: event.sourceUrl) else { return }
              if focusStore.isBlocked(url: url) {
                blockedMessage = focusStore.blockedReason(for: url)
                return
              }
              openURL(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
          }
          if !event.meetingLink.isEmpty {
            Button("Open meeting") {
              guard let url = URL(string: event.meetingLink) else { return }
              if focusStore.isBlocked(url: url) {
                blockedMessage = focusStore.blockedReason(for: url)
                return
              }
              openURL(url)
            }
            .buttonStyle(.bordered)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
    }
    .background(WorkspaceBackground())
    .alert("Blocked", isPresented: Binding(get: { !blockedMessage.isEmpty }, set: { if !$0 { blockedMessage = "" } })) {
      Button("OK", role: .cancel) { blockedMessage = "" }
    } message: {
      Text(blockedMessage)
    }
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
