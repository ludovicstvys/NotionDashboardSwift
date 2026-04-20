import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
  let appRouter: AppRouter
  let appDatabase: AppDatabase
  let diagnosticsStore: DiagnosticsStore
  let configStore: ConfigStore
  let updateStore: UpdateStore
  let googleAuthStore: GoogleAuthStore
  let notificationScheduler: NotificationScheduler
  let focusStore: FocusStore
  let stageStore: StageStore
  let calendarStore: CalendarStore
  let marketNewsStore: MarketNewsStore
  let stageRepository: StageRepository
  let todoRepository: TodoRepository
  let calendarRepository: CalendarRepository
  let dashboardViewModel: DashboardViewModel
  let stagesViewModel: StagesViewModel
  let calendarViewModel: CalendarViewModel

  init() {
    self.appRouter = AppRouter()
    let appDatabase = AppDatabase()
    self.appDatabase = appDatabase
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
    let stageRepository = StageRepository(appDatabase: appDatabase)
    self.stageRepository = stageRepository
    let todoRepository = TodoRepository(appDatabase: appDatabase)
    self.todoRepository = todoRepository
    let calendarRepository = CalendarRepository(appDatabase: appDatabase)
    self.calendarRepository = calendarRepository
    let stageStore = StageStore(
      configStore: config,
      diagnostics: diagnostics,
      stageRepository: stageRepository,
      todoRepository: todoRepository
    )
    self.stageStore = stageStore
    let calendarStore = CalendarStore(
      configStore: config,
      googleAuthStore: auth,
      notificationScheduler: notificationScheduler,
      diagnostics: diagnostics,
      calendarRepository: calendarRepository
    )
    self.calendarStore = calendarStore
    self.marketNewsStore = MarketNewsStore(configStore: config, diagnostics: diagnostics)
    self.dashboardViewModel = DashboardViewModel(
      stageRepository: stageRepository,
      todoRepository: todoRepository,
      calendarRepository: calendarRepository,
      stageStore: stageStore,
      calendarStore: calendarStore,
      appRouter: appRouter
    )
    self.stagesViewModel = StagesViewModel(
      stageRepository: stageRepository,
      stageStore: stageStore,
      appRouter: appRouter
    )
    self.calendarViewModel = CalendarViewModel(
      calendarRepository: calendarRepository,
      calendarStore: calendarStore
    )
  }
}
