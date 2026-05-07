import Combine
import Foundation
import SwiftUI

@MainActor
final class FocusStore: ObservableObject {
  enum Phase: String {
    case idle
    case work
    case shortBreak
  }

  @Published var isEnabled: Bool = false
  @Published private(set) var isPaused: Bool = false
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var remainingSeconds: Int = 0
  @Published private(set) var focusSummary: String = "Focus off"
  @Published private(set) var completionToken: String = ""

  private var timer: Timer?
  private weak var configStore: ConfigStore?
  private weak var diagnostics: DiagnosticsStore?
  private weak var notificationScheduler: NotificationScheduler?
  private var cancellables: Set<AnyCancellable> = []

  init(configStore: ConfigStore, diagnostics: DiagnosticsStore?, notificationScheduler: NotificationScheduler? = nil) {
    self.configStore = configStore
    self.diagnostics = diagnostics
    self.notificationScheduler = notificationScheduler
    self.isEnabled = configStore.config.focusModeEnabled
    if self.isEnabled {
      phase = .work
      remainingSeconds = max(1, configStore.config.pomodoroWorkMinutes) * 60
      runTimer()
    }
    refreshFocusSummary()

    configStore.$config
      .map(\.focusModeEnabled)
      .removeDuplicates()
      .sink { [weak self] enabled in
        guard let self else { return }
        if enabled != self.isEnabled {
          self.setEnabled(enabled, persistConfig: false, emitLogs: false)
        }
      }
      .store(in: &cancellables)
  }

  deinit {
    timer?.invalidate()
  }

  func startSession() {
    setEnabled(true, persistConfig: true)
  }

  func stopSession() {
    setEnabled(false, persistConfig: true)
  }

  func pauseSession() {
    guard isEnabled, !isPaused else { return }
    isPaused = true
    refreshFocusSummary()
    syncWidgetSnapshot()
    diagnostics?.log(category: "focus", message: "Focus session paused.")
  }

  func resumeSession() {
    guard isEnabled, isPaused else { return }
    isPaused = false
    refreshFocusSummary()
    syncWidgetSnapshot()
    diagnostics?.log(category: "focus", message: "Focus session resumed.")
  }

  func togglePause() {
    if isPaused {
      resumeSession()
    } else {
      pauseSession()
    }
  }

  func setEnabled(_ enabled: Bool) {
    setEnabled(enabled, persistConfig: true)
  }

  private func setEnabled(_ enabled: Bool, persistConfig: Bool, emitLogs: Bool = true) {
    if enabled {
      activateSession(persistConfig: persistConfig, emitLogs: emitLogs)
    } else {
      deactivateSession(persistConfig: persistConfig, emitLogs: emitLogs)
    }
  }

  func isBlocked(url: URL) -> Bool {
    matchedBlockRule(for: url) != nil
  }

  func blockedReason(for url: URL) -> String {
    if let rule = matchedBlockRule(for: url) {
      return "Blocked by focus mode: \(url.host ?? url.absoluteString) matches \(rule)."
    }
    return "Blocked by focus mode: \(url.host ?? url.absoluteString)"
  }

