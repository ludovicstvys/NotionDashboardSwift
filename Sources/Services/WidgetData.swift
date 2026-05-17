import Foundation
#if os(macOS)
import Darwin
#endif

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

struct WidgetFocusSnapshot: Codable, Hashable {
  var generatedAt: Date
  var isEnabled: Bool
  var isPaused: Bool
  var phase: String
  var summary: String
  var remainingSeconds: Int
  var endDate: Date?
  var workMinutes: Int
  var breakMinutes: Int

  static let empty = WidgetFocusSnapshot(
    generatedAt: .distantPast,
    isEnabled: false,
    isPaused: false,
    phase: "idle",
    summary: "Focus off",
    remainingSeconds: 0,
    endDate: nil,
    workMinutes: 25,
    breakMinutes: 5
  )
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
  private static let fileName = "dashboard-widget-snapshot-v2.json"

  static func load() -> DashboardWidgetSnapshot? {
    loadFromFile()
  }

  static func save(_ snapshot: DashboardWidgetSnapshot) {
    guard let data = encode(snapshot) else {
      NSLog("DashboardWidgetSnapshotStore: encode failed")
      return
    }
    guard let url = snapshotURL() else { return }
    do {
      try data.write(to: url)
    } catch {
      NSLog("DashboardWidgetSnapshotStore: write failed at \(url.path): \(error)")
    }
  }

  private static func snapshotURL() -> URL? {
    WidgetSharedContainer.url(appending: fileName)
  }

  private static func loadFromFile() -> DashboardWidgetSnapshot? {
    guard let url = snapshotURL(), let data = try? Data(contentsOf: url) else { return nil }
    return decode(DashboardWidgetSnapshot.self, from: data)
  }

}

enum FocusWidgetSnapshotStore {
  private static let fileName = "focus-widget-snapshot-v2.json"

  static func load() -> WidgetFocusSnapshot? {
    loadFromFile()
  }

  static func save(_ snapshot: WidgetFocusSnapshot) {
    guard let data = encode(snapshot) else {
      NSLog("FocusWidgetSnapshotStore: encode failed")
      return
    }
    guard let url = snapshotURL() else { return }
    do {
      try data.write(to: url)
    } catch {
      NSLog("FocusWidgetSnapshotStore: write failed at \(url.path): \(error)")
    }
  }

  private static func snapshotURL() -> URL? {
    WidgetSharedContainer.url(appending: fileName)
  }

  private static func loadFromFile() -> WidgetFocusSnapshot? {
    guard let url = snapshotURL(), let data = try? Data(contentsOf: url) else { return nil }
    return decode(WidgetFocusSnapshot.self, from: data)
  }

}

private enum WidgetSharedContainer {
  private static let appGroupIdentifier = "group.com.loldashboard.notiondashboard.widgets"
  private static let directoryName = "NotionDashboard/WidgetSnapshots"

  static func url(appending fileName: String) -> URL? {
#if os(macOS)
    guard let homeURL = realHomeURL else { return nil }
    let directoryURL = homeURL
      .appendingPathComponent("Library/Application Support", isDirectory: true)
      .appendingPathComponent(directoryName, isDirectory: true)
#else
    guard let directoryURL = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
      .appendingPathComponent(directoryName, isDirectory: true) else { return nil }
#endif
    do {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    } catch {
      NSLog("WidgetSharedContainer: createDirectory failed at \(directoryURL.path): \(error)")
    }
    return directoryURL.appendingPathComponent(fileName)
  }

#if os(macOS)
  private static var realHomeURL: URL? {
    guard let homePointer = getpwuid(getuid())?.pointee.pw_dir else { return nil }
    return URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
  }
#endif
}

private func encode<T: Encodable>(_ value: T) -> Data? {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  encoder.dateEncodingStrategy = .iso8601
  do {
    return try encoder.encode(value)
  } catch {
    NSLog("WidgetData.encode failed for \(T.self): \(error)")
    return nil
  }
}

private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  return try? decoder.decode(type, from: data)
}
