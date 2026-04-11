import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var stageStore: StageStore
  @EnvironmentObject private var marketNewsStore: MarketNewsStore
  @EnvironmentObject private var focusStore: FocusStore
  @EnvironmentObject private var calendarStore: CalendarStore
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var googleAuthStore: GoogleAuthStore
  @Environment(\.openURL) private var openURL

  @State private var blockedMessage: String = ""
  @State private var selectedEvent: CalendarEvent?

  private let splitBoardThreshold: CGFloat = 1_040
  private let supportGridThreshold: CGFloat = 1_240

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            mastheadPanel(width: proxy.size.width)
            homeCommandBar
            todayBoard(width: proxy.size.width)
            supportGrid(width: proxy.size.width)
          }
          .padding(.horizontal, horizontalPadding(for: proxy.size.width))
          .padding(.vertical, 28)
          .frame(maxWidth: 1_440)
          .frame(maxWidth: .infinity, alignment: .top)
        }
      }
      .background(backgroundView)
      .navigationTitle("Home")
      .task(priority: .utility) {
        await refreshDashboard(force: false)
      }
      .animation(.snappy(duration: 0.26), value: calendarStore.events.count)
      .animation(.snappy(duration: 0.26), value: stageStore.stages.count)
      .animation(.snappy(duration: 0.26), value: marketNewsStore.news.count)
      .sheet(item: $selectedEvent) { event in
        NavigationStack {
          CalendarEventDetailView(event: event)
            .navigationTitle(event.summary.isEmpty ? "Event" : event.summary)
        }
        .presentationDetents([.medium, .large])
      }
      .alert(
        "Blocked",
        isPresented: Binding(
          get: { !blockedMessage.isEmpty },
          set: { if !$0 { blockedMessage = "" } }
        )
      ) {
        Button("OK", role: .cancel) { blockedMessage = "" }
      } message: {
        Text(blockedMessage)
      }
    }
  }

  private func mastheadPanel(width: CGFloat) -> some View {
    dashboardPanel(tint: .teal, padding: width >= 900 ? 28 : 22) {
      VStack(alignment: .leading, spacing: 22) {
        if width >= 900 {
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

        if width >= 960 {
          HStack(alignment: .top, spacing: 16) {
            nextEventSpotlight
            nextTodoSpotlight
            snapshotSpotlight
          }
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
      title: "Now",
      subtitle: "Keep the command loop short: refresh, sync, and watch the live state."
    ) {
      Button {
        Task { await refreshDashboard(force: true) }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .buttonStyle(.borderedProminent)
      .tint(.teal)

      Button {
        Task { await stageStore.syncFromNotion() }
      } label: {
        Label("Sync stages", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.bordered)

      WorkspaceBadge(
        text: googleAuthStore.isAuthenticated ? "Calendar live" : "Calendar idle",
        tint: googleAuthStore.isAuthenticated ? .green : .orange
      )

      WorkspaceBadge(
        text: focusStore.isEnabled ? "Focus on" : "Focus off",
        tint: focusStore.isEnabled ? .teal : .white
      )
    }
  }

  private func mastheadCopy(width: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("HOME CONTROL")
        .font(.caption2.weight(.bold))
        .tracking(2.4)
        .foregroundStyle(Color.white.opacity(0.70))

      Text(width >= 980 ? "Run the day,\nnot the backlog." : "Run the day, not the backlog.")
        .font(.system(size: width >= 1_120 ? 50 : 40, weight: .bold, design: .serif))
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)

      Text(Date.now.formatted(date: .complete, time: .omitted))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.80))

      Text("The first screen now behaves like a control room: agenda on one side, todo on the other, and the pipeline signals underneath.")
        .font(.subheadline)
        .foregroundStyle(Color.white.opacity(0.72))
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func mastheadSidePanel(alignment: HorizontalAlignment, textAlignment: TextAlignment) -> some View {
    VStack(alignment: alignment, spacing: 12) {
      focusBadge
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
    spotlightCard(title: "Next event", tint: .teal, systemImage: "calendar.badge.clock") {
      if let event = upcomingEvents.first {
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
    spotlightCard(title: "Next todo", tint: .orange, systemImage: "checklist") {
      if let todo = nextTodo {
        Text(todo.title)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(2)

        Text(todoSubtitle(for: todo))
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.70))

        if let stage = stageForTodo(todo) {
          Text(stage.displayLabel)
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
    spotlightCard(title: "Today snapshot", tint: .pink, systemImage: "chart.line.uptrend.xyaxis") {
      VStack(alignment: .leading, spacing: 10) {
        snapshotLine(label: "Upcoming", value: "\(upcomingEvents.count)")
        snapshotLine(label: "Open todos", value: "\(openTodoCount)")
        snapshotLine(label: "Overdue", value: "\(overdueTodoCount)")
        snapshotLine(label: "Blockers", value: "\(stageStore.blockers.count)")
      }
    }
  }

  private func todayBoard(width: CGFloat) -> some View {
    dashboardPanel(
      title: "Today board",
      subtitle: "Agenda and todo share the same split-screen so the next moves are visible at a glance.",
      tint: .orange,
      padding: width >= 900 ? 28 : 22
    ) {
      if width >= splitBoardThreshold {
        HStack(alignment: .top, spacing: 22) {
          agendaColumn
          splitDivider(isVertical: true)
          todoColumn
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
        accent: .teal,
        countText: "\(upcomingEvents.count)"
      )

      if calendarStore.isLoading {
        ProgressView("Loading events...")
          .tint(.teal)
      } else if upcomingEvents.isEmpty {
        emptyState(
          title: "No upcoming event",
          message: googleAuthStore.isAuthenticated || !configStore.config.externalIcalUrl.isEmpty
            ? "Refresh the calendar or adjust the connected sources in Settings."
            : "Connect Google Calendar or add an external iCal URL in Settings."
        )
      } else {
        let events = Array(upcomingEvents.prefix(6))
        ForEach(Array(events.enumerated()), id: \.offset) { index, event in
          agendaTimelineRow(event, isLast: index == events.count - 1)
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
        accent: .orange,
        countText: "\(openTodoCount) open"
      )

      if stageStore.sortedTodos.isEmpty {
        emptyState(
          title: "No todo item",
          message: "Automation todos will appear here when stages move through the pipeline."
        )
      } else {
        let todos = Array(stageStore.sortedTodos.prefix(6))
        ForEach(Array(todos.enumerated()), id: \.offset) { index, todo in
          todoQueueRow(todo, isLast: index == todos.count - 1)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func supportGrid(width: CGFloat) -> some View {
    LazyVGrid(columns: supportColumns(for: width), alignment: .leading, spacing: 18) {
      overviewPanel
      blockersPanel
      qualityPanel
      marketsPanel
      newsPanel
    }
  }

  private var overviewPanel: some View {
    let kpi = stageStore.weeklyKPI

    return dashboardPanel(title: "Pipeline overview", subtitle: "Status distribution and weekly cadence", tint: .blue) {
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
          overviewLine(label: "Pending queue", value: "\(stageStore.pendingQueueCount)")
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
  }

  private var blockersPanel: some View {
    dashboardPanel(title: "Blockers", subtitle: "Items stuck beyond the expected delay", tint: .pink) {
      VStack(alignment: .leading, spacing: 12) {
        if stageStore.blockers.isEmpty {
          emptyState(title: "No blocker found", message: "Open and applied stages are moving within the expected SLA.")
        } else {
          ForEach(stageStore.blockers.prefix(4)) { blocker in
            VStack(alignment: .leading, spacing: 10) {
              HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(blocker.stage.displayLabel.isEmpty ? "Stage" : blocker.stage.displayLabel)
                    .font(.subheadline.weight(.semibold))
                  Text("\(blocker.reason) · \(blocker.stagnantDays)d")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Move to \(blocker.suggestedStatus.rawValue)") {
                  Task {
                    await stageStore.updateStageStatus(stageID: blocker.stage.id, to: blocker.suggestedStatus)
                  }
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .font(.caption.weight(.semibold))
              }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .workspaceInteractiveSurface(cornerRadius: 20, tint: .pink, raised: false)
          }
        }
      }
    }
  }

  private var qualityPanel: some View {
    dashboardPanel(title: "Data quality", subtitle: "Quick fixes for incomplete records", tint: .mint) {
      VStack(alignment: .leading, spacing: 12) {
        if stageStore.qualityIssues.isEmpty {
          emptyState(title: "No issue detected", message: "Company, URL, and deadline fields are populated.")
        } else {
          ForEach(stageStore.qualityIssues.prefix(5)) { issue in
            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text(issue.stage.displayLabel.isEmpty ? "Stage" : issue.stage.displayLabel)
                  .font(.subheadline.weight(.semibold))
                Text("Field: \(issue.field.rawValue)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                if !issue.suggestedValue.isEmpty {
                  Text(issue.suggestedValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
              }
              Spacer()
              if !issue.suggestedValue.isEmpty {
                Button("Apply") {
                  stageStore.applyQualityFix(issue)
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
              }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .workspaceInteractiveSurface(cornerRadius: 18, tint: .mint, raised: false)
          }
        }
      }
    }
  }

  private var marketsPanel: some View {
    dashboardPanel(title: "Markets", subtitle: "Configured symbols from Yahoo Finance", tint: .green) {
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
                  .foregroundStyle(quote.changePercent >= 0 ? Color.green : Color.red)
              }
            }
            .padding(.vertical, 3)
          }
        }
      }
    }
  }

  private var newsPanel: some View {
    dashboardPanel(title: "News", subtitle: "Headlines that may affect the pipeline", tint: .yellow) {
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
              Button("Open") {
                guard let url = URL(string: item.link) else { return }
                if focusStore.isBlocked(url: url) {
                  blockedMessage = focusStore.blockedReason(for: url)
                  return
                }
                openURL(url)
              }
              .buttonStyle(.bordered)
              .font(.caption.weight(.semibold))
            }
            .padding(.vertical, 2)
          }
        }
      }
    }
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
              detailChip(text: event.calendarName, tint: .teal)
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

  private func todoQueueRow(_ todo: TodoItem, isLast: Bool) -> some View {
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

        if let stage = stageForTodo(todo) {
          detailChip(text: stage.displayLabel, tint: .orange)
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
    .overlay(alignment: .bottom) {
      if !isLast {
        Rectangle()
          .fill(Color.white.opacity(0.08))
          .frame(height: 1)
          .padding(.leading, 86)
      }
    }
  }

  private var focusBadge: some View {
    HStack(spacing: 8) {
      Image(systemName: focusStore.isEnabled ? "timer" : "moon.zzz")
      Text(focusStore.isEnabled ? "\(focusStore.phase.rawValue) · \(max(0, focusStore.remainingSeconds / 60))m left" : "Focus off")
        .font(.caption.weight(.semibold))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background((focusStore.isEnabled ? Color.orange : Color.white).opacity(0.14))
    .foregroundStyle(focusStore.isEnabled ? Color.orange : Color.white.opacity(0.74))
    .clipShape(Capsule())
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
    .frame(maxWidth: .infinity, alignment: .leading)
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
          .font(.title3.weight(.bold))
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
    .frame(maxWidth: .infinity, alignment: .leading)
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

  private func supportColumns(for width: CGFloat) -> [GridItem] {
    if width >= supportGridThreshold {
      return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }
    if width >= 860 {
      return [GridItem(.flexible()), GridItem(.flexible())]
    }
    return [GridItem(.flexible())]
  }

  private func horizontalPadding(for width: CGFloat) -> CGFloat {
    width >= 900 ? 28 : 18
  }

  private func stageForTodo(_ todo: TodoItem) -> Stage? {
    stageStore.stages.first(where: { $0.id == todo.relatedStageID })
  }

  private func todoSubtitle(for todo: TodoItem) -> String {
    let prefix = todo.dueDate < Calendar.current.startOfDay(for: Date()) && todo.status != .done ? "Overdue" : "Due"
    return "\(prefix): \(todo.dueDate.shortDate)"
  }

  private func count(for status: StageStatus) -> Int {
    stageStore.stages.filter { $0.status == status }.count
  }

  private func statusColor(_ status: StageStatus) -> Color {
    switch status {
    case .open:
      return .blue
    case .applied:
      return .green
    case .interview:
      return .orange
    case .rejected:
      return .red
    }
  }

  private func todoStatusColor(_ status: TodoStatus) -> Color {
    switch status {
    case .notStarted:
      return .orange
    case .inProgress:
      return .teal
    case .done:
      return .green
    }
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

  private var upcomingEvents: [CalendarEvent] {
    let now = Date()
    return calendarStore.events
      .filter { $0.end >= now.addingTimeInterval(-60 * 60) }
      .sorted { $0.start < $1.start }
  }

  private var nextTodo: TodoItem? {
    stageStore.sortedTodos.first(where: { $0.status != .done })
  }

  private var openTodoCount: Int {
    stageStore.sortedTodos.filter { $0.status != .done }.count
  }

  private var overdueTodoCount: Int {
    let startOfToday = Calendar.current.startOfDay(for: Date())
    return stageStore.sortedTodos.filter { $0.status != .done && $0.dueDate < startOfToday }.count
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
    WorkspaceBackground()
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
