import Combine
import Foundation
import SwiftUI

struct DashboardViewState: Hashable {
  var nextEvent: CalendarEvent?
  var upcomingEvents: [CalendarEvent]
  var nextTodo: TodoItem?
  var visibleTodos: [TodoItem]
  var stageLabelsByTodoID: [String: String]
  var statusCounts: [StageStatus: Int]
  var weeklyKPI: WeeklyStageKPI
  var blockers: [StageBlocker]
  var qualityIssues: [StageQualityIssue]
  var openTodoCount: Int
  var overdueTodoCount: Int
  var pendingQueueCount: Int

  static let empty = DashboardViewState(
    nextEvent: nil,
    upcomingEvents: [],
    nextTodo: nil,
    visibleTodos: [],
    stageLabelsByTodoID: [:],
    statusCounts: [:],
    weeklyKPI: .empty,
    blockers: [],
    qualityIssues: [],
    openTodoCount: 0,
    overdueTodoCount: 0,
    pendingQueueCount: 0
  )
}

@MainActor
final class DashboardViewModel: ObservableObject {
  @Published private(set) var state: DashboardViewState = .empty

  private let stageRepository: StageRepository
  private let todoRepository: TodoRepository
  private let calendarRepository: CalendarRepository
  private weak var stageStore: StageStore?
  private weak var appRouter: AppRouter?
  private var cancellables: Set<AnyCancellable> = []
  private var reloadTask: Task<Void, Never>?
  private var reloadDebounceTask: Task<Void, Never>?

  init(
    stageRepository: StageRepository,
    todoRepository: TodoRepository,
    calendarRepository: CalendarRepository,
    stageStore: StageStore,
    calendarStore: CalendarStore,
    appRouter: AppRouter
  ) {
    self.stageRepository = stageRepository
    self.todoRepository = todoRepository
    self.calendarRepository = calendarRepository
    self.stageStore = stageStore
    self.appRouter = appRouter

    stageStore.$stageRevision
      .sink { [weak self] _ in self?.scheduleReload() }
      .store(in: &cancellables)

    stageStore.$todoRevision
      .sink { [weak self] _ in self?.scheduleReload() }
      .store(in: &cancellables)

    stageStore.$metricsRevision
      .sink { [weak self] _ in self?.scheduleReload() }
      .store(in: &cancellables)

    calendarStore.$calendarRevision
      .sink { [weak self] _ in self?.scheduleReload() }
      .store(in: &cancellables)

    appRouter.$route
      .sink { [weak self] _ in self?.scheduleReload() }
      .store(in: &cancellables)

    reload()
  }

  func reload() {
    reloadTask?.cancel()
    let focusedTodoID = appRouter?.route.todoID
    let pendingQueueCount = stageStore?.pendingQueueCount ?? 0
    let stageRepository = self.stageRepository
    let todoRepository = self.todoRepository
    let calendarRepository = self.calendarRepository
    weak var weakSelf = self

    reloadTask = Task.detached(priority: .userInitiated) {
      let calendarState = calendarRepository.fetchViewState()
      let visibleTodos = todoRepository.fetchVisibleTodos(limit: 6, focusedTodoID: focusedTodoID)
      let stageLabels = stageRepository.fetchStageLabelMap(ids: Set(visibleTodos.map(\.relatedStageID)))
      let stageLabelsByTodoID = Dictionary(uniqueKeysWithValues: visibleTodos.map { todo in
        (todo.id, stageLabels[todo.relatedStageID] ?? "")
      })
      let nextState = DashboardViewState(
        nextEvent: calendarState.nextUpcomingEvent,
        upcomingEvents: calendarState.upcomingEvents,
        nextTodo: todoRepository.fetchNextTodo(),
        visibleTodos: visibleTodos,
        stageLabelsByTodoID: stageLabelsByTodoID,
        statusCounts: stageRepository.fetchStatusCounts(),
        weeklyKPI: stageRepository.fetchWeeklyKPI(),
        blockers: stageRepository.fetchBlockers(limit: 4),
        qualityIssues: stageRepository.fetchQualityIssues(limit: 5),
        openTodoCount: todoRepository.fetchOpenTodoCount(),
        overdueTodoCount: todoRepository.fetchOverdueTodoCount(),
        pendingQueueCount: pendingQueueCount
      )
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let strongSelf = weakSelf else { return }
        strongSelf.state = nextState
      }
    }
  }

  private func scheduleReload() {
    reloadDebounceTask?.cancel()
    reloadDebounceTask = Task {
      try? await Task.sleep(nanoseconds: 100_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self.reload()
      }
    }
  }
}

@MainActor
final class StagesViewModel: ObservableObject {
  @Published private(set) var listState: StagesListViewState = .empty
  @Published private(set) var selectedStageDetail: StageDetailViewState?
  @Published private(set) var searchQuery: String = ""

  private let stageRepository: StageRepository
  private weak var stageStore: StageStore?
  private weak var appRouter: AppRouter?
  private let pageSize = 40
  private var currentOffset = 0
  private var cancellables: Set<AnyCancellable> = []
  private var reloadTask: Task<Void, Never>?
  private var reloadDebounceTask: Task<Void, Never>?
  private var selectionTask: Task<Void, Never>?
  private var loadMoreTask: Task<Void, Never>?
  private var isLoadingMore = false