  private func runTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard !self.isPaused else { return }
        guard self.remainingSeconds > 0 else {
          self.advancePhase()
          return
        }
        self.remainingSeconds -= 1
      }
    }
  }

  private func advancePhase() {
    guard let configStore else { return }
    if phase == .work {
      let workMinutes = max(1, configStore.config.pomodoroWorkMinutes)
      let breakMinutes = max(1, configStore.config.pomodoroBreakMinutes)
      completionToken = UUID().uuidString
      Task { [weak self] in
        guard let self else { return }
        await self.notificationScheduler?.schedulePomodoroCompletionNotification(
          workMinutes: workMinutes,
          breakMinutes: breakMinutes
        )
      }
      phase = .shortBreak
      isPaused = false
      remainingSeconds = breakMinutes * 60
      refreshFocusSummary()
      diagnostics?.log(category: "focus", message: "Switching to break.")
    } else {
      phase = .work
      isPaused = false
      remainingSeconds = max(1, configStore.config.pomodoroWorkMinutes) * 60
      refreshFocusSummary()
      diagnostics?.log(category: "focus", message: "Switching to work.")
    }
  }

  private func refreshFocusSummary() {
    guard isEnabled else {
      focusSummary = "Focus off"
      syncWidgetSnapshot()
      return
    }

    if isPaused {
      switch phase {
      case .idle:
        focusSummary = "Focus paused"
      case .work:
        focusSummary = "Work paused"
      case .shortBreak:
        focusSummary = "Break paused"
      }
      syncWidgetSnapshot()
      return
    }

    switch phase {
    case .idle:
      focusSummary = "Focus idle"
    case .work:
      focusSummary = "Focus work"
    case .shortBreak:
      focusSummary = "Focus break"
    }
    syncWidgetSnapshot()
  }

  private func activateSession(persistConfig: Bool, emitLogs: Bool) {
    guard let configStore else { return }
    isEnabled = true
    if persistConfig, configStore.config.focusModeEnabled == false {
      configStore.update { $0.focusModeEnabled = true }
    }
    phase = .work
    isPaused = false
    remainingSeconds = max(1, configStore.config.pomodoroWorkMinutes) * 60
    refreshFocusSummary()
    runTimer()
    if emitLogs {
      diagnostics?.log(category: "focus", message: "Focus work session started.")
    }
  }

  private func deactivateSession(persistConfig: Bool, emitLogs: Bool) {
    timer?.invalidate()
    timer = nil
    phase = .idle
    isPaused = false
    remainingSeconds = 0
    isEnabled = false
    refreshFocusSummary()
    if persistConfig, let configStore, configStore.config.focusModeEnabled == true {
      configStore.update { $0.focusModeEnabled = false }
    }
    if emitLogs {
      diagnostics?.log(category: "focus", message: "Focus session stopped.")
    }
    syncWidgetSnapshot()
  }

  private enum NormalizedRule {
    case host(String)
    case hostPath(host: String, pathPrefix: String)
    case substring(String)
  }

  private struct URLBlockTarget {
    let host: String
    let path: String
    let absolute: String

    func matches(hostRule: String) -> Bool {
      host == hostRule || host.hasSuffix(".\(hostRule)")
    }

    func matches(pathPrefix: String) -> Bool {
      guard !pathPrefix.isEmpty else { return true }
      return path == pathPrefix || path.hasPrefix("\(pathPrefix)/")
    }
  }

  private func matchedBlockRule(for url: URL) -> String? {
    guard let configStore else { return nil }
    guard isEnabled else { return nil }
    guard let target = normalizedTarget(url) else { return nil }

    for raw in configStore.config.urlBlockerRules {
      guard let rule = normalizedRule(raw) else { continue }

      switch rule {
      case let .host(hostRule):
        if target.matches(hostRule: hostRule) {
          return raw
        }
      case let .hostPath(hostRule, pathPrefix):
        if target.matches(hostRule: hostRule), target.matches(pathPrefix: pathPrefix) {
          return raw
        }
      case let .substring(substring):
        if target.absolute.contains(substring) {
          return raw
        }
      }
    }

    return nil
  }

  private func normalizedTarget(_ url: URL) -> URLBlockTarget? {
    guard let normalizedURL = normalizedURL(url) else { return nil }
    guard let rawHost = normalizedURL.host else { return nil }
    let host = canonicalHost(rawHost)
    guard !host.isEmpty else { return nil }
    let path = normalizedPath(normalizedURL.path)
    let absolute = normalizedAbsoluteString(for: normalizedURL, host: host, path: path)
    return URLBlockTarget(host: host, path: path, absolute: absolute)
  }

  private func normalizedURL(_ url: URL) -> URL? {
    if url.host != nil { return url }

    let raw = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    if raw.contains("://") { return URL(string: raw) }
    return URL(string: "https://\(raw)")
  }

  private func normalizedRule(_ raw: String) -> NormalizedRule? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !value.isEmpty else { return nil }

    if value.hasPrefix("||") {
      value = value
        .replacingOccurrences(of: "||", with: "")
        .replacingOccurrences(of: "^", with: "")
    }

    if let components = ruleComponents(from: value), let rawHost = components.host {
      let host = canonicalHost(rawHost)
      guard !host.isEmpty else { return nil }
      let pathPrefix = normalizedPath(components.path)
      if pathPrefix.isEmpty {
        return .host(host)
      }
      return .hostPath(host: host, pathPrefix: pathPrefix)
    }

    if value.hasPrefix("www.") {
      value.removeFirst(4)
    }

    if value.contains("*") {
      return .substring(value.replacingOccurrences(of: "*", with: ""))
    }
    return .host(canonicalHost(value))
  }

  private func ruleComponents(from value: String) -> URLComponents? {
    if value.contains("://") {
      return URLComponents(string: value)
    }
    if value.contains("/") {
      return URLComponents(string: "https://\(value)")
    }
    return nil
  }

  private func canonicalHost(_ rawHost: String) -> String {
    var host = rawHost
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    while host.hasSuffix(".") {
      host.removeLast()
    }

    for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) {
      host.removeFirst(prefix.count)
      break
    }

    return host
  }

  private func normalizedPath(_ rawPath: String) -> String {
    var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !path.isEmpty, path != "/" else { return "" }
    if !path.hasPrefix("/") {
      path = "/\(path)"
    }
    while path.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return path
  }

  private func normalizedAbsoluteString(for url: URL, host: String, path: String) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url.absoluteString.lowercased()
    }
    let scheme = components.scheme?.lowercased()
    let query = components.query?.lowercased()
    components.scheme = scheme
    components.host = host
    components.path = path
    components.query = query
    return (components.string ?? url.absoluteString).lowercased()
  }

  private func syncWidgetSnapshot() {
    let config = configStore?.config
    let snapshot = WidgetFocusSnapshot(
      generatedAt: Date(),
      isEnabled: isEnabled,
      isPaused: isPaused,
      phase: phase.rawValue,
      summary: focusSummary,
      remainingSeconds: max(0, remainingSeconds),
      endDate: isEnabled && !isPaused && remainingSeconds > 0
        ? Date().addingTimeInterval(TimeInterval(remainingSeconds))
        : nil,
      workMinutes: max(1, config?.pomodoroWorkMinutes ?? 25),
      breakMinutes: max(1, config?.pomodoroBreakMinutes ?? 5)
    )
    FocusWidgetSnapshotStore.save(snapshot)
    WidgetSnapshotSync.reloadWidgetTimelines()
  }
}
