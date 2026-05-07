import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct NotionDashboardApp: App {
  @StateObject private var container = AppContainer()

  var body: some Scene {
    WindowGroup("Dashboard", id: "dashboard-main") {
      AppRootView(container: container)
    }
    WindowGroup("Pomodoro", id: "pomodoro-popup") {
      PomodoroPopupView()
    }
#if os(macOS)
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") {
          Task { await container.updateStore.checkForUpdates(userInitiated: true) }
        }
        .keyboardShortcut("u")
      }
    }
#endif

#if os(macOS)
    MenuBarExtra {
      FocusMenuBarPanel(
        focusStore: container.focusStore,
        configStore: container.configStore,
        appRouter: container.appRouter
      )
    } label: {
      FocusMenuBarLabel(focusStore: container.focusStore)
    }
    .menuBarExtraStyle(.window)
#endif
  }
}

private struct AppRootView: View {
  let container: AppContainer
  @Environment(\.openWindow) private var openWindow
  @State private var lastPresentedToken: String = ""

  var body: some View {
    RootView()
      .environmentObject(container.appRouter)
      .environmentObject(container.diagnosticsStore)
      .environmentObject(container.configStore)
      .environmentObject(container.updateStore)
      .environmentObject(container.googleAuthStore)
      .environmentObject(container.notificationScheduler)
      .environmentObject(container.focusStore)
      .environmentObject(container.stageStore)
      .environmentObject(container.calendarStore)
      .environmentObject(container.marketNewsStore)
      .environmentObject(container.dashboardViewModel)
      .environmentObject(container.stagesViewModel)
      .environmentObject(container.calendarViewModel)
      .onOpenURL { url in
        container.appRouter.handle(url: url)
      }
      .onChange(of: container.focusStore.completionToken) { token in
        guard !token.isEmpty, token != lastPresentedToken else { return }
        lastPresentedToken = token
        openWindow(id: "pomodoro-popup")
        NSApp.activate(ignoringOtherApps: true)
      }
  }
}