  init(stageRepository: StageRepository, stageStore: StageStore, appRouter: AppRouter) {
    self.stageRepository = stageRepository
    self.stageStore = stageStore
    self.appRouter = appRouter

    stageStore.$stageRevision
      .sink { [weak self] _ in self?.scheduleReload(resetPagination: true) }
      .store(in: &cancellables)

    stageStore.$todoRevision
      .sink { [weak self] _ in self?.scheduleReload(resetPagination: true) }
      .store(in: &cancellables)

    stageStore.$metricsRevision
      .sink { [weak self] _ in self?.scheduleReload(resetPagination: true) }
      .store(in: &cancellables)

    appRouter.$route
      .sink { [weak self] route in
        guard route.destination == .stages else { return }
        self?.focusStage(id: route.stageID)
      }
      .store(in: &cancellables)

    reload(resetPagination: true)
  }

  func updateSearchQuery(_ query: String) {
    searchQuery = query
    reload(resetPagination: true)
  }

  func loadMoreIfNeeded(currentItemID: String) {
    guard listState.hasMore else { return }
    guard currentItemID == listState.items.last?.id else { return }
    guard !isLoadingMore else { return }
    isLoadingMore = true
    currentOffset += pageSize

    let stageRepository = self.stageRepository
    let searchQuery = self.searchQuery
    let offset = self.currentOffset
    let pendingQueueCount = stageStore?.pendingQueueCount ?? 0
    weak var weakSelf = self

    loadMoreTask?.cancel()
    loadMoreTask = Task.detached(priority: .userInitiated) {
      let next = stageRepository.fetchListState(
        searchQuery: searchQuery,
        limit: 40,
        offset: offset,
        pendingQueueCount: pendingQueueCount
      )
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let strongSelf = weakSelf else { return }
        strongSelf.listState.items.append(contentsOf: next.items)
        strongSelf.listState.totalCount = next.totalCount
        strongSelf.listState.hasMore = next.hasMore
        strongSelf.listState.blockersCount = next.blockersCount
        strongSelf.listState.pendingQueueCount = next.pendingQueueCount
        strongSelf.isLoadingMore = false
      }
    }
  }

  func selectStage(id: String?) {
    selectionTask?.cancel()
    guard let id else {
      selectedStageDetail = nil
      return
    }
    let stageRepository = self.stageRepository
    weak var weakSelf = self
    selectionTask = Task.detached(priority: .userInitiated) {
      let detail = stageRepository.fetchStageDetail(stageID: id)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let strongSelf = weakSelf else { return }
        strongSelf.selectedStageDetail = detail
      }
    }
  }

  func reload(resetPagination: Bool) {
    reloadTask?.cancel()
    if resetPagination {
      currentOffset = 0
    }
    let searchQuery = self.searchQuery
    let offset = self.currentOffset
    let pendingQueueCount = stageStore?.pendingQueueCount ?? 0
    let targetStageID = appRouter?.route.stageID ?? selectedStageDetail?.stage.id
    let stageRepository = self.stageRepository
    weak var weakSelf = self

    reloadTask = Task.detached(priority: .userInitiated) {
      let nextState = stageRepository.fetchListState(
        searchQuery: searchQuery,
        limit: 40,
        offset: offset,
        pendingQueueCount: pendingQueueCount
      )
      let selectedID = targetStageID ?? nextState.items.first?.id
      let detail = selectedID.flatMap { stageRepository.fetchStageDetail(stageID: $0) }
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let strongSelf = weakSelf else { return }
        if resetPagination {
          strongSelf.listState = nextState
        } else {
          strongSelf.listState.items.append(contentsOf: nextState.items)
          strongSelf.listState.totalCount = nextState.totalCount
          strongSelf.listState.hasMore = nextState.hasMore
          strongSelf.listState.blockersCount = nextState.blockersCount
          strongSelf.listState.pendingQueueCount = nextState.pendingQueueCount
        }
        strongSelf.selectedStageDetail = detail
        strongSelf.isLoadingMore = false
      }
    }
  }

  private func scheduleReload(resetPagination: Bool) {
    reloadDebounceTask?.cancel()
    reloadDebounceTask = Task {
      try? await Task.sleep(nanoseconds: 100_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self.reload(resetPagination: resetPagination)
      }
    }
  }

  private func focusStage(id: String?) {
    if let id {
      selectStage(id: id)
      return
    }
    if selectedStageDetail == nil {
      selectStage(id: listState.items.first?.id)
    }
  }
}

@MainActor
final class CalendarViewModel: ObservableObject {
  @Published private(set) var state: CalendarViewState = .empty

  private let calendarRepository: CalendarRepository
  private var cancellables: Set<AnyCancellable> = []
  private var reloadTask: Task<Void, Never>?
  private var reloadDebounceTask: Task<Void, Never>?

  init(calendarRepository: CalendarRepository, calendarStore: CalendarStore) {
    self.calendarRepository = calendarRepository
    calendarStore.$calendarRevision
      .sink { [weak self] _ in self?.scheduleReload() }
      .store(in: &cancellables)

    reload()
  }

  func reload() {
    reloadTask?.cancel()
    let calendarRepository = self.calendarRepository
    weak var weakSelf = self
    reloadTask = Task.detached(priority: .userInitiated) {
      let nextState = calendarRepository.fetchViewState()
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let strongSelf = weakSelf else { return }
        strongSelf.state = nextState
      }
    }
  }

  private func scheduleReload() {
    reloadDebounceTask?.cancel()
    reloadDebounceTask = Task {
      try? await Task.sleep(nanoseconds: 100_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self.reload()
      }
    }
  }

  func event(id: String) -> CalendarEvent? {
    calendarRepository.fetchEvent(id: id)
  }
}
