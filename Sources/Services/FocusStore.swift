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

  private var timer: Timer?
  private weak var configStore: ConfigStore?
  private weak var diagnostics: DiagnosticsStore?

  init(configStore: ConfigStore, diagnostics: DiagnosticsStore?) {
    self.configStore = configStore
    self.diagnostics = diagnostics
    self.isEnabled = configStore.config.focusModeEnabled
    if self.isEnabled {
      phase = .work
      remainingSeconds = max(1, configStore.config.pomodoroWorkMinutes) * 60
      runTimer()
    }
  }

  deinit {
    timer?.invalidate()
  }

  func startSession() {
    guard let configStore else { return }
    isEnabled = true
    configStore.update { $0.focusModeEnabled = true }
    phase = .work
    remainingSeconds = max(1, configStore.config.pomodoroWorkMinutes) * 60
    runTimer()
    diagnostics?.log(category: "focus", message: "Focus work session started.")
  }

  func stopSession() {
    timer?.invalidate()
    timer = nil
    phase = .idle
    remainingSeconds = 0
    isEnabled = false
    configStore?.update { $0.focusModeEnabled = false }
    diagnostics?.log(category: "focus", message: "Focus session stopped.")
  }

  func setEnabled(_ enabled: Bool) {
    if enabled {
      startSession()
    } else {
      stopSession()
    }
  }

  func isBlocked(url: URL) -> Bool {
    guard let configStore else { return false }
    guard isEnabled else { return false }
    let host = (url.host ?? "").lowercased()
    if host.isEmpty { return false }
    return configStore.config.urlBlockerRules.contains { raw in
      let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !rule.isEmpty else { return false }
      if rule.hasPrefix("||") {
        let clean = rule
          .replacingOccurrences(of: "||", with: "")
          .replacingOccurrences(of: "^", with: "")
        return host == clean || host.hasSuffix(".\(clean)")
      }
      if rule.contains("/") {
        return url.absoluteString.lowercased().contains(rule)
      }
      return host == rule || host.hasSuffix(".\(rule)")
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
      diagnostics?.log(category: "focus", message: "Switching to break.")
    } else {
      phase = .work
      remainingSeconds = max(1, configStore.config.pomodoroWorkMinutes) * 60
      diagnostics?.log(category: "focus", message: "Switching to work.")
    }
  }
}
