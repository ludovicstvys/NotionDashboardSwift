import SwiftUI

#if os(macOS)
struct FocusMenuBarLabel: View {
  @ObservedObject var focusStore: FocusStore

  var body: some View {
    Label {
      Text(focusStore.isEnabled ? labelText : "Focus")
    } icon: {
      Image(systemName: labelIcon)
        .symbolRenderingMode(.hierarchical)
    }
  }

  private var labelText: String {
    let minutes = max(0, focusStore.remainingSeconds) / 60
    return focusStore.isPaused ? "Pause" : "\(minutes)m"
  }

  private var labelIcon: String {
    if focusStore.isPaused { return "pause.circle.fill" }
    return focusStore.isEnabled ? "timer.circle.fill" : "timer"
  }
}

struct FocusMenuBarPanel: View {
  @ObservedObject var focusStore: FocusStore
  @ObservedObject var configStore: ConfigStore
  @ObservedObject var appRouter: AppRouter
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header
      timerRing
      actions
      footer
    }
    .frame(width: 330)
    .padding(20)
    .background {
      ZStack {
        LinearGradient(
          colors: [
            WorkspacePalette.panelRaised,
            WorkspacePalette.panelBase,
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        Circle()
          .fill(statusTint.opacity(0.18))
          .blur(radius: 42)
          .offset(x: 105, y: -100)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(
          LinearGradient(
            colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1
        )
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 12)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(focusStore.isEnabled ? focusStore.focusSummary : "Pomodoro ready")
          .font(.system(size: 20, weight: .semibold, design: .rounded))
          .foregroundStyle(WorkspacePalette.primaryText)
        Text(focusStore.isEnabled ? "Focus guardrails are active" : "Start a focused work block from here")
          .font(.caption)
          .foregroundStyle(WorkspacePalette.subtleText)
      }

      Spacer(minLength: 0)

      phasePill
    }
  }

  private var phasePill: some View {
    HStack(spacing: 6) {
      Image(systemName: focusStore.isPaused ? "pause.fill" : "circle.fill")
        .font(.system(size: 8, weight: .bold))
      Text(focusStore.isEnabled ? phaseLabel : "Idle")
    }
    .font(.caption.weight(.bold))
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(statusTint.opacity(0.16))
    .foregroundStyle(statusTint)
    .clipShape(Capsule())
  }

  private var timerRing: some View {
    ZStack {
      Circle()
        .stroke(WorkspacePalette.innerCard, lineWidth: 16)

      Circle()
        .trim(from: 0, to: max(0.012, progress))
        .stroke(
          AngularGradient(
            colors: [statusTint.opacity(0.60), statusTint, .white.opacity(0.86), statusTint],
            center: .center
          ),
          style: StrokeStyle(lineWidth: 16, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .shadow(color: statusTint.opacity(0.36), radius: 12, x: 0, y: 0)

      Circle()
        .fill(WorkspacePalette.panelBase.opacity(0.88))
        .frame(width: 172, height: 172)
        .overlay {
          Circle()
            .stroke(WorkspacePalette.line, lineWidth: 1)
        }

      VStack(spacing: 8) {
        Image(systemName: ringIcon)
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(statusTint)
        Text(focusStore.isEnabled ? timeText : "\(configStore.config.pomodoroWorkMinutes):00")
          .font(.system(size: 42, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(WorkspacePalette.primaryText)
        Text(focusStore.isEnabled ? phaseDetail : "work block")
          .font(.caption.weight(.semibold))
          .foregroundStyle(WorkspacePalette.subtleText)
      }
    }
    .frame(width: 230, height: 230)
    .frame(maxWidth: .infinity)
  }

  private var actions: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        Button(focusStore.isEnabled ? "Restart" : "Start") {
          focusStore.startSession()
        }
        .buttonStyle(.borderedProminent)
        .tint(statusTint)

        Button(focusStore.isPaused ? "Resume" : "Pause") {
          focusStore.togglePause()
        }
        .buttonStyle(.bordered)
        .disabled(!focusStore.isEnabled)

        Button("Stop") {
          focusStore.stopSession()
        }
        .buttonStyle(.bordered)
        .disabled(!focusStore.isEnabled)
      }

      Button {
        appRouter.select(.home)
        openWindow(id: "dashboard-main")
        NSApp.activate(ignoringOtherApps: true)
      } label: {
        Label("Open Dashboard", systemImage: "rectangle.grid.2x2.fill")
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity)
    }
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Label("\(configStore.config.urlBlockerRules.count) blocked rule(s)", systemImage: "shield.lefthalf.filled")
      Spacer()
      Text("Break \(configStore.config.pomodoroBreakMinutes)m")
    }
    .font(.caption2.weight(.semibold))
    .foregroundStyle(WorkspacePalette.subtleText)
    .padding(.top, 2)
  }

  private var statusTint: Color {
    if focusStore.isPaused { return WorkspacePalette.warning }
    return focusStore.phase == .shortBreak ? WorkspacePalette.accentSoft : WorkspacePalette.warning
  }

  private var ringIcon: String {
    if focusStore.isPaused { return "pause.circle.fill" }
    if focusStore.phase == .shortBreak { return "cup.and.saucer.fill" }
    return focusStore.isEnabled ? "bolt.fill" : "timer"
  }

  private var phaseLabel: String {
    if focusStore.isPaused { return "Paused" }
    if focusStore.phase == .shortBreak { return "Break" }
    return "Work"
  }

  private var timeText: String {
    let minutes = max(0, focusStore.remainingSeconds) / 60
    let seconds = max(0, focusStore.remainingSeconds) % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private var progress: Double {
    guard focusStore.isEnabled else { return 0 }
    let totalMinutes = focusStore.phase == .shortBreak
      ? configStore.config.pomodoroBreakMinutes
      : configStore.config.pomodoroWorkMinutes
    let total = max(1, totalMinutes * 60)
    return 1 - min(1, Double(max(0, focusStore.remainingSeconds)) / Double(total))
  }

  private var phaseDetail: String {
    if !focusStore.isEnabled {
      return "Focus off"
    }
    switch focusStore.phase {
    case .idle:
      return "Idle"
    case .work:
      return focusStore.isPaused ? "paused work session" : "\(configStore.config.pomodoroWorkMinutes)m work session"
    case .shortBreak:
      return focusStore.isPaused ? "paused break" : "\(configStore.config.pomodoroBreakMinutes)m break"
    }
  }
}

struct PomodoroPopupView: View {
  @EnvironmentObject private var focusStore: FocusStore
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var appRouter: AppRouter
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Pomodoro complete")
          .font(.system(size: 22, weight: .semibold, design: .rounded))
        Text("Your work block ended. The break starts now.")
          .font(.subheadline)
          .foregroundStyle(WorkspacePalette.subtleText)
      }

      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "timer.circle.fill")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(WorkspacePalette.warning)

        VStack(alignment: .leading, spacing: 4) {
          Text(focusStore.focusSummary)
            .font(.headline)
          Text("Break length: \(configStore.config.pomodoroBreakMinutes) minute(s)")
            .font(.caption)
            .foregroundStyle(WorkspacePalette.subtleText)
        }
      }

      HStack(spacing: 10) {
        Button("Open Dashboard") {
          appRouter.select(.home)
          openWindow(id: "dashboard-main")
          NSApp.activate(ignoringOtherApps: true)
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkspacePalette.warning)

        Button("Dismiss") {
          dismiss()
        }
        .buttonStyle(.bordered)
      }
    }
    .frame(width: 320)
    .padding(20)
    .background(
      LinearGradient(
        colors: [WorkspacePalette.panelRaised, WorkspacePalette.panelBase],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
  }
}
#endif
