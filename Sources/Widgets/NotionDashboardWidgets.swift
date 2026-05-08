import SwiftUI
import WidgetKit

private struct WidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: DashboardWidgetSnapshot
}

private struct WidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> WidgetEntry {
    WidgetEntry(date: Date(), snapshot: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
    completion(WidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load() ?? .empty))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
    let entry = WidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load() ?? .empty)
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }
}

private enum WidgetPalette {
  static let panel = Color(red: 0.05, green: 0.07, blue: 0.10)
  static let panelTop = Color(red: 0.09, green: 0.12, blue: 0.16)
  static let panelHighlight = Color.white.opacity(0.05)
  static let surface = Color.white.opacity(0.06)
  static let surfaceStrong = Color.white.opacity(0.10)
  static let border = Color.white.opacity(0.12)
  static let subtle = Color.white.opacity(0.76)
  static let muted = Color.white.opacity(0.54)
  static let orange = Color(red: 0.93, green: 0.68, blue: 0.29)
  static let blue = Color(red: 0.18, green: 0.74, blue: 0.92)
  static let teal = Color(red: 0.44, green: 0.86, blue: 0.76)
  static let yellow = Color(red: 0.96, green: 0.78, blue: 0.28)
  static let primaryText = Color.white.opacity(0.97)
  static let secondaryText = Color.white.opacity(0.84)
}

private struct WidgetCardBackground: View {
  let tint: Color

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          WidgetPalette.panelTop,
          tint.opacity(0.12),
          WidgetPalette.panel,
          Color.black.opacity(0.24),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      RadialGradient(
        colors: [
          tint.opacity(0.28),
          .clear,
        ],
        center: .topTrailing,
        startRadius: 10,
        endRadius: 150
      )

      RadialGradient(
        colors: [
          tint.opacity(0.14),
          .clear,
        ],
        center: .bottomLeading,
        startRadius: 6,
        endRadius: 110
      )

      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              WidgetPalette.panelHighlight,
              .clear,
            ],
            startPoint: .topLeading,
            endPoint: .center
          )
        )

      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
    }
  }
}

private extension View {
  @ViewBuilder
  func dashboardWidgetBackground(tint: Color) -> some View {
    if #available(iOSApplicationExtension 17.0, macOSApplicationExtension 14.0, *) {
      containerBackground(for: .widget) {
        WidgetCardBackground(tint: tint)
      }
    } else {
      background(WidgetCardBackground(tint: tint))
    }
  }
}

@main
struct NotionDashboardWidgets: WidgetBundle {
  var body: some Widget {
    TodoSmallWidget()
    OpenStagesSmallWidget()
    UpcomingEventsSmallWidget()
    PomodoroSmallWidget()
  }
}

struct TodoSmallWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "todo-small-widget", provider: WidgetProvider()) { entry in
      TodoSmallWidgetView(entry: entry)
    }
    .configurationDisplayName("Todo")
    .description("Shows your next pending todo.")
    .supportedFamilies([.systemSmall])
  }
}

struct OpenStagesSmallWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "open-stages-small-widget", provider: WidgetProvider()) { entry in
      OpenStagesSmallWidgetView(entry: entry)
    }
    .configurationDisplayName("Open stages")
    .description("Shows your open stage pipeline.")
    .supportedFamilies([.systemSmall])
  }
}

struct UpcomingEventsSmallWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "upcoming-events-small-widget", provider: WidgetProvider()) { entry in
      UpcomingEventsSmallWidgetView(entry: entry)
    }
    .configurationDisplayName("Upcoming event")
    .description("Shows your next calendar event.")
    .supportedFamilies([.systemSmall, .systemLarge])
  }
}

struct PomodoroSmallWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "pomodoro-small-widget", provider: PomodoroWidgetProvider()) { entry in
      PomodoroSmallWidgetView(entry: entry)
    }
    .configurationDisplayName("Pomodoro")
    .description("Shows your current Pomodoro session.")
    .supportedFamilies([.systemSmall])
  }
}

private struct PomodoroWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetFocusSnapshot
}

