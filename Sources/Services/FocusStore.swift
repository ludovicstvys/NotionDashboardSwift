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
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var remainingSeconds: Int = 0
  @Published private(set) var focusSummary: String = "Focus off"

  private var timer: Timer?
  private weak var configStore: ConfigStore?
  private weak var diagnostics: DiagnosticsStore?
  private var cancellables: Set<AnyCancellable> = []

  init(configStore: ConfigStore, diagnostics: DiagnosticsStore?) {
    self.configStore = configStore
    self.diagnostics = diagnostics
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
    guard let configStore else { return false }
    guard isEnabled else { return false }
    guard let normalizedURL = normalizedURL(url) else { return false }
    let host = (normalizedURL.host ?? "").lowercased()
    if host.isEmpty { return false }
    let absolute = normalizedURL.absoluteString.lowercased()

    return configStore.config.urlBlockerRules.contains { raw in
      guard let rule = normalizedRule(raw) else { return false }

      switch rule {
      case let .host(hostRule):
        return host == hostRule || host.hasSuffix(".\(hostRule)")
      case let .absolute(substring):
        return absolute.contains(substring)
      }
    }
  }

  func blockedReason(for url: URL) -> String {
    "Blocked by focus mode: \(url.host ?? url.absoluteString)"
  }

  private func runTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
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
      phase = .shortBreak
      remainingSeconds = max(1, configStore.config.pomodoroBreakMinutes) * 60
      refreshFocusSummary()
      diagnostics?.log(category: "focus", message: "Switching to break.")
    } else {
      phase = .work
      remainingSeconds = max(1, configStore.config.pomodoroWorkMinutes) * 60
      refreshFocusSummary()
      diagnostics?.log(category: "focus", message: "Switching to work.")
    }
  }

  private func refreshFocusSummary() {
    guard isEnabled else {
      focusSummary = "Focus off"
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
  }

  private func activateSession(persistConfig: Bool, emitLogs: Bool) {
    guard let configStore else { return }
    isEnabled = true
    if persistConfig, configStore.config.focusModeEnabled == false {
      configStore.update { $0.focusModeEnabled = true }
    }
    phase = .work
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
    remainingSeconds = 0
    isEnabled = false
    refreshFocusSummary()
    if persistConfig, let configStore, configStore.config.focusModeEnabled == true {
      configStore.update { $0.focusModeEnabled = false }
    }
    if emitLogs {
      diagnostics?.log(category: "focus", message: "Focus session stopped.")
    }
  }

  private enum NormalizedRule {
    case host(String)
    case absolute(String)
  }

  private func normalizedURL(_ url: URL) -> URL? {
    if url.host != nil {
      return url
    }

    let raw = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    if raw.contains("://") {
      return URL(string: raw)
    }
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

    if value.contains("://"), let host = URL(string: value)?.host?.lowercased(), !host.isEmpty {
      return .host(host)
    }

    if value.hasPrefix("www.") {
      value.removeFirst(4)
    }

    if value.contains("/") {
      return .absolute(value)
    }
    return .host(value)
  }
}
