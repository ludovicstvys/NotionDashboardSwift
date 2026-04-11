import Foundation
import SwiftUI

enum ConfigStoreError: LocalizedError {
  case invalidText
  case invalidSnapshot

  var errorDescription: String? {
    switch self {
    case .invalidText:
      return "Invalid text input."
    case .invalidSnapshot:
      return "Invalid connections snapshot."
    }
  }
}

@MainActor
final class ConfigStore: ObservableObject {
  @Published var config: AppConfig {
    didSet {
      persist()
    }
  }

  private let storageKey = "swift_notion_dashboard_config_v1"
  private let defaults: UserDefaults
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder

    if
      let data = defaults.data(forKey: storageKey),
      let loaded = try? decoder.decode(AppConfig.self, from: data)
    {
      self.config = loaded
    } else {
      self.config = .defaults
    }
  }

  func update(_ mutate: (inout AppConfig) -> Void) {
    var copy = config
    mutate(&copy)
    config = copy
  }

  func reload() {
    if
      let data = defaults.data(forKey: storageKey),
      let loaded = try? decoder.decode(AppConfig.self, from: data)
    {
      config = loaded
    }
  }

  func exportConnectionsText() throws -> String {
    let snapshot = ConnectionsSnapshot(
      format: "notion-dashboard-swift-connections-v1",
      exportedAt: Date(),
      includesSensitiveData: true,
      config: config
    )
    let data = try encoder.encode(snapshot)
    guard let text = String(data: data, encoding: .utf8) else {
      throw ConfigStoreError.invalidSnapshot
    }
    return text
  }

  func importConnectionsText(_ text: String) throws {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { throw ConfigStoreError.invalidText }
    guard let data = clean.data(using: .utf8) else { throw ConfigStoreError.invalidText }

    if let snapshot = try? decoder.decode(ConnectionsSnapshot.self, from: data) {
      config = snapshot.config
      return
    }
    if let direct = try? decoder.decode(AppConfig.self, from: data) {
      config = direct
      return
    }
    throw ConfigStoreError.invalidSnapshot
  }

  private func persist() {
    guard let data = try? encoder.encode(config) else { return }
    defaults.set(data, forKey: storageKey)
  }
}