private struct PomodoroWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> PomodoroWidgetEntry {
    PomodoroWidgetEntry(date: Date(), snapshot: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping (PomodoroWidgetEntry) -> Void) {
    completion(PomodoroWidgetEntry(date: Date(), snapshot: FocusWidgetSnapshotStore.load() ?? .empty))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PomodoroWidgetEntry>) -> Void) {
    let snapshot = FocusWidgetSnapshotStore.load() ?? .empty
    let entry = PomodoroWidgetEntry(date: Date(), snapshot: snapshot)
    let refresh = Calendar.current.date(byAdding: .second, value: 30, to: Date()) ?? Date().addingTimeInterval(30)
    completion(Timeline(entries: [entry], policy: .after(refresh)))
  }
}

private struct PomodoroSmallWidgetView: View {
  let entry: PomodoroWidgetEntry

  private var liveRemainingSeconds: Int {
    guard entry.snapshot.isEnabled,
          !entry.snapshot.isPaused,
          let endDate = entry.snapshot.endDate else {
      return max(0, entry.snapshot.remainingSeconds)
    }
    return max(0, Int(endDate.timeIntervalSinceNow.rounded(.down)))
  }

  private var totalSeconds: Int {
    let minutes = entry.snapshot.phase == "shortBreak" ? entry.snapshot.breakMinutes : entry.snapshot.workMinutes
    return max(1, minutes) * 60
  }

  private var timeText: String {
    let minutes = liveRemainingSeconds / 60
    let seconds = liveRemainingSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private var progress: Double {
    guard entry.snapshot.isEnabled else { return 0 }
    let remaining = liveRemainingSeconds
    return 1 - min(1, Double(remaining) / Double(totalSeconds))
  }

  @ViewBuilder
  private var timerLabel: some View {
    if entry.snapshot.isEnabled,
       !entry.snapshot.isPaused,
       let endDate = entry.snapshot.endDate,
       endDate > Date() {
      Text(timerInterval: Date()...endDate, countsDown: true)
        .font(.system(size: 26, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white)
    } else {
      Text(entry.snapshot.isEnabled ? timeText : "\(max(1, entry.snapshot.workMinutes)):00")
        .font(.system(size: 26, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white)
    }
  }

  private var statusText: String {
    if !entry.snapshot.isEnabled { return "Ready" }
    if entry.snapshot.isPaused {
      return entry.snapshot.phase == "shortBreak" ? "Break paused" : "Work paused"
    }
    return entry.snapshot.phase == "shortBreak" ? "Break" : "Work"
  }

  private var tint: Color {
    if !entry.snapshot.isEnabled { return WidgetPalette.muted }
    if entry.snapshot.isPaused { return WidgetPalette.yellow }
    return entry.snapshot.phase == "shortBreak" ? WidgetPalette.teal : WidgetPalette.orange
  }

  var body: some View {
    WidgetCard(
      title: "Pomodoro",
      symbol: "timer",
      tint: tint,
      url: WidgetDeepLink.settings(),
      generatedAt: entry.snapshot.generatedAt
    ) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 8) {
            Text(entry.snapshot.isEnabled ? "Session live" : "Focus ready")
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .foregroundStyle(tint)
              .textCase(.uppercase)
              .tracking(0.8)

            timerLabel
              .font(.system(size: 34, weight: .bold, design: .rounded))

            Text(statusText)
              .font(.caption)
              .foregroundStyle(WidgetPalette.secondaryText)
              .lineLimit(2)
          }

          Spacer(minLength: 0)

          VStack(alignment: .trailing, spacing: 8) {
            WidgetInfoCapsule(
              label: entry.snapshot.phase == "shortBreak" ? "Break" : "Work",
              tint: tint,
              usesNeutralTint: !entry.snapshot.isEnabled
            )

            if entry.snapshot.isPaused {
              WidgetInfoCapsule(label: "Paused", tint: WidgetPalette.yellow)
            }
          }
        }

        WidgetProgressBar(progress: progress, tint: tint)

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            WidgetInfoCapsule(label: "Work \(max(1, entry.snapshot.workMinutes))m", tint: tint)
            WidgetInfoCapsule(label: "Break \(max(1, entry.snapshot.breakMinutes))m", tint: WidgetPalette.subtle, usesNeutralTint: true)
          }

          Text(entry.snapshot.isEnabled ? entry.snapshot.summary : "Tap to open the dashboard")
            .font(.caption)
            .foregroundStyle(WidgetPalette.secondaryText)
            .lineLimit(2)
            .lineSpacing(1)
        }
      }
    }
  }
}

