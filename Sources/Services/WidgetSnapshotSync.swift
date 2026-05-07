import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetSnapshotSync {
  private static let queue = DispatchQueue(
    label: "com.loldashboard.notiondashboard.widget-snapshot-sync",
    qos: .utility
  )
  private static var pendingWorkItem: DispatchWorkItem?
  private static var lastSnapshotDigest: Int?
  private static var lastTimelineReloadDate: Date?
  private static let coalesceDelay: TimeInterval = 3
  private static let minReloadInterval: TimeInterval = 5

  static func syncStagesAndTodos(stages: [Stage], todos: [TodoItem]) {
    scheduleSync(
      stages: stages.widgetSnapshots(),
      todos: todos.widgetSnapshots(using: stages),
      events: nil
    )
  }

  static func syncEvents(_ events: [CalendarEvent]) {
    scheduleSync(
      stages: nil,
      todos: nil,
      events: events.widgetSnapshots()
    )
  }

  static func syncEventsImmediately(_ events: [CalendarEvent]) {
    syncNow(
      stages: nil,
      todos: nil,
      events: events.widgetSnapshots()
    )
  }

  static func reloadWidgetTimelines() {
    reloadAllTimelines()
  }

  private static func reloadAllTimelines() {
#if canImport(WidgetKit)
    let now = Date()
    if let lastTimelineReloadDate, now.timeIntervalSince(lastTimelineReloadDate) < minReloadInterval {
      return
    }
    lastTimelineReloadDate = now
    WidgetCenter.shared.reloadAllTimelines()
#endif
  }

  private static func scheduleSync(
    stages: [WidgetStageSnapshot]?,
    todos: [WidgetTodoSnapshot]?,
    events: [WidgetEventSnapshot]?
  ) {
    pendingWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      syncNow(stages: stages, todos: todos, events: events)
    }
    pendingWorkItem = workItem
    queue.asyncAfter(deadline: .now() + coalesceDelay, execute: workItem)
  }

  private static func syncNow(
    stages: [WidgetStageSnapshot]?,
    todos: [WidgetTodoSnapshot]?,
    events: [WidgetEventSnapshot]?
  ) {
    let start = CFAbsoluteTimeGetCurrent()
    var snapshot = WidgetSnapshotStore.load() ?? .empty
    if let stages {
      snapshot.stages = stages
    }
    if let todos {
      snapshot.todos = todos
    }
    if let events {
      snapshot.events = events
    }
    let digest = snapshotDigest(snapshot)
    if digest == lastSnapshotDigest {
      return
    }
    snapshot.generatedAt = Date()
    WidgetSnapshotStore.save(snapshot)
    lastSnapshotDigest = digest
    let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
    PerformanceMonitor.recordPersistence(label: "WidgetSnapshotSync.save", durationMs: durationMs)
    PerformanceMonitor.noteWidgetReloadScheduled()
    reloadAllTimelines()
  }

  private static func snapshotDigest(_ snapshot: DashboardWidgetSnapshot) -> Int {
    var hasher = Hasher()
    hasher.combine(snapshot.todos.count)
    hasher.combine(snapshot.stages.count)
    hasher.combine(snapshot.events.count)
    snapshot.todos.forEach { item in
      hasher.combine(item.id)
      hasher.combine(item.title)
      hasher.combine(item.dueDate.timeIntervalSince1970)
      hasher.combine(item.statusLabel)
      hasher.combine(item.relatedStageLabel)
    }
    snapshot.stages.forEach { item in
      hasher.combine(item.id)
      hasher.combine(item.title)
      hasher.combine(item.company)
      hasher.combine(item.statusKey)
      hasher.combine(item.updatedAt.timeIntervalSince1970)
    }
    snapshot.events.forEach { item in
      hasher.combine(item.id)
      hasher.combine(item.title)
      hasher.combine(item.start.timeIntervalSince1970)
      hasher.combine(item.end.timeIntervalSince1970)
      hasher.combine(item.location)
      hasher.combine(item.calendarName)
      hasher.combine(item.eventTypeLabel)
      hasher.combine(item.isAllDay)
    }
    return hasher.finalize()
  }
}

extension WidgetTodoSnapshot {
  init(todo: TodoItem, relatedStageLabel: String) {
    self.id = todo.id
    self.title = todo.title
    self.dueDate = todo.dueDate
    self.statusLabel = todo.status.rawValue
    self.relatedStageLabel = relatedStageLabel
  }

  init(_ todo: TodoItem, relatedStageLabel: String) {
    self.init(todo: todo, relatedStageLabel: relatedStageLabel)
  }
}

extension WidgetStageSnapshot {
  init(stage: Stage) {
    self.id = stage.id
    self.title = stage.title
    self.company = stage.company
    self.statusKey = stage.status.key
    self.updatedAt = stage.updatedAt
  }

  init(_ stage: Stage) {
    self.init(stage: stage)
  }
}

extension WidgetEventSnapshot {
  init(event: CalendarEvent) {
    self.id = event.id
    self.title = event.summary.isEmpty ? "Event" : event.summary
    self.start = event.start
    self.end = event.end
    self.location = event.location
    self.calendarName = event.calendarName
    self.eventTypeLabel = event.eventType.widgetLabel
    self.isAllDay = event.isAllDay
  }

  init(_ event: CalendarEvent) {
    self.init(event: event)
  }
}

private extension Array where Element == Stage {
  func widgetSnapshots() -> [WidgetStageSnapshot] {
    var result: [WidgetStageSnapshot] = []
    result.reserveCapacity(count)
    for item in self {
      result.append(WidgetStageSnapshot(stage: item))
    }
    return result
  }
}

private extension Array where Element == TodoItem {
  func widgetSnapshots(using stages: [Stage]) -> [WidgetTodoSnapshot] {
    let stageLabelByID = Dictionary(uniqueKeysWithValues: stages.map { ($0.id, $0.displayLabel) })
    return map { todo in
      let relatedStageLabel = stageLabelByID[todo.relatedStageID] ?? ""
      return WidgetTodoSnapshot(todo: todo, relatedStageLabel: relatedStageLabel)
    }
  }
}

private extension Array where Element == CalendarEvent {
  func widgetSnapshots() -> [WidgetEventSnapshot] {
    var result: [WidgetEventSnapshot] = []
    result.reserveCapacity(count)
    for item in self {
      result.append(WidgetEventSnapshot(event: item))
    }
    return result
  }
}

private extension EventType {
  var widgetLabel: String {
    switch self {
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
