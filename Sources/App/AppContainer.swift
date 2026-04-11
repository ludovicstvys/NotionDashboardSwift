import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
  let diagnosticsStore: DiagnosticsStore
  let configStore: ConfigStore
  let updateStore: UpdateStore
  let googleAuthStore: GoogleAuthStore
  let notificationScheduler: NotificationScheduler
  let focusStore: FocusStore
  let stageStore: StageStore
  let calendarStore: CalendarStore
  let marketNewsStore: MarketNewsStore

  init() {
    let diagnostics = DiagnosticsStore()
    self.diagnosticsStore = diagnostics
    let config = ConfigStore()
    self.configStore = config
    self.updateStore = UpdateStore(diagnostics: diagnostics)
    let auth = GoogleAuthStore(configStore: config, diagnostics: diagnostics)
    self.googleAuthStore = auth
    let focus = FocusStore(configStore: config, diagnostics: diagnostics)
    self.focusStore = focus
    let notificationScheduler = NotificationScheduler(diagnostics: diagnostics, focusStore: focus)
    self.notificationScheduler = notificationScheduler
    self.stageStore = StageStore(configStore: config, diagnostics: diagnostics)
    self.calendarStore = CalendarStore(
      configStore: config,
      googleAuthStore: auth,
      notificationScheduler: notificationScheduler,
      diagnostics: diagnostics
    )
    self.marketNewsStore = MarketNewsStore(configStore: config, diagnostics: diagnostics)
  }
}
