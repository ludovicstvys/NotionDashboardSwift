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
  static let panel = Color(red: 0.10, green: 0.12, blue: 0.16)
  static let border = Color.white.opacity(0.08)
  static let subtle = Color.white.opacity(0.66)
  static let muted = Color.white.opacity(0.52)
  static let orange = Color.orange
  static let blue = Color.blue
  static let teal = Color.teal
}

private struct WidgetCardBackground: View {
  let tint: Color

  var body: some View {
    LinearGradient(
      colors: [
        WidgetPalette.panel,
        tint.opacity(0.34),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
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

  private var modeText: String {
    if !entry.snapshot.isEnabled { return "Idle" }
    return entry.snapshot.phase == "shortBreak" ? "Break" : "Work"
  }

  private var tint: Color {
    if !entry.snapshot.isEnabled { return WidgetPalette.muted }
    if entry.snapshot.isPaused { return .yellow }
    return entry.snapshot.phase == "shortBreak" ? WidgetPalette.teal : WidgetPalette.orange
  }

  var body: some View {
    WidgetCard(
      title: "Pomodoro",
      tint: tint,
      url: WidgetDeepLink.settings(),
      generatedAt: entry.snapshot.generatedAt
    ) {
      VStack(alignment: .leading, spacing: 12) {
        ZStack {
          Circle()
            .stroke(WidgetPalette.border, lineWidth: 12)

          Circle()
            .trim(from: 0, to: max(0.01, progress))
            .stroke(
              AngularGradient(
                colors: [
                  tint.opacity(0.55),
                  tint,
                  .white.opacity(0.9),
                  tint.opacity(0.55)
                ],
                center: .center
              ),
              style: StrokeStyle(lineWidth: 12, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: tint.opacity(0.35), radius: 8)

          Circle()
            .fill(WidgetPalette.panel)
            .frame(width: 92, height: 92)

          VStack(spacing: 2) {
            timerLabel

            Text(modeText)
              .font(.caption2.weight(.bold))
              .foregroundStyle(tint)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(tint.opacity(0.16))
              .clipShape(Capsule())
          }
        }
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 4) {
          Text(statusText)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(1)

          Text(entry.snapshot.isEnabled ? "Work \(max(1, entry.snapshot.workMinutes))m • Break \(max(1, entry.snapshot.breakMinutes))m" : "Tap to open the dashboard")
            .font(.caption)
            .foregroundStyle(WidgetPalette.subtle)
            .lineLimit(2)
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
    WidgetCard(title: "Next todos", tint: WidgetPalette.orange, url: WidgetDeepLink.todo(nextTodos.first?.id), generatedAt: entry.snapshot.generatedAt) {
      if !nextTodos.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(nextTodos.enumerated()), id: \.element.id) { index, todo in
            VStack(alignment: .leading, spacing: 2) {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index + 1).")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(WidgetPalette.subtle)

                Text(todo.title)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.white)
                  .lineLimit(1)
              }

              HStack(spacing: 6) {
                Text(todo.dueDate, style: .date)
                  .font(.caption2)
                  .foregroundStyle(WidgetPalette.muted)

                if !todo.relatedStageLabel.isEmpty {
                  Text("•")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WidgetPalette.muted)

                  Text(todo.relatedStageLabel)
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(1)
                }
              }
            }
          }
        }
      } else {
        EmptyWidgetState(title: "No pending todo", subtitle: "Your queue is clear.")
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
      title: "Open stages",
      tint: WidgetPalette.blue,
      url: WidgetDeepLink.stage(openStages.first?.id),
      generatedAt: entry.snapshot.generatedAt
    ) {
      if let stage = openStages.first {
        VStack(alignment: .leading, spacing: 8) {
          Text("\(openStages.count)")
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(.white)

          Text(stage.company.isEmpty ? "Unknown company" : stage.company)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WidgetPalette.subtle)
            .lineLimit(1)

          Text(stage.title.isEmpty ? "Stage" : stage.title)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(3)

          Text(stage.updatedAt, style: .relative)
            .font(.caption2)
            .foregroundStyle(WidgetPalette.muted)
        }
      } else {
        EmptyWidgetState(title: "No open stage", subtitle: "Pipeline is empty.")
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
      tint: WidgetPalette.teal,
      url: WidgetDeepLink.event(nextEvent?.id),
      generatedAt: entry.snapshot.generatedAt
    ) {
      if let event = nextEvent {
        VStack(alignment: .leading, spacing: 8) {
          Text(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()))
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(.white)

          Text(event.title)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(3)

          Text(event.eventTypeLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WidgetPalette.subtle)

          Text(event.location.isEmpty ? event.calendarName : event.location)
            .font(.caption2)
            .foregroundStyle(WidgetPalette.muted)
            .lineLimit(1)
        }
      } else {
        EmptyWidgetState(title: "No upcoming event", subtitle: "Nothing scheduled next.")
      }
    }
  }
}

