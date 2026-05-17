import Foundation

struct StageStoreSnapshot: Codable {
  var stages: [Stage]
  var todos: [TodoItem]
  var pendingOperations: [PendingNotionOperation]
  var lastSuccessfulNotionSyncDate: Date?

  static let empty = StageStoreSnapshot(
    stages: [],
    todos: [],
    pendingOperations: [],
    lastSuccessfulNotionSyncDate: nil
  )
}

enum StageStoreCache {
  private static let fileName = "stage-store-cache-v2.json"

  static func load() -> StageStoreSnapshot? {
    guard let url = snapshotURL() else { return nil }
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(StageStoreSnapshot.self, from: data)
  }

  static func save(_ snapshot: StageStoreSnapshot) {
    guard let url = snapshotURL() else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data: Data
    do {
      data = try encoder.encode(snapshot)
    } catch {
      NSLog("StageStoreCache: encode failed: \(error)")
      return
    }
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: url, options: .atomic)
    } catch {
      NSLog("StageStoreCache.save failed at \(url.path): \(error)")
      PerformanceMonitor.recordPersistence(label: "StageStoreCache.save.error", durationMs: 0)
    }
  }

  private static func snapshotURL() -> URL? {
    AppSupportDirectory.fileURL(fileName)
  }
}