private struct TodoSmallWidgetView: View {
  let entry: WidgetEntry

  private var nextTodos: [WidgetTodoSnapshot] {
    entry.snapshot.todos
      .filter { $0.statusLabel != "Done" }
      .sorted { $0.dueDate < $1.dueDate }
      .prefix(3)
      .map { $0 }
  }

  var body: some View {
    WidgetCard(title: "Next todos", symbol: "checklist", tint: WidgetPalette.orange, url: WidgetDeepLink.todo(nextTodos.first?.id), generatedAt: entry.snapshot.generatedAt) {
      if !nextTodos.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          let hero = nextTodos[0]

          HStack(alignment: .top, spacing: 12) {
            WidgetKeyFigure(
              value: "\(nextTodos.count)",
              label: nextTodos.count == 1 ? "todo ready" : "todos ready",
              detail: nextTodos.count == 1 ? "One task needs attention" : "Next items in your queue",
              tint: WidgetPalette.orange
            )

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
              WidgetInfoCapsule(label: hero.dueDate.formatted(.dateTime.day().month(.abbreviated)), tint: WidgetPalette.orange)
              if !hero.relatedStageLabel.isEmpty {
                WidgetInfoCapsule(label: hero.relatedStageLabel, tint: WidgetPalette.subtle, usesNeutralTint: true)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(WidgetPanel(tint: WidgetPalette.orange))

          VStack(alignment: .leading, spacing: 8) {
            Text(hero.title)
              .font(.system(size: 17, weight: .bold, design: .rounded))
              .foregroundStyle(WidgetPalette.primaryText)
              .lineLimit(2)
              .minimumScaleFactor(0.85)
              .lineSpacing(1)

            Text("Next up")
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .foregroundStyle(WidgetPalette.muted)
              .textCase(.uppercase)
              .tracking(0.7)

            if nextTodos.count > 1 {
              VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(nextTodos.dropFirst().prefix(2)), id: \.id) { todo in
                  WidgetMiniRow(
                    title: todo.title,
                    detail: todo.relatedStageLabel.isEmpty ? "Due soon" : todo.relatedStageLabel,
                    tint: WidgetPalette.orange
                  )
                }
              }
            }
          }
        }
      } else {
        EmptyWidgetState(title: "No pending todo", subtitle: "Your queue is clear. Open the app when you want to add the next item.")
      }
    }
  }
}

private struct OpenStagesSmallWidgetView: View {
  let entry: WidgetEntry

  private var openStages: [WidgetStageSnapshot] {
    entry.snapshot.stages
      .filter { $0.statusKey == "open" }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  var body: some View {
    WidgetCard(
      title: "Pipeline",
      symbol: "briefcase",
      tint: WidgetPalette.blue,
      url: WidgetDeepLink.stage(openStages.first?.id),
      generatedAt: entry.snapshot.generatedAt
    ) {
      if !openStages.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          let leadStage = openStages[0]

          WidgetKeyFigure(
            value: "\(openStages.count)",
            label: openStages.count == 1 ? "open stage" : "open stages",
            detail: openStages.count == 1 ? "One active opportunity" : "Across your active pipeline",
            tint: WidgetPalette.blue
          )

          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              if !leadStage.company.isEmpty {
                WidgetInfoCapsule(label: leadStage.company, tint: WidgetPalette.blue)
              }
              WidgetInfoCapsule(label: "Updated \(relativeTimeLabel(from: leadStage.updatedAt))", tint: WidgetPalette.subtle, usesNeutralTint: true)
            }

            Text(leadStage.title.isEmpty ? "Stage in progress" : leadStage.title)
              .font(.system(size: 17, weight: .bold, design: .rounded))
              .foregroundStyle(WidgetPalette.primaryText)
              .lineLimit(2)
              .minimumScaleFactor(0.82)

            if openStages.count > 1 {
              VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(openStages.dropFirst().prefix(2)), id: \.id) { stage in
                  WidgetMiniRow(
                    title: stage.company.isEmpty ? stage.title : stage.company,
                    detail: stage.title.isEmpty ? "Active opportunity" : stage.title,
                    tint: WidgetPalette.blue
                  )
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(WidgetPanel(tint: WidgetPalette.blue))
        }
      } else {
        EmptyWidgetState(title: "No open stage", subtitle: "Pipeline is empty. Open the dashboard to add or reopen an opportunity.")
      }
    }
  }
}

