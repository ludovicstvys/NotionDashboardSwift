import Foundation
import SwiftUI

@MainActor
final class DiagnosticsStore: ObservableObject {
  @Published private(set) var entries: [DiagnosticsEntry] = []

  private let storageKey = "swift_notion_dashboard_diagnostics_v1"
  private let defaults: UserDefaults
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let maxEntries = 200

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder
    reload()
  }

  func log(
    severity: DiagnosticsSeverity = .info,
    category: String,
    message: String,
    metadata: [String: String] = [:]
  ) {
    let entry = DiagnosticsEntry(
      createdAt: Date(),
      severity: severity,
      category: category,
      message: message,
      metadata: metadata
    )
    entries.insert(entry, at: 0)
    if entries.count > maxEntries {
      entries = Array(entries.prefix(maxEntries))
    }
    persist()
  }

  func clear() {
    entries = []
    persist()
  }

  func reload() {
    guard
      let data = defaults.data(forKey: storageKey),
      let decoded = try? decoder.decode([DiagnosticsEntry].self, from: data)
    else {
      entries = []
      return
    }
    entries = decoded
  }

  private func persist() {
    guard let data = try? encoder.encode(entries) else { return }
    defaults.set(data, forKey: storageKey)
  }
}
