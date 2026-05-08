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
  private let persistenceScheduler = DebouncedWorkScheduler(
    label: "com.loldashboard.notiondashboard.config-store-persist",
    delay: 0.25
  )

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder

    let stored = Self.loadConfig(from: defaults.data(forKey: storageKey), decoder: decoder)
    let legacy = Self.loadConfig(from: LegacyPreferences.data(forKey: storageKey), decoder: decoder)
    let selected = Self.preferredConfig(current: stored, legacy: legacy)
    let migrated = Self.migratedGoogleOAuthConfig(selected)
    let configured = Self.appliedEnvironmentOverrides(migrated)
    self.config = configured
    if configured != stored {
      persist()
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
      config = Self.migratedGoogleOAuthConfig(loaded)
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
      config = Self.migratedGoogleOAuthConfig(snapshot.config)
      return
    }
    if let direct = try? decoder.decode(AppConfig.self, from: data) {
      config = Self.migratedGoogleOAuthConfig(direct)
      return
    }
    throw ConfigStoreError.invalidSnapshot
  }

  private static func migratedGoogleOAuthConfig(_ source: AppConfig) -> AppConfig {
    var config = source
    let defaultScopes = AppConfig.defaults.googleOAuthScopes
    if config.googleOAuthScopes.isEmpty {
      config.googleOAuthScopes = defaultScopes
    }

    let storedRedirectURI = config.googleOAuthRedirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
    if !storedRedirectURI.isEmpty {
      config.googleOAuthRedirectURI = ""
      config.googleAccessToken = ""
      config.googleRefreshToken = ""
      config.googleTokenExpiration = nil
    }

    return config
  }

  private static func appliedEnvironmentOverrides(_ source: AppConfig) -> AppConfig {
    var config = source
    let secrets = EnvironmentSecrets.load()

    let nextClientID = secrets.googleOAuthClientID ?? config.googleOAuthClientID
    let nextClientSecret = secrets.googleOAuthClientSecret ?? config.googleOAuthClientSecret
    let credentialsChanged = nextClientID != config.googleOAuthClientID ||
      nextClientSecret != config.googleOAuthClientSecret

    config.googleOAuthClientID = nextClientID
    config.googleOAuthClientSecret = nextClientSecret

    if credentialsChanged {
      config.googleAccessToken = ""
      config.googleRefreshToken = ""
      config.googleTokenExpiration = nil
      config.googleSelectedCalendarIDs = []
      config.googleDefaultCalendarID = ""
    }

    return config
  }

  private static func loadConfig(from data: Data?, decoder: JSONDecoder) -> AppConfig? {
    guard let data else { return nil }
    return try? decoder.decode(AppConfig.self, from: data)
  }

  private static func preferredConfig(current: AppConfig?, legacy: AppConfig?) -> AppConfig {
    guard let legacy else { return current ?? .defaults }
    guard let current else { return legacy }
    return connectionScore(legacy) > connectionScore(current) ? legacy : current
  }

  private static func connectionScore(_ config: AppConfig) -> Int {
    var score = 0
    if config.hasNotionCredentials { score += 4 }
    if !config.notionTodoDbId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
    if !config.googleRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 3 }
    if !config.googleAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
    if !config.googleSelectedCalendarIDs.isEmpty { score += 2 }
    if !config.externalIcalUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 2 }
    if config.focusModeEnabled { score += 1 }
    return score
  }

  private func persist() {
    let config = self.config
    let defaults = self.defaults
    let storageKey = self.storageKey
    persistenceScheduler.schedule {
      let start = CFAbsoluteTimeGetCurrent()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      guard let data = try? encoder.encode(config) else { return }
      defaults.set(data, forKey: storageKey)
      let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
      PerformanceMonitor.recordPersistence(label: "ConfigStore.persist", durationMs: durationMs)
    }
  }
}
