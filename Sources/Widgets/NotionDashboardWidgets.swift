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

@main
struct NotionDashboardWidgets: WidgetBundle {
  var body: some Widget {
    TodoSmallWidget()
    OpenStagesSmallWidget()
    UpcomingEventsSmallWidget()
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
    .supportedFamilies([.systemSmall])
  }
}

private struct TodoSmallWidgetView: View {
  let entry: WidgetEntry

  private var nextTodo: WidgetTodoSnapshot? {
    entry.snapshot.todos
      .filter { $0.statusLabel != "Done" }
      .sorted { $0.dueDate < $1.dueDate }
      .first
  }

  var body: some View {
    WidgetCard(title: "Next todo", tint: WidgetPalette.orange, url: WidgetDeepLink.todo(nextTodo?.id), generatedAt: entry.snapshot.generatedAt) {
      if let todo = nextTodo {
        VStack(alignment: .leading, spacing: 8) {
          Text(todo.title)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(3)

          Text(todo.dueDate, style: .date)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WidgetPalette.subtle)

          if !todo.relatedStageLabel.isEmpty {
            Text(todo.relatedStageLabel)
              .font(.caption2)
              .foregroundStyle(WidgetPalette.muted)
              .lineLimit(1)
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
  let entry: WidgetEntry

  private var nextEvent: WidgetEventSnapshot? {
    let threshold = Date().addingTimeInterval(-3600)
    return entry.snapshot.events
      .filter { $0.end >= threshold }
      .sorted { $0.start < $1.start }
      .first
  }

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

private struct WidgetCard<Content: View>: View {
  let title: String
  let tint: Color
  let url: URL?
  let generatedAt: Date
  @ViewBuilder let content: Content

  private var isStale: Bool {
    generatedAt != .distantPast && Date().timeIntervalSince(generatedAt) > 60 * 60 * 3
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              WidgetPalette.panel,
              tint.opacity(0.34),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
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
