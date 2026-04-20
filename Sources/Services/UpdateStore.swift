import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import Sparkle
#endif

struct UpdateManifest: Hashable, Identifiable {
  let channel: String
  let version: String
  let build: String
  let minimumSystemVersion: String
  let publishedAt: Date?
  let releaseNotesURL: URL?

  var id: String {
    "\(channel)-\(version)-\(build)"
  }

  var versionLabel: String {
    build == version ? version : "\(version) (\(build))"
  }
}

enum UpdateCheckState: Equatable {
  case idle
  case checking
  case upToDate
  case updateAvailable
  case error
}

enum UpdateStoreError: LocalizedError {
  case unsupportedPlatform
  case missingFeedURL
  case missingPublicKey
  case updaterUnavailable
  case unableToOpenReleaseNotes

  var errorDescription: String? {
    switch self {
    case .unsupportedPlatform:
      return "Sparkle updates are only available in the macOS app."
    case .missingFeedURL:
      return "Sparkle feed URL is missing from the app configuration."
    case .missingPublicKey:
      return "Sparkle public EdDSA key is missing. Set SPARKLE_PUBLIC_ED_KEY before publishing updates."
    case .updaterUnavailable:
      return "Sparkle updater is unavailable because the app is not configured yet."
    case .unableToOpenReleaseNotes:
      return "Release notes are not available for the latest appcast item."
    }
  }
}

@MainActor
final class UpdateStore: NSObject, ObservableObject {
  private let sparkleNoUpdateErrorCode = 1001

  @Published private(set) var state: UpdateCheckState = .idle
  @Published private(set) var availableUpdate: UpdateManifest?
  @Published private(set) var lastCheckDate: Date?
  @Published private(set) var automaticChecksEnabled = false
  @Published private(set) var automaticDownloadsEnabled = false
  @Published private(set) var allowsAutomaticDownloads = false
  @Published private(set) var checkInterval: TimeInterval = 3600
  @Published private(set) var lastErrorMessage = ""

  private let bundle: Bundle
  private weak var diagnostics: DiagnosticsStore?

#if os(macOS)
  private var updaterController: SPUStandardUpdaterController?
#endif

  init(
    diagnostics: DiagnosticsStore?,
    bundle: Bundle = .main
  ) {
    self.bundle = bundle
    self.diagnostics = diagnostics
    super.init()

#if os(macOS)
    guard configurationIssue == nil else {
      lastErrorMessage = configurationIssue ?? ""
      state = .error
      diagnostics?.log(
        severity: .warning,
        category: "updates",
        message: "Sparkle configuration is incomplete.",
        metadata: ["error": lastErrorMessage]
      )
      return
    }

    let controller = SPUStandardUpdaterController(
      startingUpdater: false,
      updaterDelegate: self,
      userDriverDelegate: nil
    )
    updaterController = controller

    // Sparkle prefers any feed URL persisted in defaults over Info.plist; clear old overrides.
    _ = controller.updater.clearFeedURLFromUserDefaults()

    refreshFromUpdater()
    controller.startUpdater()
    diagnostics?.log(category: "updates", message: "Sparkle updater started.")
#endif
  }

