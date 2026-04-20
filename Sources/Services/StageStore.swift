import Foundation
import SwiftUI

@MainActor
final class StageStore: ObservableObject {
  private enum NotionSyncTrigger {
    case manual
    case launch
  }

  private enum QueueFlushPolicy {
    case keepFailures
    case dropFailures
  }

  @Published private(set) var stages: [Stage] = []
  @Published private(set) var todos: [TodoItem] = []
  @Published private(set) var pendingOperations: [PendingNotionOperation] = []
  @Published var isSyncingNotion: Bool = false
  @Published var syncMessage: String = ""
  @Published private(set) var lastSuccessfulNotionSyncDate: Date?
  @Published private(set) var sortedTodos: [TodoItem] = []
  @Published private(set) var weeklyKPI: WeeklyStageKPI = .empty
  @Published private(set) var blockers: [StageBlocker] = []
  @Published private(set) var qualityIssues: [StageQualityIssue] = []
  @Published private(set) var statusCounts: [StageStatus: Int] = [:]
  @Published private(set) var stageRevision: Int = 0
  @Published private(set) var todoRevision: Int = 0
  @Published private(set) var metricsRevision: Int = 0
  @Published private(set) var dataRevision: Int = 0

  private let stagesStorageKey = "swift_notion_dashboard_stages_v1"
  private let todosStorageKey = "swift_notion_dashboard_todos_v1"
  private let queueStorageKey = "swift_notion_dashboard_notion_queue_v1"
  private let lastSuccessfulSyncDateKey = "swift_notion_dashboard_notion_last_successful_sync_v1"
  private let launchSyncStaleInterval: TimeInterval = 15 * 60
  private let defaults: UserDefaults
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let notionClient: NotionClient
  private let stageRepository: StageRepository?
  private let todoRepository: TodoRepository?
  private let persistenceScheduler = DebouncedWorkScheduler(
    label: "com.loldashboard.notiondashboard.stage-store-persist",
    delay: 0.18
  )
  private weak var configStore: ConfigStore?
  private weak var diagnostics: DiagnosticsStore?
  private var stageSearchIndex: [String: String] = [:]

  init(
    configStore: ConfigStore,
    defaults: UserDefaults = .standard,
    diagnostics: DiagnosticsStore? = nil,
    notionClient: NotionClient? = nil,
    stageRepository: StageRepository? = nil,
    todoRepository: TodoRepository? = nil
  ) {
    self.configStore = configStore
    self.defaults = defaults
    self.diagnostics = diagnostics
    self.notionClient = notionClient ?? NotionClient(diagnostics: diagnostics)
    self.stageRepository = stageRepository
    self.todoRepository = todoRepository

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder

    load()
  }

  func filteredStages(matching rawQuery: String) -> [Stage] {
    let query = rawQuery.normalizedToken
    guard !query.isEmpty else { return stages }
    return stages.filter { stage in
      stageSearchIndex[stage.id, default: ""].contains(query)
    }
  }

  func prepareForLaunch() async {
    guard let configStore else { return }
    guard configStore.config.hasNotionCredentials else { return }
    guard shouldSyncAtLaunch else { return }
    await syncFromNotion(trigger: .launch)
  }