private struct UpcomingEventsLargeWidgetView: View {
  let entry: WidgetEntry

  private struct DayBucket: Identifiable {
    let id: Date
    let date: Date
    let events: [WidgetEventSnapshot]
  }

  private var buckets: [DayBucket] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let endOfWeek = calendar.date(byAdding: .day, value: 7, to: today) ?? Date().addingTimeInterval(60 * 60 * 24 * 7)

    let upcoming = entry.snapshot.events
      .filter { $0.end >= today && $0.start < endOfWeek }
      .sorted { $0.start < $1.start }

    return (0..<7).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
      let events = upcoming.filter { calendar.isDate($0.start, inSameDayAs: date) }
      return DayBucket(id: date, date: date, events: events)
    }
  }

  var body: some View {
    WidgetCard(
      title: "This week",
      tint: WidgetPalette.teal,
      url: WidgetDeepLink.event(entry.snapshot.events.sorted { $0.start < $1.start }.first?.id),
      generatedAt: entry.snapshot.generatedAt
    ) {
      if buckets.contains(where: { !$0.events.isEmpty }) {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(buckets) { bucket in
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(bucket.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                  .font(.caption.weight(.bold))
                  .foregroundStyle(.white)
                Spacer()
                Text("\(bucket.events.count)")
                  .font(.caption2.weight(.bold))
                  .foregroundStyle(WidgetPalette.subtle)
              }

              if bucket.events.isEmpty {
                Text("No events")
                  .font(.caption2)
                  .foregroundStyle(WidgetPalette.muted)
              } else {
                ForEach(Array(bucket.events.prefix(3)), id: \.id) { event in
                  HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()))
                      .font(.caption2.weight(.semibold))
                      .foregroundStyle(WidgetPalette.subtle)
                      .frame(width: 62, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                      Text(event.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                      Text(event.location.isEmpty ? event.calendarName : event.location)
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.muted)
                        .lineLimit(1)
                    }
                  }
                }

                if bucket.events.count > 3 {
                  Text("+ \(bucket.events.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.muted)
                }
              }
            }
          }
        }
      } else {
        EmptyWidgetState(title: "No upcoming events", subtitle: "Nothing scheduled this week.")
      }
    }
  }
}

private struct WidgetCard<Content: View>: View {
  let title: String
  let tint: Color
  let url: URL?
  let generatedAt: Date
  let content: Content

  init(
    title: String,
    tint: Color,
    url: URL?,
    generatedAt: Date,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
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
        .stroke(WidgetPalette.border, lineWidth: 1)

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.88))
          Spacer()
          if isStale {
            Text("STALE")
              .font(.caption2.weight(.bold))
              .foregroundStyle(tint)
          }
        }

        content

        Spacer(minLength: 0)
      }
      .padding(16)
    }
    .dashboardWidgetBackground(tint: tint)
    .widgetURL(url)
  }
}

private struct EmptyWidgetState: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.white)

      Text(subtitle)
        .font(.caption)
        .foregroundStyle(WidgetPalette.subtle)
        .lineLimit(3)
    }
  }
}
