import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var appRouter: AppRouter
  @EnvironmentObject private var dashboardViewModel: DashboardViewModel
  @EnvironmentObject private var stageStore: StageStore
  @EnvironmentObject private var marketNewsStore: MarketNewsStore
  @EnvironmentObject private var calendarStore: CalendarStore
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var googleAuthStore: GoogleAuthStore

  @State private var selectedEvent: CalendarEvent?

  var body: some View {
    NavigationStack {
      ScrollViewReader { scrollProxy in
        GeometryReader { proxy in
          let metrics = WorkspaceLayoutMetrics(width: proxy.size.width)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
              mastheadPanel(width: proxy.size.width, metrics: metrics)
              homeCommandBar
              todayBoard(metrics: metrics)
              supportGrid(metrics: metrics)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.regularPanelPadding)
            .frame(maxWidth: metrics.contentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .top)
          }
        }
        .onAppear {
          focusTargetTodo(using: scrollProxy)
        }
        .onChange(of: appRouter.route.nonce) { _ in
          focusTargetTodo(using: scrollProxy)
        }
        .onChange(of: dashboardViewModel.state.visibleTodos.map(\.id)) { _ in
          focusTargetTodo(using: scrollProxy)
        }
      }
      .background(backgroundView)
      .navigationTitle("Home")
      .safeAreaInset(edge: .bottom) {
        FooterMessageHost(message: footerMessage)
      }
      .task(priority: .utility) {
        await refreshDashboard(force: false)
      }
      .sheet(item: $selectedEvent) { event in
        NavigationStack {
          CalendarEventDetailView(event: event)
            .navigationTitle(event.summary.isEmpty ? "Event" : event.summary)
        }
        .presentationDetents([.medium, .large])
      }
    }
    .instrumentedScreen("DashboardView")
  }

  private func mastheadPanel(width: CGFloat, metrics: WorkspaceLayoutMetrics) -> some View {
    return dashboardPanel(tint: WorkspacePalette.accent, padding: metrics.regularPanelPadding) {
      VStack(alignment: .leading, spacing: 24) {
        if metrics.sizeClass != .compact {
          HStack(alignment: .top, spacing: 24) {
            mastheadCopy(width: width)
            Spacer(minLength: 0)
            mastheadSidePanel(alignment: .trailing, textAlignment: .trailing)
              .frame(width: min(max(width * 0.26, 240), 320), alignment: .trailing)
          }
        } else {
          VStack(alignment: .leading, spacing: 18) {
            mastheadCopy(width: width)
            mastheadSidePanel(alignment: .leading, textAlignment: .leading)
          }
        }

        if metrics.sizeClass == .wide {
          HStack(alignment: .top, spacing: 16) {
            nextEventSpotlight
            nextTodoSpotlight
            snapshotSpotlight
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          VStack(alignment: .leading, spacing: 14) {
            nextEventSpotlight
            nextTodoSpotlight
            snapshotSpotlight
          }
        }
      }
    }
  }

  private var homeCommandBar: some View {
    WorkspaceCommandBar(
      title: "Workspace",
      subtitle: "Refresh quietly, sync when needed, and keep the page focused on what matters today."
    ) {
      Button {
        Task { await refreshDashboard(force: true) }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .buttonStyle(.borderedProminent)
      .tint(WorkspacePalette.accent)

      Button {
        Task { await stageStore.syncFromNotion() }
      } label: {
        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.bordered)

      WorkspaceBadge(
        text: googleAuthStore.isAuthenticated ? "Calendar connected" : "Calendar offline",
        tint: googleAuthStore.isAuthenticated ? WorkspacePalette.success : WorkspacePalette.warning
      )

      WorkspaceBadge(
        text: configStore.config.focusModeEnabled ? "Focus on" : "Focus off",
        tint: configStore.config.focusModeEnabled ? WorkspacePalette.accent : .white
      )
    }
  }

  private func mastheadCopy(width: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Image("DashboardLogo")
        .resizable()
        .scaledToFit()
        .frame(width: width >= 980 ? 86 : 72)
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)

      Text("HOME CONTROL")
        .font(.caption2.weight(.bold))
        .tracking(1.8)
        .foregroundStyle(Color.white.opacity(0.70))

      Text(width >= 980 ? "A cleaner view of\nyour day." : "A cleaner view of your day.")
        .font(.system(size: width >= 1_120 ? 46 : 38, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)

      Text(Date.now.formatted(date: .complete, time: .omitted))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.80))

      Text("The dashboard is now centered on three things only: the next event, the next todo, and a compact operational snapshot.")
        .font(.subheadline)
        .foregroundStyle(Color.white.opacity(0.72))
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func mastheadSidePanel(alignment: HorizontalAlignment, textAlignment: TextAlignment) -> some View {
    VStack(alignment: alignment, spacing: 12) {
      DashboardFocusSessionBadge()
      connectionBadge

      if !calendarStore.statusMessage.isEmpty {
        Text(calendarStore.statusMessage)
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.70))
          .multilineTextAlignment(textAlignment)
      }
    }
  }

  private var nextEventSpotlight: some View {
    spotlightCard(title: "Next event", tint: WorkspacePalette.accent, systemImage: "calendar.badge.clock") {
      if let event = dashboardViewModel.state.nextEvent {
        Text(event.summary.isEmpty ? "Event" : event.summary)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(2)

        Text(event.whenText)
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.70))

        Text(event.location.isEmpty ? event.calendarName : event.location)
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.62))
          .lineLimit(1)
      } else {
        emptySpotlight(
          title: "Agenda not connected",
          message: "Attach Google Calendar or an external iCal feed in Settings."
        )
      }
    }
  }

  private var nextTodoSpotlight: some View {
    spotlightCard(title: "Next todo", tint: WorkspacePalette.warning, systemImage: "checklist") {
      if let todo = nextTodo {
        Text(todo.title)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(2)

        Text(todoSubtitle(for: todo))
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.70))

        if let label = stageLabel(for: todo), !label.isEmpty {
          Text(label)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.62))
            .lineLimit(1)
        }
      } else {
        emptySpotlight(
          title: "Todo queue is clean",
          message: "No pending follow-up is currently waiting in the pipeline."
        )
      }
    }
  }

  private var snapshotSpotlight: some View {
    spotlightCard(title: "Overview", tint: .white, systemImage: "chart.bar.xaxis") {
      VStack(alignment: .leading, spacing: 10) {
        snapshotLine(label: "Upcoming", value: "\(calendarStore.upcomingCount)")
        snapshotLine(label: "Open todos", value: "\(openTodoCount)")
        snapshotLine(label: "Overdue", value: "\(overdueTodoCount)")
        snapshotLine(label: "Queue", value: "\(dashboardViewModel.state.pendingQueueCount)")
      }
    }
  }

  private func todayBoard(metrics: WorkspaceLayoutMetrics) -> some View {
    dashboardPanel(
      title: "Today board",
      subtitle: "Agenda and tasks stay side by side so the next move is always visible.",
      tint: WorkspacePalette.warning,
      padding: metrics.regularPanelPadding
    ) {
      if metrics.sizeClass == .wide {
        HStack(alignment: .top, spacing: 22) {
          agendaColumn
            .workspaceAlignedCard(minHeight: 420)
          splitDivider(isVertical: true)
          todoColumn
            .workspaceAlignedCard(minHeight: 420)
        }
      } else {
        VStack(alignment: .leading, spacing: 20) {
          agendaColumn
          splitDivider(isVertical: false)
          todoColumn
        }
      }
    }
  }

  private var agendaColumn: some View {
    VStack(alignment: .leading, spacing: 14) {
      boardHeader(
        title: "Agenda",
        subtitle: "Upcoming calendar events",
        accent: WorkspacePalette.accent,
        countText: "\(dashboardViewModel.state.upcomingEvents.count)"
      )

      if calendarStore.isLoading {
        ProgressView("Loading events...")
          .tint(WorkspacePalette.accent)
      } else if dashboardViewModel.state.upcomingEvents.isEmpty {
        emptyState(
          title: "No upcoming event",
          message: googleAuthStore.isAuthenticated || !configStore.config.externalIcalUrl.isEmpty
            ? "Refresh the calendar or adjust the connected sources in Settings."
            : "Connect Google Calendar or add an external iCal URL in Settings."
        )
      } else {
        let events = dashboardViewModel.state.upcomingEvents
        ForEach(events) { event in
          agendaTimelineRow(event, isLast: event.id == events.last?.id)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var todoColumn: some View {
    VStack(alignment: .leading, spacing: 14) {
      boardHeader(
        title: "Todo",
        subtitle: "Deadlines and pipeline follow-ups",
        accent: WorkspacePalette.warning,
        countText: "\(openTodoCount) open"
      )

      if dashboardViewModel.state.visibleTodos.isEmpty {
        emptyState(
          title: "No todo item",
          message: "Automation todos will appear here when stages move through the pipeline."
        )
      } else {
        let todos = visibleTodos
        ForEach(todos) { todo in
          todoQueueRow(
            todo,
            isLast: todo.id == todos.last?.id,
            isHighlighted: isTodoHighlighted(todo.id)
          )
          .id(todoRowID(todo.id))
        }
      }
    }
    .id("home-todo-section")
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func supportGrid(metrics: WorkspaceLayoutMetrics) -> some View {
    LazyVGrid(columns: supportColumns(for: metrics), alignment: .leading, spacing: metrics.panelGap) {
      overviewPanel
      marketsPanel
      newsPanel
    }
  }

  private var overviewPanel: some View {
    let kpi = dashboardViewModel.state.weeklyKPI

    return dashboardPanel(title: "Pipeline overview", subtitle: "Status distribution and weekly cadence", tint: WorkspacePalette.accentSoft) {
      VStack(alignment: .leading, spacing: 16) {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
          compactMetric(title: "Open", value: "\(count(for: .open))", tint: statusColor(.open))
          compactMetric(title: "Applied", value: "\(count(for: .applied))", tint: statusColor(.applied))
          compactMetric(title: "Interview", value: "\(count(for: .interview))", tint: statusColor(.interview))
          compactMetric(title: "Rejected", value: "\(count(for: .rejected))", tint: statusColor(.rejected))
        }

        subtleDivider

        VStack(alignment: .leading, spacing: 10) {
      overviewLine(label: "Added this week", value: "\(kpi.addedCount)")
      overviewLine(label: "Applied this week", value: "\(kpi.appliedCount)")
      overviewLine(label: "Pending queue", value: "\(dashboardViewModel.state.pendingQueueCount)")
        }

        VStack(alignment: .leading, spacing: 8) {
          ForEach(kpi.progressByStatus, id: \.status) { item in
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(item.status.rawValue)
                  .font(.caption.weight(.semibold))
                Spacer()
                Text("\(item.count) · \(Int(item.ratio * 100))%")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              GeometryReader { proxy in
                ZStack(alignment: .leading) {
                  Capsule()
                    .fill(Color.white.opacity(0.08))
                  Capsule()
                    .fill(statusColor(item.status).opacity(0.85))
                    .frame(width: max(proxy.size.width * item.ratio, item.count == 0 ? 0 : 10))
                }
              }
              .frame(height: 8)
            }
          }
        }
      }
    }
    .workspaceAlignedCard(minHeight: 390)
  }

  private var marketsPanel: some View {
    dashboardPanel(title: "Markets", subtitle: "Configured symbols from Yahoo Finance", tint: WorkspacePalette.success) {
      VStack(alignment: .leading, spacing: 12) {
        if marketNewsStore.quotes.isEmpty {
          Text(marketNewsStore.isLoadingQuotes ? "Loading quotes..." : "No market quote available.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(marketNewsStore.quotes.prefix(5)) { quote in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(quote.shortName)
                  .font(.subheadline.weight(.semibold))
                Text(quote.symbol)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f", quote.price))
                  .font(.subheadline.weight(.bold))
                Text(String(format: "%+.2f%%", quote.changePercent))
                  .font(.caption)
                  .foregroundStyle(quote.changePercent >= 0 ? WorkspacePalette.success : Color.red)
              }
            }
            .padding(.vertical, 3)
          }
        }
      }
    }
    .workspaceAlignedCard(minHeight: 390)
  }

  private var newsPanel: some View {
    DashboardNewsPanel()
  }

  private func agendaTimelineRow(_ event: CalendarEvent, isLast: Bool) -> some View {
    Button {
      selectedEvent = event
    } label: {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(event.start.formatted(.dateTime.weekday(.abbreviated)))
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.white.opacity(0.64))
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
            Text(eventTypeLabel(for: event.eventType))
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 9)
              .padding(.vertical, 5)
              .background(eventTypeColor(for: event.eventType).opacity(0.20))
              .foregroundStyle(eventTypeColor(for: event.eventType))
              .clipShape(Capsule())
          }

          Text(event.whenText)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.68))

          HStack(spacing: 8) {
            if !event.calendarName.isEmpty {
              detailChip(text: event.calendarName, tint: WorkspacePalette.accent)
            }
            if !event.location.isEmpty {
              detailChip(text: event.location, tint: .white, usesNeutralStyle: true)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 6)
      .overlay(alignment: .bottom) {
        if !isLast {
          Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 86)
        }
      }
    }
    .buttonStyle(.plain)
  }

  private func todoQueueRow(_ todo: TodoItem, isLast: Bool, isHighlighted: Bool) -> some View {
    let isOverdue = todo.status != .done && todo.dueDate < Calendar.current.startOfDay(for: Date())

    return HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text(todo.dueDate.formatted(.dateTime.day().month(.abbreviated)))
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .foregroundStyle(isOverdue ? Color.red : Color.white)
        Text(todo.status == .done ? "Closed" : (isOverdue ? "Overdue" : "Due"))
          .font(.caption2.weight(.bold))
          .foregroundStyle(isOverdue ? Color.red : Color.white.opacity(0.64))
      }
      .frame(width: 72, alignment: .leading)

      VStack(alignment: .leading, spacing: 6) {
        Text(todo.title)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(2)

        Text(todoSubtitle(for: todo))
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.68))

        if let label = stageLabel(for: todo), !label.isEmpty {
          detailChip(text: label, tint: WorkspacePalette.warning)
        }
      }

      Spacer(minLength: 10)

      Menu {
        ForEach(TodoStatus.allCases) { status in
          Button(status.rawValue) {
            stageStore.setTodoStatus(todoID: todo.id, status: status)
          }
        }
      } label: {
        Text(todo.status.rawValue)
          .font(.caption.weight(.bold))
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(todoStatusColor(todo.status).opacity(0.18))
          .foregroundStyle(todoStatusColor(todo.status))
          .clipShape(Capsule())
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(isHighlighted ? Color.white.opacity(0.06) : Color.clear)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(isHighlighted ? WorkspacePalette.warning.opacity(0.28) : Color.clear, lineWidth: 1.5)
    }
    .overlay(alignment: .bottom) {
      if !isLast {
        Rectangle()
          .fill(Color.white.opacity(0.08))
          .frame(height: 1)
          .padding(.leading, 86)
      }
    }
  }

  private var connectionBadge: some View {
    HStack(spacing: 8) {
      Image(systemName: calendarConnectionSymbol)
      Text(calendarConnectionText)
        .font(.caption.weight(.semibold))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.10))
    .foregroundStyle(Color.white.opacity(0.78))
    .clipShape(Capsule())
  }

  private func spotlightCard<Content: View>(
    title: String,
    tint: Color,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .foregroundStyle(tint)
        Text(title)
          .font(.caption.weight(.bold))
          .foregroundStyle(Color.white.opacity(0.72))
      }

      content()
    }
    .padding(18)
    .workspaceAlignedCard(minHeight: 166)
    .workspaceInteractiveSurface(cornerRadius: 22, tint: tint, raised: false)
  }

  private func emptySpotlight(title: String, message: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
      Text(message)
        .font(.caption)
        .foregroundStyle(Color.white.opacity(0.68))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func snapshotLine(label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(.caption)
        .foregroundStyle(Color.white.opacity(0.68))
      Spacer()
      Text(value)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
    }
  }

  private func boardHeader(title: String, subtitle: String, accent: Color, countText: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.68))
      }
      Spacer()
      Text(countText)
        .font(.caption.weight(.bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(accent.opacity(0.20))
        .foregroundStyle(accent)
        .clipShape(Capsule())
    }
  }

  private func detailChip(text: String, tint: Color, usesNeutralStyle: Bool = false) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background((usesNeutralStyle ? Color.white : tint).opacity(usesNeutralStyle ? 0.08 : 0.18))
      .foregroundStyle(usesNeutralStyle ? Color.white.opacity(0.72) : tint)
      .clipShape(Capsule())
  }

  private func compactMetric(title: String, value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title3.weight(.bold))
        .foregroundStyle(tint)
    }
    .padding(14)
    .workspaceAlignedCard(minHeight: 88)
    .workspaceInteractiveSurface(cornerRadius: 16, tint: tint, raised: false)
  }

  private func overviewLine(label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.subheadline.weight(.semibold))
    }
  }

  private func emptyState(title: String, message: String) -> some View {
    WorkspaceEmptyState(title: title, message: message, tint: .teal)
  }

  private func dashboardPanel<Content: View>(
    title: String? = nil,
    subtitle: String? = nil,
    tint: Color = .teal,
    padding: CGFloat = 24,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      if let title {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
          if let subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(Color.white.opacity(0.66))
          }
        }
      }

      content()
    }
    .padding(padding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .workspaceInteractiveSurface(cornerRadius: 32, tint: tint)
  }

  private func splitDivider(isVertical: Bool) -> some View {
    Rectangle()
      .fill(Color.white.opacity(0.08))
      .frame(width: isVertical ? 1 : nil, height: isVertical ? nil : 1)
  }

  private var subtleDivider: some View {
    Rectangle()
      .fill(Color.white.opacity(0.08))
      .frame(height: 1)
  }

  private func supportColumns(for metrics: WorkspaceLayoutMetrics) -> [GridItem] {
    if metrics.sizeClass == .wide {
      return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }
    if metrics.sizeClass == .medium {
      return [GridItem(.flexible()), GridItem(.flexible())]
    }
    return [GridItem(.flexible())]
  }

  private func stageLabel(for todo: TodoItem) -> String? {
    dashboardViewModel.state.stageLabelsByTodoID[todo.id]
  }

  private func todoSubtitle(for todo: TodoItem) -> String {
    let prefix = todo.dueDate < Calendar.current.startOfDay(for: Date()) && todo.status != .done ? "Overdue" : "Due"
    return "\(prefix): \(todo.dueDate.shortDate)"
  }

  private func count(for status: StageStatus) -> Int {
    dashboardViewModel.state.statusCounts[status] ?? 0
  }

  private func statusColor(_ status: StageStatus) -> Color {
    switch status {
    case .open:
      return WorkspacePalette.accent
    case .applied:
      return WorkspacePalette.success
    case .interview:
      return WorkspacePalette.warning
    case .rejected:
      return .red
    }
  }

  private func todoStatusColor(_ status: TodoStatus) -> Color {
    switch status {
    case .notStarted:
      return WorkspacePalette.warning
    case .inProgress:
      return WorkspacePalette.accent
    case .done:
      return WorkspacePalette.success
    }
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

  private var nextTodo: TodoItem? {
    dashboardViewModel.state.nextTodo
  }

  private var visibleTodos: [TodoItem] {
    dashboardViewModel.state.visibleTodos
  }

  private var openTodoCount: Int {
    dashboardViewModel.state.openTodoCount
  }

  private var overdueTodoCount: Int {
    dashboardViewModel.state.overdueTodoCount
  }

  private var calendarConnectionText: String {
    if googleAuthStore.isAuthenticated {
      return "Google Calendar live"
    }
    if !configStore.config.externalIcalUrl.isEmpty {
      return "External iCal connected"
    }
    return "Calendar source missing"
  }

  private var calendarConnectionSymbol: String {
    if googleAuthStore.isAuthenticated || !configStore.config.externalIcalUrl.isEmpty {
      return "point.3.connected.trianglepath.dotted"
    }
    return "wifi.slash"
  }

  private var backgroundView: some View {
    WorkspaceBackground().equatable()
  }

  private var footerMessage: String? {
    if !stageStore.syncMessage.isEmpty {
      return stageStore.syncMessage
    }
    if !calendarStore.statusMessage.isEmpty {
      return calendarStore.statusMessage
    }
    return nil
  }

  private func focusTargetTodo(using proxy: ScrollViewProxy) {
    guard appRouter.destination == .home else { return }
    guard let todoID = appRouter.route.todoID else { return }
    let targetID = visibleTodos.contains(where: { $0.id == todoID }) ? todoRowID(todoID) : "home-todo-section"
    withAnimation(.snappy(duration: 0.26)) {
      proxy.scrollTo(targetID, anchor: .center)
    }
  }

  private func isTodoHighlighted(_ todoID: String) -> Bool {
    appRouter.destination == .home && appRouter.route.todoID == todoID
  }

  private func todoRowID(_ todoID: String) -> String {
    "home-todo-\(todoID)"
  }

  private func refreshDashboard(force: Bool) async {
    if force {
      await calendarStore.loadCombinedEvents(icalURL: configStore.config.externalIcalUrl)
      await marketNewsStore.refreshAll()
      return
    }

    await calendarStore.prepareForLaunch(icalURL: configStore.config.externalIcalUrl)
    await marketNewsStore.prepareForLaunch()
  }
}