private struct UpcomingEventsSmallWidgetView: View {
  @Environment(\.widgetFamily) private var widgetFamily
  let entry: WidgetEntry

  private var nextEvent: WidgetEventSnapshot? {
    let threshold = Date().addingTimeInterval(-3600)
    return entry.snapshot.events
      .filter { $0.end >= threshold }
      .sorted { $0.start < $1.start }
      .first
  }

  var body: some View {
    if widgetFamily == .systemLarge {
      UpcomingEventsLargeWidgetView(entry: entry)
    } else {
      UpcomingEventsCompactWidgetView(entry: entry, nextEvent: nextEvent)
    }
  }
}

private struct UpcomingEventsCompactWidgetView: View {
  let entry: WidgetEntry
  let nextEvent: WidgetEventSnapshot?

  var body: some View {
    WidgetCard(
      title: "Next event",
      symbol: "calendar",
      tint: WidgetPalette.teal,
      url: WidgetDeepLink.event(nextEvent?.id),
      generatedAt: entry.snapshot.generatedAt
    ) {
      if let event = nextEvent {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 12) {
            WidgetKeyFigure(
              value: event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()),
              label: event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
              detail: event.eventTypeLabel,
              tint: WidgetPalette.teal
            )

            Spacer(minLength: 0)

            if !event.location.isEmpty {
              WidgetInfoCapsule(label: "Live", tint: WidgetPalette.teal)
            }
          }
          .padding(12)
          .background(WidgetPanel(tint: WidgetPalette.teal))

          Text(event.title)
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(WidgetPalette.primaryText)
            .lineLimit(3)
            .minimumScaleFactor(0.84)
            .lineSpacing(1)

          VStack(alignment: .leading, spacing: 6) {
            WidgetMetaRow(icon: "calendar", text: event.isAllDay ? "All day on \(event.calendarName)" : "Starts \(relativeTimeLabel(from: event.start))")
            WidgetMetaRow(icon: "mappin.and.ellipse", text: event.location.isEmpty ? event.calendarName : event.location)
          }
        }
      } else {
        EmptyWidgetState(title: "No upcoming event", subtitle: "Nothing is scheduled next. Use the app to add or sync your calendar.")
      }
    }
  }
}

private struct UpcomingEventsLargeWidgetView: View {
  let entry: WidgetEntry

  private var buckets: [WidgetDayBucket] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let endOfWeek = calendar.date(byAdding: .day, value: 4, to: today) ?? Date().addingTimeInterval(60 * 60 * 24 * 4)

    let upcoming = entry.snapshot.events
      .filter { $0.end >= today && $0.start < endOfWeek }
      .sorted { $0.start < $1.start }

    return (0..<4).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
      let events = upcoming.filter { calendar.isDate($0.start, inSameDayAs: date) }
      return WidgetDayBucket(id: date, date: date, events: events)
    }
  }

  private var firstUpcomingEvent: WidgetEventSnapshot? {
    buckets
      .flatMap(\.events)
      .sorted { $0.start < $1.start }
      .first
  }

  var body: some View {
    WidgetCard(
      title: "This week",
      symbol: "calendar.badge.clock",
      tint: WidgetPalette.teal,
      url: WidgetDeepLink.event(entry.snapshot.events.sorted { $0.start < $1.start }.first?.id),
      generatedAt: entry.snapshot.generatedAt
    ) {
      if buckets.contains(where: { !$0.events.isEmpty }) {
        VStack(alignment: .leading, spacing: 12) {
          if let firstUpcomingEvent {
            VStack(alignment: .leading, spacing: 10) {
              HStack(alignment: .top, spacing: 12) {
                WidgetKeyFigure(
                  value: "\(buckets.flatMap(\.events).count)",
                  label: buckets.flatMap(\.events).count == 1 ? "event this week" : "events this week",
                  detail: firstUpcomingEvent.isAllDay ? "Next event is all day" : "Next event starts \(relativeTimeLabel(from: firstUpcomingEvent.start))",
                  tint: WidgetPalette.teal
                )

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                  WidgetInfoCapsule(
                    label: firstUpcomingEvent.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                    tint: WidgetPalette.teal
                  )
                  WidgetInfoCapsule(
                    label: firstUpcomingEvent.isAllDay ? "All day" : firstUpcomingEvent.start.formatted(.dateTime.hour().minute()),
                    tint: WidgetPalette.subtle,
                    usesNeutralTint: true
                  )
                }
              }

              Text(firstUpcomingEvent.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.primaryText)
                .lineLimit(2)
                .lineSpacing(1)

              Text(firstUpcomingEvent.location.isEmpty ? firstUpcomingEvent.calendarName : firstUpcomingEvent.location)
                .font(.caption)
                .foregroundStyle(WidgetPalette.secondaryText)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(WidgetPanel(tint: WidgetPalette.teal))
          }

          VStack(alignment: .leading, spacing: 12) {
            ForEach(buckets) { bucket in
              WidgetAgendaDayRow(bucket: bucket)
            }
          }
        }
      } else {
        WeeklyEmptyWidgetState()
      }
    }
  }
}

