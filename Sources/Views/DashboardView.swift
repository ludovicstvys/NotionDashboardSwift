import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var appRouter: AppRouter
  @EnvironmentObject private var dashboardViewModel: DashboardViewModel
  @EnvironmentObject private var stageStore: StageStore
  @EnvironmentObject private var marketNewsStore: MarketNewsStore
  @EnvironmentObject private var calendarStore: CalendarStore
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var googleAuthStore: GoogleAuthStore
  @EnvironmentObject private var focusStore: FocusStore

  @State private var selectedEvent: CalendarEvent?
  @State private var selectedTodo: TodoItem?
  @State private var createTodoDraft = false

  var body: some View {
    NavigationStack {
      ScrollViewReader { scrollProxy in
        GeometryReader { proxy in
          let metrics = WorkspaceLayoutMetrics(width: proxy.size.width)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
              mastheadPanel(width: proxy.size.width, metrics: metrics)
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
      .sheet(item: $selectedTodo) { todo in
        NavigationStack {
          TodoEditorView(
            todo: todo,
            stages: stageStore.stages,
            allowsDelete: true,
            onSave: { title, dueDate, notes, relatedStageID, status in
              Task {
                await stageStore.updateTodo(
                  todoID: todo.id,
                  title: title,
                  dueDate: dueDate,
                  notes: notes,
                  relatedStageID: relatedStageID,
                  status: status
                )
              }
            },
            onDelete: {
              stageStore.deleteTodo(todoID: todo.id)
            }
          )
          .navigationTitle("Edit todo")
        }
        .presentationDetents([.medium, .large])
      }
      .sheet(isPresented: $createTodoDraft) {
        NavigationStack {
          let draftID = UUID().uuidString
          TodoEditorView(
            todo: TodoItem(
              id: draftID,
              title: "",
              dueDate: .now,
              status: .notStarted,
              notes: "",
              relatedStageID: "",
              automationTag: "local:\(draftID)",
              createdAt: .now
            ),
            stages: stageStore.stages,
            allowsDelete: false,
            onSave: { title, dueDate, notes, relatedStageID, status in
              Task {
                await stageStore.createTodo(
                  title: title,
                  dueDate: dueDate,
                  notes: notes,
                  relatedStageID: relatedStageID,
                  status: status
                )
              }
            },
            onDelete: {}
          )
          .navigationTitle("New todo")
        }
        .presentationDetents([.medium, .large])
      }
    }
    .instrumentedScreen("DashboardView")
  }

  private func mastheadPanel(width: CGFloat, metrics: WorkspaceLayoutMetrics) -> some View {
    return WorkspaceHeroPanel(tint: WorkspacePalette.accent, padding: metrics.regularPanelPadding) {
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

  private func mastheadCopy(width: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Image("DashboardLogo")
        .resizable()
        .scaledToFit()
        .frame(width: width >= 980 ? 86 : 72)
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)

      Text("TODAY")
        .font(.caption2.weight(.bold))
        .tracking(1.8)
        .foregroundStyle(Color.white.opacity(0.70))

      Text(width >= 980 ? "Your operating system\nfor today." : "Your operating system for today.")
        .font(.system(size: width >= 1_120 ? 46 : 38, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)

      Text(Date.now.formatted(date: .complete, time: .omitted))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.80))

      Text("Calendar, todos, pipeline and market signals in one focused command center.")
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
      HStack(alignment: .top, spacing: 12) {
        boardHeader(
          title: "Todo",
          subtitle: "Deadlines and pipeline follow-ups",
          accent: WorkspacePalette.warning,
          countText: "\(openTodoCount) open"
        )
        Spacer(minLength: 0)
        Button {
          createTodoDraft = true
        } label: {
          Label("New todo", systemImage: "plus")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(WorkspacePalette.warning)
      }

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
    let supportCardHeight: CGFloat = 390
    return LazyVGrid(columns: supportColumns(for: metrics), alignment: .leading, spacing: metrics.panelGap) {
      focusPanel
        .frame(height: supportCardHeight, alignment: .topLeading)
      marketsPanel
        .frame(height: supportCardHeight, alignment: .topLeading)
      newsPanel
        .frame(height: supportCardHeight, alignment: .topLeading)
    }
  }

  private var focusPanel: some View {
    dashboardPanel(title: "Focus", subtitle: "Pomodoro guardrails and blocked distractions", tint: .pink) {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
          Text(focusStore.isEnabled ? focusTimeText : "Ready")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Text(focusStore.focusSummary)
            .font(.headline.weight(.semibold))
            .foregroundStyle(focusStore.isEnabled ? WorkspacePalette.accentSoft : WorkspacePalette.subtleText)
        }

        ProgressView(value: focusProgress)
          .tint(.pink)

        HStack(spacing: 10) {
          Button(focusStore.isEnabled ? "Restart" : "Start focus") {
            focusStore.startSession()
          }
          .buttonStyle(.borderedProminent)
          .tint(.pink)

          Button(focusStore.isPaused ? "Resume" : "Pause") {
            focusStore.togglePause()
          }
          .buttonStyle(.bordered)
          .disabled(!focusStore.isEnabled)

          Button("Stop") {
            focusStore.stopSession()
          }
          .buttonStyle(.bordered)
          .disabled(!focusStore.isEnabled)
        }

        Text(configStore.config.urlBlockerRules.isEmpty ? "No blocked websites configured." : "\(configStore.config.urlBlockerRules.count) blocked rule(s) active.")
          .font(.caption)
          .foregroundStyle(WorkspacePalette.subtleText)
      }
    }
    .workspaceAlignedCard(minHeight: 390)
  }

  private var marketsPanel: some View {
    dashboardPanel(title: "Markets", subtitle: "Same compact readout style as the widgets", tint: WorkspacePalette.success) {
      VStack(alignment: .leading, spacing: 14) {
        if marketNewsStore.quotes.isEmpty {
          WorkspaceEmptyState(
            title: marketNewsStore.isLoadingQuotes ? "Loading quotes" : "No market quote",
            message: marketNewsStore.isLoadingQuotes ? "Fetching Yahoo Finance data." : "Enable markets or configure symbols in Settings.",
            tint: WorkspacePalette.success,
            systemImage: "chart.line.uptrend.xyaxis"
          )
        } else {
          if let leadQuote = marketNewsStore.quotes.first {
            marketLeadQuote(leadQuote)
          }

          VStack(alignment: .leading, spacing: 8) {
            ForEach(marketNewsStore.quotes.dropFirst().prefix(4)) { quote in
              marketQuoteRow(quote)
            }
          }

          if let lastRefresh = marketNewsStore.lastRefreshDate {
            Text("Updated \(lastRefresh.formatted(.relative(presentation: .named)))")
              .font(.caption2)
              .foregroundStyle(WorkspacePalette.subtleText)
          }
        }
      }
    }
    .workspaceAlignedCard(minHeight: 390)
  }

  private var newsPanel: some View {
    DashboardNewsPanel()
  }

  private var focusTimeText: String {
    let minutes = max(0, focusStore.remainingSeconds) / 60
    let seconds = max(0, focusStore.remainingSeconds) % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private var focusProgress: Double {
    guard focusStore.isEnabled else { return 0 }
    let totalMinutes = focusStore.focusSummary == "Focus break"
      ? configStore.config.pomodoroBreakMinutes
      : configStore.config.pomodoroWorkMinutes
    let total = max(1, totalMinutes * 60)
    return 1 - min(1, Double(max(0, focusStore.remainingSeconds)) / Double(total))
  }

  private func marketLeadQuote(_ quote: MarketQuote) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 5) {
          Text(quote.symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(WorkspacePalette.success)
          Text(quote.shortName)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(2)
        }

        Spacer(minLength: 0)

        Text(marketDirectionLabel(for: quote))
          .font(.caption2.weight(.bold))
          .foregroundStyle(marketTint(for: quote))
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(marketTint(for: quote).opacity(0.16))
          .clipShape(Capsule())
      }

      HStack(alignment: .lastTextBaseline, spacing: 10) {
        Text(marketPriceText(for: quote))
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Text(marketPercentText(for: quote))
          .font(.headline.weight(.bold))
          .foregroundStyle(marketTint(for: quote))
      }

      Text("Market time \(quote.marketTime.formatted(date: .omitted, time: .shortened))")
        .font(.caption)
        .foregroundStyle(WorkspacePalette.subtleText)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(
        colors: [
          WorkspacePalette.success.opacity(0.20),
          WorkspacePalette.innerCard,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(WorkspacePalette.success.opacity(0.18), lineWidth: 1)
    }
  }

  private func marketQuoteRow(_ quote: MarketQuote) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(quote.symbol)
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
        Text(quote.shortName)
          .font(.caption2)
          .foregroundStyle(WorkspacePalette.subtleText)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 2) {
        Text(marketPriceText(for: quote))
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
        Text(marketPercentText(for: quote))
          .font(.caption2.weight(.bold))
          .foregroundStyle(marketTint(for: quote))
      }
    }
    .padding(10)
    .background(WorkspacePalette.innerCard)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func marketPriceText(for quote: MarketQuote) -> String {
    if quote.price >= 1_000 {
      return quote.price.formatted(.number.precision(.fractionLength(0...2)))
    }
    return quote.price.formatted(.number.precision(.fractionLength(2)))
  }

  private func marketPercentText(for quote: MarketQuote) -> String {
    quote.changePercent.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%"
  }

  private func marketDirectionLabel(for quote: MarketQuote) -> String {
    quote.changePercent >= 0 ? "UP" : "DOWN"
  }

  private func marketTint(for quote: MarketQuote) -> Color {
    quote.changePercent >= 0 ? WorkspacePalette.success : WorkspacePalette.danger
  }

  private func agendaTimelineRow(_ event: CalendarEvent, isLast: Bool) -> some View {
    Button {
      selectedEvent = event
    } label: {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text(event.start.formatted(.dateTime.weekday(.abbreviated)))
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(Color.white.opacity(0.56))
          Text(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()))
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Text(event.end.formatted(.dateTime.hour().minute()))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.48))
        }
        .frame(width: 80, alignment: .leading)
        .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
              Text(event.summary.isEmpty ? "Event" : event.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
              Text(event.whenText)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.58))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
              Text(eventTypeLabel(for: event.eventType))
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(eventTypeColor(for: event.eventType).opacity(0.22))
                .foregroundStyle(eventTypeColor(for: event.eventType))
                .clipShape(Capsule())
            }
          }

          HStack(spacing: 6) {
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
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(LinearGradient(
            colors: [
              eventTypeColor(for: event.eventType).opacity(0.12),
              Color.white.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
      )
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private func todoQueueRow(_ todo: TodoItem, isLast: Bool, isHighlighted: Bool) -> some View {
    let isOverdue = todo.status != .done && todo.dueDate < Calendar.current.startOfDay(for: Date())

    return HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .center, spacing: 4) {
          Text(todo.dueDate.formatted(.dateTime.day()))
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(isOverdue ? Color.red : Color.white)
          Text(todo.dueDate.formatted(.dateTime.month(.abbreviated)))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isOverdue ? Color.red.opacity(0.8) : Color.white.opacity(0.56))
        }
        .frame(width: 64, alignment: .center)
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isOverdue
              ? Color.red.opacity(0.12)
              : todoStatusColor(todo.status).opacity(0.12))
        )
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(isOverdue
              ? Color.red.opacity(0.2)
              : todoStatusColor(todo.status).opacity(0.2), lineWidth: 1)
        }

        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
              Text(todo.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

              Text(todoSubtitle(for: todo))
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.56))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 0) {
              Menu {
                ForEach(TodoStatus.allCases) { status in
                  Button(status.rawValue) {
                    stageStore.setTodoStatus(todoID: todo.id, status: status)
                  }
                }
              } label: {
                HStack(spacing: 4) {
                  Text(todo.status.rawValue)
                    .font(.caption2.weight(.bold))
                  Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(todoStatusColor(todo.status).opacity(0.18))
                .foregroundStyle(todoStatusColor(todo.status))
                .clipShape(Capsule())
              }
              .buttonStyle(.plain)
            }
          }

          HStack(spacing: 8) {
            if let label = stageLabel(for: todo), !label.isEmpty {
              detailChip(text: label, tint: WorkspacePalette.warning)
            }
            Spacer(minLength: 0)
            editTodoButton(todo)
          }
        }

        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(LinearGradient(
          colors: [
            todoStatusColor(todo.status).opacity(isHighlighted ? 0.14 : 0.08),
            Color.white.opacity(isHighlighted ? 0.06 : 0.02)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(
          isHighlighted
            ? todoStatusColor(todo.status).opacity(0.40)
            : Color.white.opacity(0.06),
          lineWidth: isHighlighted ? 1.5 : 1
        )
    }
    .contentShape(Rectangle())
    .onTapGesture { selectedTodo = todo }
  }

  private func editTodoButton(_ todo: TodoItem) -> some View {
    Button {
      selectedTodo = todo
    } label: {
      HStack(spacing: 7) {
        Image(systemName: "square.and.pencil")
          .font(.caption.weight(.bold))
        Text("Edit")
          .font(.caption.weight(.bold))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        Capsule(style: .continuous)
          .fill(LinearGradient(
            colors: [
              WorkspacePalette.accent.opacity(0.36),
              Color.white.opacity(0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
      )
      .overlay {
        Capsule(style: .continuous)
          .stroke(WorkspacePalette.accent.opacity(0.38), lineWidth: 1)
      }
      .shadow(color: WorkspacePalette.accent.opacity(0.18), radius: 10, x: 0, y: 5)
    }
    .buttonStyle(.plain)
    .contentShape(Capsule())
    .help("Edit todo")
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

private struct TodoEditorView: View {
  let todo: TodoItem
  let stages: [Stage]
  let allowsDelete: Bool
  let onSave: (_ title: String, _ dueDate: Date, _ notes: String, _ relatedStageID: String, _ status: TodoStatus) -> Void
  let onDelete: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var dueDate: Date
  @State private var notes: String
  @State private var relatedStageID: String
  @State private var status: TodoStatus

  init(
    todo: TodoItem,
    stages: [Stage],
    allowsDelete: Bool,
    onSave: @escaping (_ title: String, _ dueDate: Date, _ notes: String, _ relatedStageID: String, _ status: TodoStatus) -> Void,
    onDelete: @escaping () -> Void
  ) {
    self.todo = todo
    self.stages = stages
    self.allowsDelete = allowsDelete
    self.onSave = onSave
    self.onDelete = onDelete
    _title = State(initialValue: todo.title)
    _dueDate = State(initialValue: todo.dueDate)
    _notes = State(initialValue: todo.notes)
    _relatedStageID = State(initialValue: todo.relatedStageID)
    _status = State(initialValue: todo.status)
  }

  var body: some View {
    Form {
      Section("Todo") {
        TextField("Title", text: $title)
        DatePicker("Due date", selection: $dueDate, displayedComponents: [.date])
        Picker("Status", selection: $status) {
          ForEach(TodoStatus.allCases) { status in
            Text(status.rawValue).tag(status)
          }
        }
      }

      Section("Context") {
        Picker("Related stage", selection: $relatedStageID) {
          Text("None").tag("")
          ForEach(stages) { stage in
            Text(stage.displayLabel.isEmpty ? "Stage" : stage.displayLabel).tag(stage.id)
          }
        }
        TextEditor(text: $notes)
          .frame(minHeight: 120)
      }

      Section {
        Button("Save changes") {
          onSave(title, dueDate, notes, relatedStageID, status)
          dismiss()
        }
        .buttonStyle(.borderedProminent)

        if allowsDelete {
          Button(role: .destructive) {
            onDelete()
            dismiss()
          } label: {
            Text("Delete todo")
          }
        }
      }
    }
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

      ScrollView(.vertical, showsIndicators: true) {
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
            }
            .padding(.vertical, 2)
          }
        }
        }
      }
    }
    .padding(24)
    .workspaceAlignedCard(minHeight: 390)
    .workspaceInteractiveSurface(cornerRadius: 32, tint: WorkspacePalette.accent)
  }
}