  func updateStageStatus(stageID: String, to newStatus: StageStatus) async {
    guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
    guard let configStore else { return }
    stages[index].status = newStatus
    stages[index].updatedAt = Date()
    let updated = stages[index]
    persist(
      immediateDatabase: true,
      stageChanged: true,
      todoChanged: false,
      metricsChanged: true,
      preferDeltaWrite: true,
      upsertedStages: [updated]
    )

    if configStore.config.hasNotionCredentials {
      do {
        if let notionPageID = notionPageID(for: updated) {
          try await notionClient.updateStageStatus(pageID: notionPageID, status: newStatus, config: configStore.config)
        } else {
          await syncSingleStageIfPossible(stageID: stageID)
          return
        }
        diagnostics?.log(
          category: "notion",
          message: "Stage status updated.",
          metadata: ["stageID": stageID, "notionPageID": notionPageID(for: updated) ?? ""]
        )
      } catch {
        let queueItem: PendingNotionOperation
        if let notionPageID = notionPageID(for: updated), isLikelyNotionPageID(notionPageID) {
          queueItem = PendingNotionOperation(
            kind: .updateStatus,
            stage: nil,
            stageID: notionPageID,
            status: newStatus,
            createdAt: Date(),
            retryCount: 0
          )
        } else {
          queueItem = PendingNotionOperation(
            kind: .upsertStage,
            stage: updated,
            stageID: updated.id,
            status: nil,
            createdAt: Date(),
            retryCount: 0
          )
        }
        enqueue(queueItem)
        syncMessage = "Status queued (offline/retry): \(error.localizedDescription)"
        diagnostics?.log(
          severity: .warning,
          category: "notion-queue",
          message: "Queued status update.",
          metadata: ["stageID": stageID, "error": error.localizedDescription]
        )
      }
    }
  }

  func deleteStage(stageID: String) {
    let deletedTodoIDs = Set(todos.filter { $0.relatedStageID == stageID }.map(\.id))
    stages.removeAll { $0.id == stageID }
    todos.removeAll { $0.relatedStageID == stageID }
    persist(
      immediateDatabase: true,
      stageChanged: true,
      todoChanged: !deletedTodoIDs.isEmpty,
      metricsChanged: true,
      preferDeltaWrite: true,
      deletedStageIDs: Set([stageID]),
      deletedTodoIDs: deletedTodoIDs
    )
  }

  func setTodoStatus(todoID: String, status: TodoStatus) {
    guard let index = todos.firstIndex(where: { $0.id == todoID }) else { return }
    guard todos[index].automationTag.hasPrefix("notion:") else { return }
    todos[index].status = status
    persist(
      immediateDatabase: true,
      stageChanged: false,
      todoChanged: true,
      metricsChanged: false,
      preferDeltaWrite: true,
      upsertedTodos: [todos[index]]
    )
  }

  func syncFromNotion() async {
    await syncFromNotion(trigger: .manual)
  }