private struct WidgetCard<Content: View>: View {
  let title: String
  let symbol: String
  let tint: Color
  let url: URL?
  let generatedAt: Date
  let content: Content

  init(
    title: String,
    symbol: String,
    tint: Color,
    url: URL?,
    generatedAt: Date,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.symbol = symbol
    self.tint = tint
    self.url = url
    self.generatedAt = generatedAt
    self.content = content()
  }

  private var isStale: Bool {
    generatedAt != .distantPast && Date().timeIntervalSince(generatedAt) > 60 * 60 * 3
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color.white.opacity(0.012))

      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(
          LinearGradient(
            colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1
        )

      VStack(alignment: .leading, spacing: 14) {
        HStack {
          HStack(spacing: 7) {
            ZStack {
              Circle()
                .fill(tint.opacity(0.16))
              Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)

            Text(title)
              .font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundStyle(WidgetPalette.secondaryText)
              .tracking(0.35)
          }
          Spacer()
          if isStale {
            Text("STALE")
              .font(.caption2.weight(.bold))
              .foregroundStyle(tint)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(tint.opacity(0.14))
              .clipShape(Capsule())
          }
        }

        content

        Spacer(minLength: 0)
      }
      .padding(17)
    }
    .shadow(color: tint.opacity(0.10), radius: 14, y: 8)
    .dashboardWidgetBackground(tint: tint)
    .widgetURL(url)
  }
}

private struct WidgetPanel: View {
  let tint: Color

  var body: some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
      .fill(
        LinearGradient(
          colors: [
            Color.white.opacity(0.08),
            tint.opacity(0.10),
            Color.black.opacity(0.04),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      )
  }
}

private struct WidgetInfoCapsule: View {
  let label: String
  let tint: Color
  var usesNeutralTint: Bool = false

  var body: some View {
    Text(label)
      .font(.caption2.weight(.bold))
      .foregroundStyle(usesNeutralTint ? WidgetPalette.subtle : tint)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(usesNeutralTint ? WidgetPalette.surfaceStrong : tint.opacity(0.15))
      .clipShape(Capsule())
  }
}

private struct WidgetMetaRow: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      Image(systemName: icon)
        .font(.caption2.weight(.bold))
        .foregroundStyle(WidgetPalette.subtle)
      Text(text)
        .font(.caption)
        .foregroundStyle(WidgetPalette.subtle)
        .lineLimit(2)
        .lineSpacing(1)
    }
  }
}

private struct WidgetKeyFigure: View {
  let value: String
  let label: String
  let detail: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: 32, weight: .bold, design: .rounded))
        .foregroundStyle(WidgetPalette.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .contentTransition(.numericText())

      Text(label)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .textCase(.uppercase)
        .tracking(0.7)

      Text(detail)
        .font(.caption2)
        .foregroundStyle(WidgetPalette.muted)
        .lineLimit(2)
    }
  }
}

private struct WidgetMiniRow: View {
  let title: String
  let detail: String
  let tint: Color

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Capsule()
        .fill(tint.opacity(0.95))
        .frame(width: 3, height: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(WidgetPalette.primaryText)
          .lineLimit(1)

        Text(detail)
          .font(.caption2)
          .foregroundStyle(WidgetPalette.muted)
          .lineLimit(1)
      }
    }
  }
}