private struct DashboardFocusSessionBadge: View {
  @EnvironmentObject private var focusStore: FocusStore

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: focusStore.isEnabled ? "timer" : "moon.zzz")
      Text(focusStore.isEnabled ? "\(focusStore.focusSummary) · \(max(0, focusStore.remainingSeconds / 60))m left" : "Focus off")
        .font(.caption.weight(.semibold))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background((focusStore.isEnabled ? WorkspacePalette.accent : Color.white).opacity(0.12))
    .foregroundStyle(focusStore.isEnabled ? WorkspacePalette.accentSoft : Color.white.opacity(0.74))
    .clipShape(Capsule())
  }
}

private struct DashboardNewsPanel: View {
  @EnvironmentObject private var marketNewsStore: MarketNewsStore

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("News")
          .font(.headline.weight(.semibold))
          .foregroundStyle(.white)
        Text("Headlines that may affect the market context")
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.66))
      }

      VStack(alignment: .leading, spacing: 12) {
        if marketNewsStore.news.isEmpty {
          Text(marketNewsStore.isLoadingNews ? "Loading headlines..." : "No headline available.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(marketNewsStore.news.prefix(4)) { item in
            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                  .font(.subheadline.weight(.semibold))
                  .lineLimit(3)
                Text("\(item.source) · \(item.publishedAt.shortDateTime)")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              ProtectedLinkButton(title: "Open", systemImage: "link", urlString: item.link, tint: WorkspacePalette.accent)
            }
            .padding(.vertical, 2)
          }
        }
      }
    }
    .padding(24)
    .workspaceAlignedCard(minHeight: 390)
    .workspaceInteractiveSurface(cornerRadius: 32, tint: WorkspacePalette.accent)
  }
}