  var currentVersion: String {
    (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
  }

  var currentBuild: Int {
    Int((bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0") ?? 0
  }

  var channel: String {
    (bundle.object(forInfoDictionaryKey: "UpdateChannel") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty ?? "stable"
  }

  var minimumSystemVersion: String {
    (bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty ?? "13.0"
  }

  var sparkleFeedURL: URL? {
    let rawValue = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty
    return rawValue.flatMap(URL.init(string:))
  }

  var sparklePublicKey: String {
    (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  var currentVersionLabel: String {
    "\(currentVersion) (\(currentBuild))"
  }

  var checkIntervalLabel: String {
    Self.intervalLabel(for: checkInterval)
  }

  var lastCheckLabel: String {
    lastCheckDate?.shortDateTime ?? "Never"
  }

  var statusLabel: String {
    switch state {
    case .idle:
      return "Idle"
    case .checking:
      return "Checking"
    case .upToDate:
      return "Up to date"
    case .updateAvailable:
      return "Update available"
    case .error:
      return "Configuration"
    }
  }

  var detailMessage: String {
    switch state {
    case .idle:
      return "Sparkle is ready to monitor the published appcast."
    case .checking:
      return "Sparkle is checking the appcast and update pipeline."
    case .upToDate:
      return "Current build \(currentVersionLabel) is the latest item Sparkle can install."
    case .updateAvailable:
      if let availableUpdate {
        return "Version \(availableUpdate.versionLabel) is published and ready for Sparkle to install."
      }
      return "A newer build is published in the appcast."
    case .error:
      return lastErrorMessage.isEmpty ? "Sparkle is not configured yet." : lastErrorMessage
    }
  }

  func setAutomaticChecksEnabled(_ enabled: Bool) {
#if os(macOS)
    guard let updater = updaterController?.updater else { return }
    updater.automaticallyChecksForUpdates = enabled
    refreshFromUpdater()
    diagnostics?.log(
      category: "updates",
      message: "Updated automatic Sparkle checks.",
      metadata: ["enabled": enabled ? "true" : "false"]
    )
#endif
  }

  func setAutomaticDownloadsEnabled(_ enabled: Bool) {
#if os(macOS)
    guard let updater = updaterController?.updater else { return }
    updater.automaticallyDownloadsUpdates = enabled
    refreshFromUpdater()
    diagnostics?.log(
      category: "updates",
      message: "Updated Sparkle automatic downloads.",
      metadata: ["enabled": enabled ? "true" : "false"]
    )
#endif
  }

  func performLaunchCheckIfNeeded() async {
#if os(macOS)
    refreshFromUpdater()
#endif
  }

  func checkForUpdates(userInitiated: Bool) async {
#if os(macOS)
    guard configurationIssue == nil else {
      let message = configurationIssue ?? UpdateStoreError.updaterUnavailable.localizedDescription
      lastErrorMessage = message
      state = .error
      diagnostics?.log(
        severity: .warning,
        category: "updates",
        message: "Sparkle check skipped because configuration is incomplete.",
        metadata: ["error": message]
      )
      return
    }

    guard let updater = updaterController?.updater else {
      let error = UpdateStoreError.updaterUnavailable
      lastErrorMessage = error.localizedDescription
      state = .error
      diagnostics?.log(
        severity: .warning,
        category: "updates",
        message: "Sparkle updater is unavailable.",
        metadata: ["error": error.localizedDescription]
      )
      return
    }

    lastErrorMessage = ""
    state = .checking
    availableUpdate = nil

    if userInitiated {
      updater.checkForUpdates()
    } else {
      updater.checkForUpdateInformation()
    }
#else
    let error = UpdateStoreError.unsupportedPlatform
    lastErrorMessage = error.localizedDescription
    state = .error
#endif
  }

  func openReleaseNotesURL() {
    guard let url = availableUpdate?.releaseNotesURL else {
      lastErrorMessage = UpdateStoreError.unableToOpenReleaseNotes.localizedDescription
      state = .error
      return
    }

    open(url: url, purpose: "release-notes")
  }

  private var configurationIssue: String? {
    if sparkleFeedURL == nil {
      return UpdateStoreError.missingFeedURL.localizedDescription
    }
    if sparklePublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return UpdateStoreError.missingPublicKey.localizedDescription
    }
    return nil
  }

  private func refreshFromUpdater() {
#if os(macOS)
    guard let updater = updaterController?.updater else { return }
    automaticChecksEnabled = updater.automaticallyChecksForUpdates
    automaticDownloadsEnabled = updater.automaticallyDownloadsUpdates
    allowsAutomaticDownloads = updater.allowsAutomaticUpdates
    checkInterval = updater.updateCheckInterval
    lastCheckDate = updater.lastUpdateCheckDate

    if updater.sessionInProgress {
      state = .checking
    } else if !lastErrorMessage.isEmpty {
      state = .error
    } else if availableUpdate != nil {
      state = .updateAvailable
    } else if lastCheckDate != nil {
      state = .upToDate
    } else {
      state = .idle
    }
#endif
  }

  private func open(url: URL, purpose: String) {
#if os(iOS)
    UIApplication.shared.open(url)
#elseif os(macOS)
    NSWorkspace.shared.open(url)
#endif
    diagnostics?.log(
      category: "updates",
      message: "Opened Sparkle URL.",
      metadata: [
        "purpose": purpose,
        "url": url.absoluteString,
      ]
    )
  }

  private func setAvailableUpdate(_ item: UpdateManifest?) {
    availableUpdate = item
    if item != nil {
      state = .updateAvailable
    } else if lastErrorMessage.isEmpty {
      state = lastCheckDate == nil ? .idle : .upToDate
    }
  }

  private func handleCheckError(_ error: Error?) {
#if os(macOS)
    refreshFromUpdater()

    guard let error else {
      lastErrorMessage = ""
      if availableUpdate == nil {
        state = lastCheckDate == nil ? .idle : .upToDate
      }
      return
    }

    let nsError = error as NSError
    if nsError.domain == SUSparkleErrorDomain && nsError.code == sparkleNoUpdateErrorCode {
      lastErrorMessage = ""
      state = .upToDate
      return
    }

    lastErrorMessage = nsError.localizedDescription
    state = .error
    diagnostics?.log(
      severity: .warning,
      category: "updates",
      message: "Sparkle cycle finished with an error.",
      metadata: ["error": nsError.localizedDescription]
    )
#else
    if let error {
      lastErrorMessage = error.localizedDescription
      state = .error
    } else {
      lastErrorMessage = UpdateStoreError.unsupportedPlatform.localizedDescription
      state = .idle
    }
#endif
  }

  private static func intervalLabel(for interval: TimeInterval) -> String {
    let minutes = Int(interval / 60)
    if minutes < 60 {
      return "\(minutes) min"
    }

    let hours = Int(interval / 3600)
    if hours < 24 {
      return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    let days = Int(interval / 86_400)
    return days == 1 ? "1 day" : "\(days) days"
  }
}

#if os(macOS)
extension UpdateStore: SPUUpdaterDelegate {
  func allowedChannels(for updater: SPUUpdater) -> Set<String> {
    let currentChannel = channel.lowercased()
    guard currentChannel != "stable", currentChannel != "default" else {
      return []
    }
    return [currentChannel]
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    let manifest = UpdateManifest(
      channel: channel,
      version: item.displayVersionString.nonEmpty ?? item.versionString,
      build: item.versionString,
      minimumSystemVersion: item.minimumSystemVersion ?? minimumSystemVersion,
      publishedAt: item.date,
      releaseNotesURL: item.releaseNotesURL
    )
    setAvailableUpdate(manifest)
    lastErrorMessage = ""
    lastCheckDate = updater.lastUpdateCheckDate
    diagnostics?.log(
      category: "updates",
      message: "Sparkle found a valid update.",
      metadata: [
        "version": manifest.version,
        "build": manifest.build,
        "channel": manifest.channel,
      ]
    )
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
    setAvailableUpdate(nil)
    lastCheckDate = updater.lastUpdateCheckDate
    lastErrorMessage = ""
    state = .upToDate
    diagnostics?.log(category: "updates", message: "Sparkle did not find a newer update.")
  }

  func updater(_ updater: SPUUpdater, didNotFindUpdate error: Error) {
    lastCheckDate = updater.lastUpdateCheckDate
    handleCheckError(error)
  }

  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
    lastCheckDate = updater.lastUpdateCheckDate
    handleCheckError(error)
  }
}
#endif

private extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