private struct WidgetProgressBar: View {
  let progress: Double
  let tint: Color

  var body: some View {
    ZStack(alignment: .leading) {
      Capsule()
        .fill(WidgetPalette.surfaceStrong)

      Capsule()
        .fill(
          LinearGradient(
            colors: [tint.opacity(0.60), tint, .white.opacity(0.95)],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .scaleEffect(x: max(0.06, progress), y: 1, anchor: .leading)
    }
    .frame(height: 8)
    .animation(.easeOut(duration: 0.24), value: progress)
  }
}

private struct WidgetDayBucket: Identifiable {
  let id: Date
  let date: Date
  let events: [WidgetEventSnapshot]
}

private struct WidgetAgendaDayRow: View {
  let bucket: WidgetDayBucket

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(bucket.date.formatted(.dateTime.weekday(.abbreviated)))
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(WidgetPalette.muted)
          .textCase(.uppercase)
          .tracking(0.7)

        Text(bucket.date.formatted(.dateTime.day()))
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundStyle(WidgetPalette.primaryText)
      }
      .frame(width: 42, alignment: .leading)

      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 8) {
          Text(bucket.date.formatted(.dateTime.month(.abbreviated)))
            .font(.caption.weight(.semibold))
            .foregroundStyle(WidgetPalette.secondaryText)
          Spacer()
          Text(bucket.events.isEmpty ? "Free" : "\(bucket.events.count) planned")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(bucket.events.isEmpty ? WidgetPalette.muted : WidgetPalette.teal)
            .tracking(0.2)
        }

        if bucket.events.isEmpty {
          Text("No events scheduled")
            .font(.caption)
            .foregroundStyle(WidgetPalette.muted)
        } else {
          VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(bucket.events.prefix(2)), id: \.id) { event in
              WidgetMiniRow(
                title: "\(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()))  \(event.title)",
                detail: event.location.isEmpty ? event.calendarName : event.location,
                tint: WidgetPalette.teal
              )
            }

            if bucket.events.count > 2 {
              Text("+ \(bucket.events.count - 2) more")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetPalette.subtle)
            }
          }
        }
      }
    }
  }
}

private func relativeTimeLabel(from date: Date) -> String {
  let formatter = RelativeDateTimeFormatter()
  formatter.unitsStyle = .short
  return formatter.localizedString(for: date, relativeTo: Date())
}

private struct EmptyWidgetState: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
        .foregroundStyle(WidgetPalette.primaryText)

      Text(subtitle)
        .font(.caption)
        .foregroundStyle(WidgetPalette.subtle)
        .lineLimit(3)

      Text("Open app")
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
  }
}

private struct WeeklyEmptyWidgetState: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Week looks clear")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(WidgetPalette.primaryText)

        Text("No upcoming events in the next four days.")
          .font(.subheadline)
          .foregroundStyle(WidgetPalette.secondaryText)
          .lineLimit(2)
      }

      HStack(spacing: 10) {
        ForEach(0..<4, id: \.self) { offset in
          VStack(alignment: .leading, spacing: 8) {
            Text(dayLabel(offset: offset))
              .font(.system(size: 11, weight: .bold, design: .rounded))
              .foregroundStyle(WidgetPalette.muted)
              .textCase(.uppercase)
              .tracking(0.8)

            Spacer(minLength: 0)

            Circle()
              .fill(WidgetPalette.teal.opacity(offset == 0 ? 0.85 : 0.40))
              .frame(width: 7, height: 7)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
              .fill(Color.white.opacity(0.08))
              .frame(height: 3)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
              .fill(Color.white.opacity(0.05))
              .frame(height: 3)
              .padding(.trailing, 10)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .padding(12)
          .background(WidgetPanel(tint: WidgetPalette.teal))
        }
      }
      .frame(maxHeight: .infinity)

      Text("Use the free time for deep work, outreach, or recovery.")
        .font(.caption)
        .foregroundStyle(WidgetPalette.muted)
        .lineLimit(2)
    }
  }

  private func dayLabel(offset: Int) -> String {
    let calendar = Calendar.current
    let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    return date.formatted(.dateTime.weekday(.abbreviated))
  }
}