  private func syncFromNotion(trigger: NotionSyncTrigger) async {
    guard let configStore else { return }
    guard configStore.config.hasNotionCredentials else {
      if trigger == .manual {
        syncMessage = "Missing Notion token/database config."
      }
      return
    }
    guard !isSyncingNotion else { return }

    isSyncingNotion = true
    defer { isSyncingNotion = false }

    if trigger == .manual {
      syncMessage = "Syncing all Notion stages..."
    }

    await flushPendingOperations(policy: .keepFailures)

    let incrementalCutoff: Date?
    switch trigger {
    case .manual:
      incrementalCutoff = nil
    case .launch:
      if shouldUseIncrementalLaunchSync {
        incrementalCutoff = lastSuccessfulNotionSyncDate?.addingTimeInterval(-300)
      } else {
        incrementalCutoff = nil
      }
    }

    do {
      let remoteStages = try await notionClient.fetchStages(
        config: configStore.config,
        updatedAfter: incrementalCutoff
      )
      let completedAt = Date()
      lastSuccessfulNotionSyncDate = completedAt

      if incrementalCutoff == nil {
        reconcileFullNotionRefresh(remoteStages)
      } else {
        remoteStages.forEach { remote in
          _ = upsertLocalStage(remote)
        }
      }

      if !configStore.config.notionTodoDbId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let stagePageIDToLocalID: [String: String] = stages.reduce(into: [:]) { partial, stage in
          guard let notionPageID = notionPageID(for: stage) else { return }
          partial[notionPageID] = stage.id
        }
        let remoteTodos = try await notionClient.fetchTodos(
          config: configStore.config,
          stagePageIDToLocalID: stagePageIDToLocalID
        )
        mergeRemoteTodos(remoteTodos)
      } else if !todos.isEmpty {
        todos = []
      }

      persist()
      let message = incrementalCutoff == nil
        ? "Notion sync done (\(remoteStages.count) stages)."
        : "Notion sync refreshed (\(remoteStages.count) changed stages)."
      if trigger == .manual {
        syncMessage = message
      }
      diagnostics?.log(
        category: "notion-sync",
        message: message,
        metadata: ["trigger": trigger == .manual ? "manual" : "launch"]
      )
    } catch {
      let message = "Notion sync failed: \(error.localizedDescription)"
      if trigger == .manual || stages.isEmpty {
        syncMessage = message
      }
      diagnostics?.log(
        severity: .error,
        category: "notion-sync",
        message: message,
        metadata: ["trigger": trigger == .manual ? "manual" : "launch"]
      )
    }
  }

  func pushAllToNotion() async {
    guard let configStore else { return }
    guard configStore.config.hasNotionCredentials else {
      syncMessage = "Missing Notion token/database config."
      return
    }
    guard !isSyncingNotion else { return }

    isSyncingNotion = true
    defer { isSyncingNotion = false }

    await flushPendingOperations(policy: .keepFailures)

    for stage in stages {
      do {
        let notionPageID = try await notionClient.upsertStage(
          stage,
          config: configStore.config,
          knownPageID: notionPageID(for: stage)
        )
        updateNotionPageID(for: stage.id, notionPageID: notionPageID)
      } catch {
        enqueue(
          PendingNotionOperation(
            kind: .upsertStage,
            stage: stage,
            stageID: stage.id,
            status: nil,
            createdAt: Date(),
            retryCount: 0
          )
        )
        diagnostics?.log(
          severity: .warning,
          category: "notion-queue",
          message: "Queued stage upsert during push.",
          metadata: ["stageID": stage.id, "error": error.localizedDescription]
        )
      }
    }

    syncMessage = "Push to Notion done (\(stages.count) stages, queue: \(pendingOperations.count))."
    diagnostics?.log(category: "notion-push", message: syncMessage)
  }

  func flushPendingOperations() async {
    await flushPendingOperations(policy: .dropFailures)
  }

  private func flushPendingOperations(policy: QueueFlushPolicy) async {
    guard let configStore else {
      syncMessage = "Config unavailable."
      return
    }
    if !configStore.config.hasNotionCredentials {
      if policy == .dropFailures {
        let droppedCount = pendingOperations.count
        pendingOperations = []
        persist(stageChanged: false, todoChanged: false, metricsChanged: true)
        syncMessage = droppedCount == 0
          ? "Queue already empty."
          : "Queue flushed locally (\(droppedCount) dropped, no Notion credentials)."
      } else {
        syncMessage = "Missing Notion token/database config. Queue kept (\(pendingOperations.count))."
      }
      return
    }
    guard !pendingOperations.isEmpty else {
      syncMessage = "Queue already empty."
      return
    }

    let operations = pendingOperations.sorted { $0.createdAt < $1.createdAt }
    let totalCount = operations.count
    pendingOperations = []
    persist(stageChanged: false, todoChanged: false, metricsChanged: true)
    syncMessage = "Flushing queue (\(totalCount))..."

    var stillPending: [PendingNotionOperation] = []
    for operation in operations {
      do {
        switch operation.kind {
        case .upsertStage:
          guard let stage = operation.stage else { continue }
          let notionPageID = try await notionClient.upsertStage(
            stage,
            config: configStore.config,
            knownPageID: notionPageID(for: stage)
          )
          updateNotionPageID(for: stage.id, notionPageID: notionPageID)
        case .updateStatus:
          guard let stageID = operation.stageID, let status = operation.status else { continue }
          try await notionClient.updateStageStatus(pageID: stageID, status: status, config: configStore.config)
        }
      } catch {
        var next = operation
        next.retryCount += 1
        stillPending.append(next)
      }
    }

    let droppedCount: Int
    switch policy {
    case .keepFailures:
      pendingOperations = stillPending.sorted { $0.createdAt < $1.createdAt }
      droppedCount = 0
    case .dropFailures:
      pendingOperations = []
      droppedCount = stillPending.count
    }

    persist(stageChanged: false, todoChanged: false, metricsChanged: true)
    let syncedCount = totalCount - stillPending.count
    switch policy {
    case .keepFailures:
      syncMessage = stillPending.isEmpty
        ? "Queue flush complete (\(syncedCount)/\(totalCount))."
        : "Queue flush partial (\(syncedCount)/\(totalCount) synced, \(stillPending.count) pending)."
    case .dropFailures:
      syncMessage = droppedCount == 0
        ? "Queue flushed (\(syncedCount)/\(totalCount) synced)."
        : "Queue flushed (\(syncedCount) synced, \(droppedCount) dropped)."
    }

    diagnostics?.log(
      severity: (policy == .keepFailures && !stillPending.isEmpty) ? .warning : .info,
      category: "notion-queue",
      message: "Queue flush done.",
      metadata: [
        "policy": policy == .keepFailures ? "keep-failures" : "drop-failures",
        "total": "\(totalCount)",
        "synced": "\(syncedCount)",
        "remaining": "\(pendingOperations.count)",
        "dropped": "\(droppedCount)",
      ]
    )
  }

  func testNotionConnection() async -> String {
    guard let configStore else { return "Config store unavailable." }
    do {
      try await notionClient.testConnection(config: configStore.config)
      diagnostics?.log(category: "notion-test", message: "Notion connection OK.")
      return "Notion connection OK."
    } catch {
      diagnostics?.log(
        severity: .error,
        category: "notion-test",
        message: "Notion connection failed.",
        metadata: ["error": error.localizedDescription]
      )
      return "Notion connection error: \(error.localizedDescription)"
    }
  }

  func applyQualityFix(_ issue: StageQualityIssue) async {
    guard let index = stages.firstIndex(where: { $0.id == issue.stage.id }) else { return }
    switch issue.field {
    case .company:
      stages[index].company = issue.suggestedValue
    case .url:
      stages[index].url = issue.suggestedValue
    case .deadline:
      if
        let date = Date.fallbackISO8601.date(from: issue.suggestedValue) ??
          Date.iso8601WithFractionalSeconds.date(from: issue.suggestedValue)
      {
        stages[index].deadline = date
      } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        stages[index].deadline = formatter.date(from: issue.suggestedValue)
      }
    }
    stages[index].updatedAt = Date()
    persist(
      immediateDatabase: true,
      stageChanged: true,
      todoChanged: false,
      metricsChanged: true,
      preferDeltaWrite: true,
      upsertedStages: [stages[index]]
    )
    await syncSingleStageIfPossible(
      stageID: stages[index].id,
      successMessage: "Quality fix synced to Notion.",
      queuedMessagePrefix: "Quality fix queued (offline/retry)"
    )
  }

  var pendingQueueCount: Int {
    pendingOperations.count
  }

  private func syncSingleStageIfPossible(
    stageID: String,
    successMessage: String = "Stage synced to Notion.",
    queuedMessagePrefix: String = "Stage queued (offline/retry)"
  ) async {
    guard let configStore else { return }
    guard configStore.config.hasNotionCredentials else { return }
    guard let stage = stages.first(where: { $0.id == stageID }) else { return }
    do {
      let notionPageID = try await notionClient.upsertStage(
        stage,
        config: configStore.config,
        knownPageID: notionPageID(for: stage)
      )
      updateNotionPageID(for: stage.id, notionPageID: notionPageID)
      syncMessage = successMessage
      diagnostics?.log(
        category: "notion",
        message: successMessage,
        metadata: ["stageID": stage.id, "notionPageID": notionPageID]
      )
    } catch {
      enqueue(
        PendingNotionOperation(
          kind: .upsertStage,
          stage: stage,
          stageID: stage.id,
          status: nil,
          createdAt: Date(),
          retryCount: 0
        )
      )
      syncMessage = "\(queuedMessagePrefix): \(error.localizedDescription)"
      diagnostics?.log(
        severity: .warning,
        category: "notion-queue",
        message: "Queued stage upsert.",
        metadata: ["stageID": stage.id, "error": error.localizedDescription]
      )
    }
  }

  @discardableResult
  private func upsertLocalStage(_ incoming: Stage) -> Stage {
    if let idIndex = stages.firstIndex(where: { $0.id == incoming.id }) {
      var merged = incoming
      merged.createdAt = stages[idIndex].createdAt
      merged.notionPageID = merged.notionPageID ?? stages[idIndex].notionPageID
      stages[idIndex] = merged
      return merged
    }

    if let duplicateIndex = stages.firstIndex(where: { isDuplicate($0, incoming) }) {
      var merged = incoming
      let existing = stages[duplicateIndex]
      merged.id = existing.id
      merged.createdAt = existing.createdAt
      merged.updatedAt = max(existing.updatedAt, incoming.updatedAt)
      merged.notionPageID = merged.notionPageID ?? existing.notionPageID
      if merged.source.isEmpty { merged.source = existing.source }
      stages[duplicateIndex] = merged
      return merged
    }

    stages.append(incoming)
    stages.sort { $0.updatedAt > $1.updatedAt }
    return incoming
  }

  private func isDuplicate(_ lhs: Stage, _ rhs: Stage) -> Bool {
    let leftURL = canonicalURL(lhs.url)
    let rightURL = canonicalURL(rhs.url)
    if !leftURL.isEmpty && leftURL == rightURL { return true }

    let leftSignature = "\(lhs.title.normalizedToken)|\(lhs.company.normalizedToken)"
    let rightSignature = "\(rhs.title.normalizedToken)|\(rhs.company.normalizedToken)"
    return !leftSignature.replacingOccurrences(of: "|", with: "").isEmpty && leftSignature == rightSignature
  }

  private func canonicalURL(_ raw: String) -> String {
    guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return raw.normalizedToken
    }
    components.fragment = nil
    let queryItems = (components.queryItems ?? []).filter { item in
      let key = item.name.normalizedToken
      return !key.hasPrefix("utm ") && key != "trk"
    }
    components.queryItems = queryItems.isEmpty ? nil : queryItems.sorted { $0.name < $1.name }
    let value = components.url?.absoluteString ?? raw
    return value.trimmingCharacters(in: CharacterSet(charactersIn: "/")).normalizedToken
  }

  private func inferCompany(from urlString: String) -> String {
    guard let host = URL(string: urlString)?.host else { return "" }
    let trimmedHost = host.replacingOccurrences(of: "www.", with: "")
    let parts = trimmedHost.split(separator: ".")
    guard parts.count >= 2 else { return trimmedHost.capitalized }
    return String(parts[parts.count - 2]).capitalized
  }

  private func suggestDeadline(for stage: Stage) -> String? {
    let haystacks = [stage.title, stage.notes, stage.url]
    let candidates = haystacks.flatMap(extractDatesFromText)
    let future = candidates.filter { $0 >= Date().startOfWeekMonday().addingDays(-1) }.sorted()
    guard let best = future.first else { return nil }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: best)
  }

  private func extractDatesFromText(_ text: String) -> [Date] {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return [] }
    var results: [Date] = []

    let isoPattern = #"\b\d{4}-\d{2}-\d{2}\b"#
    let frPattern = #"\b\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4}\b"#
    [isoPattern, frPattern].forEach { pattern in
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
      let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
      regex.matches(in: input, range: nsRange).forEach { match in
        guard let range = Range(match.range, in: input) else { return }
        let raw = String(input[range]).replacingOccurrences(of: ".", with: "/")
        if let date = parseDateCandidate(raw) {
          results.append(date)
        }
      }
    }
    return results
  }

  private func parseDateCandidate(_ raw: String) -> Date? {
    let isoFormatter = DateFormatter()
    isoFormatter.dateFormat = "yyyy-MM-dd"
    if let iso = isoFormatter.date(from: raw) { return iso }

    let parts = raw.split(separator: "/")
    guard parts.count == 3 else { return nil }
    let dayRaw = String(parts[0])
    let monthRaw = String(parts[1])
    let day = dayRaw.count == 1 ? "0\(dayRaw)" : dayRaw
    let month = monthRaw.count == 1 ? "0\(monthRaw)" : monthRaw
    var year = String(parts[2])
    if year.count == 2 { year = "20\(year)" }
    return isoFormatter.date(from: "\(year)-\(month)-\(day)")
  }

  private func load() {
    if let stageRepository, let todoRepository {
      let storedStages = stageRepository.fetchAllStages()
      let storedTodos = notionOnlyTodos(todoRepository.fetchSortedTodos())
      if !storedStages.isEmpty || !storedTodos.isEmpty {
        stages = storedStages
        todos = storedTodos
        lastSuccessfulNotionSyncDate = defaults.object(forKey: lastSuccessfulSyncDateKey) as? Date
        if
          let data = defaults.data(forKey: queueStorageKey),
          let decoded = try? decoder.decode([PendingNotionOperation].self, from: data)
        {
          pendingOperations = decoded
        }
        refreshDerivedState()
        bumpRevisions(stageChanged: true, todoChanged: true, metricsChanged: true)
        WidgetSnapshotSync.syncStagesAndTodos(stages: stages, todos: todos)
        return
      }
    }

    if let snapshot = StageStoreCache.load() {
      stages = snapshot.stages
      todos = notionOnlyTodos(snapshot.todos)
      pendingOperations = snapshot.pendingOperations
      lastSuccessfulNotionSyncDate = snapshot.lastSuccessfulNotionSyncDate
    } else {
      lastSuccessfulNotionSyncDate = defaults.object(forKey: lastSuccessfulSyncDateKey) as? Date
      if
        let data = defaults.data(forKey: stagesStorageKey),
        let decoded = try? decoder.decode([Stage].self, from: data)
      {
        stages = decoded
      }
      if
        let data = defaults.data(forKey: todosStorageKey),
        let decoded = try? decoder.decode([TodoItem].self, from: data)
      {
        todos = notionOnlyTodos(decoded)
      }
      if
        let data = defaults.data(forKey: queueStorageKey),
        let decoded = try? decoder.decode([PendingNotionOperation].self, from: data)
      {
        pendingOperations = decoded
      }
      persist(immediateDatabase: true)
    }
    refreshDerivedState()
    stageRepository?.replaceStages(stages)
    todoRepository?.replaceTodos(todos)
    defaults.set(lastSuccessfulNotionSyncDate, forKey: lastSuccessfulSyncDateKey)
    if let queueData = try? encoder.encode(pendingOperations) {
      defaults.set(queueData, forKey: queueStorageKey)
    }
    bumpRevisions(stageChanged: true, todoChanged: true, metricsChanged: true)
    WidgetSnapshotSync.syncStagesAndTodos(stages: stages, todos: todos)
  }

  private func persist(
    immediateDatabase: Bool = false,
    stageChanged: Bool = true,
    todoChanged: Bool = true,
    metricsChanged: Bool = true,
    preferDeltaWrite: Bool = false,
    upsertedStages: [Stage] = [],
    deletedStageIDs: Set<String> = [],
    upsertedTodos: [TodoItem] = [],
    deletedTodoIDs: Set<String> = []
  ) {
    stages.sort { $0.updatedAt > $1.updatedAt }
    if metricsChanged || stageChanged {
      refreshDerivedState()
    } else if todoChanged {
      sortedTodos = todos.sorted { $0.dueDate < $1.dueDate }
    }

    let snapshot = StageStoreSnapshot(
      stages: stages,
      todos: todos,
      pendingOperations: pendingOperations,
      lastSuccessfulNotionSyncDate: lastSuccessfulNotionSyncDate
    )
    defaults.set(lastSuccessfulNotionSyncDate, forKey: lastSuccessfulSyncDateKey)
    if let queueData = try? encoder.encode(pendingOperations) {
      defaults.set(queueData, forKey: queueStorageKey)
    }
    if immediateDatabase {
      if preferDeltaWrite {
        if !deletedStageIDs.isEmpty {
          stageRepository?.deleteStages(ids: deletedStageIDs)
        }
        if !upsertedStages.isEmpty {
          stageRepository?.upsertStages(upsertedStages)
        }
        if !deletedTodoIDs.isEmpty {
          if let stageRepository {
            stageRepository.deleteTodos(ids: deletedTodoIDs)
          } else {
            todoRepository?.deleteTodos(ids: deletedTodoIDs)
          }
        }
        if !upsertedTodos.isEmpty {
          if let stageRepository {
            stageRepository.upsertTodos(upsertedTodos)
          } else {
            todoRepository?.upsertTodos(upsertedTodos)
          }
        }
      } else {
        stageRepository?.replaceStages(snapshot.stages)
        todoRepository?.replaceTodos(snapshot.todos)
      }
      bumpRevisions(stageChanged: stageChanged, todoChanged: todoChanged, metricsChanged: metricsChanged)
    }
    persistenceScheduler.schedule {
      let start = CFAbsoluteTimeGetCurrent()
      StageStoreCache.save(snapshot)
      if !immediateDatabase {
        self.stageRepository?.replaceStages(snapshot.stages)
        self.todoRepository?.replaceTodos(snapshot.todos)
        Task { @MainActor in
          self.bumpRevisions(stageChanged: stageChanged, todoChanged: todoChanged, metricsChanged: metricsChanged)
        }
      }
      let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
      PerformanceMonitor.recordPersistence(label: "StageStore.persist", durationMs: durationMs)
    }

    WidgetSnapshotSync.syncStagesAndTodos(stages: snapshot.stages, todos: snapshot.todos)
  }

  private func bumpRevisions(stageChanged: Bool, todoChanged: Bool, metricsChanged: Bool) {
    if stageChanged {
      stageRevision &+= 1
    }
    if todoChanged {
      todoRevision &+= 1
    }
    if metricsChanged {
      metricsRevision &+= 1
    }
    dataRevision &+= 1
  }

  private var shouldSyncAtLaunch: Bool {
    if !pendingOperations.isEmpty {
      return true
    }
    if stages.isEmpty {
      return true
    }
    guard let lastSuccessfulNotionSyncDate else {
      return true
    }
    return Date().timeIntervalSince(lastSuccessfulNotionSyncDate) >= launchSyncStaleInterval
  }

  private func enqueue(_ operation: PendingNotionOperation) {
    if let index = pendingOperations.firstIndex(where: { existing in
      existing.kind == operation.kind &&
        existing.stageID == operation.stageID &&
        existing.status == operation.status &&
        existing.stage?.id == operation.stage?.id
    }) {
      var copy = pendingOperations[index]
      copy.retryCount += 1
      pendingOperations[index] = copy
    } else {
      pendingOperations.append(operation)
    }
    pendingOperations.sort { $0.createdAt < $1.createdAt }
    persist(stageChanged: false, todoChanged: false, metricsChanged: true)
  }

  private func isLikelyNotionPageID(_ value: String) -> Bool {
    value.range(of: #"[0-9a-fA-F]{32}"#, options: .regularExpression) != nil ||
      value.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, options: .regularExpression) != nil
  }

  private func updateNotionPageID(for stageID: String, notionPageID: String) {
    guard !notionPageID.isEmpty else { return }
    guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
    guard stages[index].notionPageID != notionPageID else { return }
    stages[index].notionPageID = notionPageID
    persist(
      stageChanged: true,
      todoChanged: false,
      metricsChanged: false,
      preferDeltaWrite: true,
      upsertedStages: [stages[index]]
    )
  }

  private func notionPageID(for stage: Stage) -> String? {
    if let notionPageID = stage.notionPageID, !notionPageID.isEmpty {
      return notionPageID
    }
    if stage.source == "notion", isLikelyNotionPageID(stage.id) {
      return stage.id
    }
    return nil
  }

  private var shouldUseIncrementalLaunchSync: Bool {
    guard let lastSuccessfulNotionSyncDate else { return false }
    let elapsed = Date().timeIntervalSince(lastSuccessfulNotionSyncDate)
    return elapsed < 6 * 60 * 60
  }

  private func reconcileFullNotionRefresh(_ remoteStages: [Stage]) {
    let remotePageIDs = Set(remoteStages.map { $0.notionPageID ?? $0.id })
    stages.removeAll { existing in
      guard existing.source == "notion" else { return false }
      let pageID = existing.notionPageID ?? existing.id
      return !remotePageIDs.contains(pageID)
    }
    remoteStages.forEach { remote in
      _ = upsertLocalStage(remote)
    }
    stages.sort { $0.updatedAt > $1.updatedAt }
  }

  private func refreshDerivedState() {
    sortedTodos = todos.sorted { $0.dueDate < $1.dueDate }

    let now = Date()
    let weekStart = now.startOfWeekMonday()
    var nextStatusCounts: [StageStatus: Int] = [:]
    var nextBlockers: [StageBlocker] = []
    var nextIssues: [StageQualityIssue] = []
    nextIssues.reserveCapacity(stages.count * 2)
    var addedCount = 0
    var appliedCount = 0

    for stage in stages {
      nextStatusCounts[stage.status, default: 0] += 1
      if stage.createdAt >= weekStart {
        addedCount += 1
      }
      if stage.status == .applied && stage.updatedAt >= weekStart {
        appliedCount += 1
      }

      let stagnantDays = Calendar.current.dateComponents([.day], from: stage.updatedAt, to: now).day ?? 0
      if stage.status == .open && stagnantDays > 7 {
        nextBlockers.append(
          StageBlocker(
            stage: stage,
            stagnantDays: stagnantDays,
            reason: "Ouvert > 7 jours",
            suggestedStatus: .applied
          )
        )
      }
      if stage.status == .applied && stagnantDays > 10 {
        nextBlockers.append(
          StageBlocker(
            stage: stage,
            stagnantDays: stagnantDays,
            reason: "Candidature > 10 jours sans update",
            suggestedStatus: .interview
          )
        )
      }

      if stage.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        nextIssues.append(
          StageQualityIssue(
            stage: stage,
            field: .company,
            suggestedValue: inferCompany(from: stage.url)
          )
        )
      }
      if stage.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        nextIssues.append(
          StageQualityIssue(
            stage: stage,
            field: .url,
            suggestedValue: ""
          )
        )
      }
      if stage.deadline == nil {
        nextIssues.append(
          StageQualityIssue(
            stage: stage,
            field: .deadline,
            suggestedValue: suggestDeadline(for: stage) ?? ""
          )
        )
      }
    }
    statusCounts = StageStatus.allCases.reduce(into: [:]) { partialResult, status in
      partialResult[status] = nextStatusCounts[status] ?? 0
    }
    blockers = nextBlockers.sorted { $0.stagnantDays > $1.stagnantDays }
    qualityIssues = nextIssues

    stageSearchIndex = Dictionary(uniqueKeysWithValues: stages.map { stage in
      (
        stage.id,
        [
          stage.title,
          stage.company,
          stage.status.rawValue,
          stage.location,
          stage.url,
        ]
        .joined(separator: " ")
        .normalizedToken
      )
    })

    let totalCount = stages.count
    weeklyKPI = WeeklyStageKPI(
      weekStart: weekStart,
      addedCount: addedCount,
      appliedCount: appliedCount,
      totalCount: totalCount,
      progressByStatus: StageStatus.allCases.map { status in
        let count = nextStatusCounts[status] ?? 0
        let ratio = totalCount > 0 ? Double(count) / Double(totalCount) : 0
        return WeeklyStageProgress(status: status, count: count, ratio: ratio)
      }
    )
  }

  private func mergeRemoteTodos(_ remoteTodos: [TodoItem]) {
    let notionTodos = notionOnlyTodos(remoteTodos)
    let mergedByID = Dictionary(uniqueKeysWithValues: notionTodos.map { ($0.id, $0) })
    todos = mergedByID.values.sorted { lhs, rhs in
      if lhs.dueDate == rhs.dueDate {
        return lhs.createdAt < rhs.createdAt
      }
      return lhs.dueDate < rhs.dueDate
    }
  }

  private func notionOnlyTodos(_ items: [TodoItem]) -> [TodoItem] {
    items.filter { $0.automationTag.hasPrefix("notion:") }
  }
}
