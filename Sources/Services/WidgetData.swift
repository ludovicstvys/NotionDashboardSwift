import Foundation

struct WidgetTodoSnapshot: Codable, Hashable, Identifiable {
  var id: String
  var title: String
  var dueDate: Date
  var statusLabel: String
  var relatedStageLabel: String
}

struct WidgetStageSnapshot: Codable, Hashable, Identifiable {
  var id: String
  var title: String
  var company: String
  var statusKey: String
  var updatedAt: Date
}

struct WidgetEventSnapshot: Codable, Hashable, Identifiable {
  var id: String
  var title: String
  var start: Date
  var end: Date
  var location: String
  var calendarName: String
  var eventTypeLabel: String
  var isAllDay: Bool
}

struct DashboardWidgetSnapshot: Codable, Hashable {
  var generatedAt: Date
  var todos: [WidgetTodoSnapshot]
  var stages: [WidgetStageSnapshot]
  var events: [WidgetEventSnapshot]

  static let empty = DashboardWidgetSnapshot(
    generatedAt: .distantPast,
    todos: [],
    stages: [],
    events: []
  )
}

enum WidgetDeepLink {
  static let scheme = "notiondashboard"

  static func todo(_ todoID: String?) -> URL? {
    build(host: "home", pathComponents: todoID.map { ["todo", $0] } ?? [])
  }

  static func stage(_ stageID: String?) -> URL? {
    build(host: "stages", pathComponents: stageID.map { [$0] } ?? [])
  }

  static func event(_ eventID: String?) -> URL? {
    build(host: "calendar", pathComponents: eventID.map { [$0] } ?? [])
  }

  static func settings() -> URL? {
    build(host: "settings", pathComponents: [])
  }

  private static func build(host: String, pathComponents: [String]) -> URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = pathComponents.map { "/\($0)" }.joined()
    return components.url
  }
}

enum WidgetSnapshotStore {
  static let appGroupIdentifier = "group.com.loldashboard.notiondashboard"
  private static let fileName = "dashboard-widget-snapshot.json"

  static func load() -> DashboardWidgetSnapshot? {
    guard let url = snapshotURL() else { return nil }
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(DashboardWidgetSnapshot.self, from: data)
  }

  static func save(_ snapshot: DashboardWidgetSnapshot) {
    guard let url = snapshotURL() else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(snapshot) else { return }
    try? data.write(to: url, options: .atomic)
  }

  private static func snapshotURL() -> URL? {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    return containerURL.appendingPathComponent(fileName)
  }
}
