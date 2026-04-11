import Foundation
import SwiftUI

@MainActor
final class StageStore: ObservableObject {
  private enum NotionSyncTrigger {
    case manual
    case launch
  }

  @Published private(set) var stages: [Stage] = []
  @Published private(set) var todos: [TodoItem] = []
  @Published private(set) var pendingOperations: [PendingNotionOperation] = []
  @Published var isSyncingNotion: Bool = false
  @Published var syncMessage: String = ""
  @Published private(set) var lastSuccessfulNotionSyncDate: Date?

  private let stagesStorageKey = "swift_notion_dashboard_stages_v1"
  private let todosStorageKey = "swift_notion_dashboard_todos_v1"
  private let queueStorageKey = "swift_notion_dashboard_notion_queue_v1"
  private let lastSuccessfulSyncDateKey = "swift_notion_dashboard_notion_last_successful_sync_v1"
  private let launchSyncStaleInterval: TimeInterval = 15 * 60
  private let defaults: UserDefaults
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let notionClient: NotionClient
  private weak var configStore: ConfigStore?
  private weak var diagnostics: DiagnosticsStore?

  init(
    configStore: ConfigStore,
    defaults: UserDefaults = .standard,
    diagnostics: DiagnosticsStore? = nil,
    notionClient: NotionClient? = nil
  ) {
    self.configStore = configStore
    self.defaults = defaults
    self.diagnostics = diagnostics
    self.notionClient = notionClient ?? NotionClient(diagnostics: diagnostics)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder

    load()
  }

  func prepareForLaunch() async {
    guard let configStore else { return }
    guard configStore.config.hasNotionCredentials else { return }
    guard shouldSyncAtLaunch else { return }
    await syncFromNotion(trigger: .launch)
  }

  func addStage(draft: StageDraft) async {
    let now = Date()
    var stage = Stage(
      title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
      company: draft.company.trimmingCharacters(in: .whitespacesAndNewlines),
      url: draft.url.trimmingCharacters(in: .whitespacesAndNewlines),
      location: draft.location.trimmingCharacters(in: .whitespacesAndNewlines),
      status: draft.status,
      deadline: draft.deadline,
      notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
      source: draft.source.trimmingCharacters(in: .whitespacesAndNewlines),
      createdAt: now,
      updatedAt: now
    )

    if stage.title.isEmpty {
      stage.title = "Stage"
    }

    let stored = upsertLocalStage(stage)
    createAutomationTodos(for: stored, status: stored.status)
    persist()
    await syncSingleStageIfPossible(stored)
  }

  func updateStageStatus(stageID: String, to newStatus: StageStatus) async {
    guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
    guard let configStore else { return }
    stages[index].status = newStatus
    stages[index].updatedAt = Date()
    let updated = stages[index]
    createAutomationTodos(for: updated, status: newStatus)
    persist()

    if configStore.config.hasNotionCredentials {
      do {
        try await notionClient.updateStageStatus(pageID: stageID, status: newStatus, config: configStore.config)
        diagnostics?.log(category: "notion", message: "Stage status updated.", metadata: ["stageID": stageID])
      } catch {
        let queueItem: PendingNotionOperation
        if isLikelyNotionPageID(stageID) {
          queueItem = PendingNotionOperation(
            kind: .updateStatus,
            stage: nil,
            stageID: stageID,
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
    stages.removeAll { $0.id == stageID }
    todos.removeAll { $0.relatedStageID == stageID }
    persist()
  }

  func setTodoStatus(todoID: String, status: TodoStatus) {
    guard let index = todos.firstIndex(where: { $0.id == todoID }) else { return }
    todos[index].status = status
    persist()
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

    await flushPendingOperations()

    do {
      let remoteStages = try await notionClient.fetchStages(config: configStore.config)
      let completedAt = Date()
      lastSuccessfulNotionSyncDate = completedAt
      persistSyncMetadata()

      if remoteStages.isEmpty {
        if trigger == .manual {
          syncMessage = "Notion sync done (0 stage)."
        }
        return
      }

      remoteStages.forEach { remote in
        upsertLocalStage(remote)
      }
      stages.sort { $0.updatedAt > $1.updatedAt }
      persist()
      let message = "Notion sync done (\(remoteStages.count) stages)."
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

    await flushPendingOperations()

    for stage in stages {
      do {
        try await notionClient.upsertStage(stage, config: configStore.config)
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
    guard let configStore else { return }
    guard configStore.config.hasNotionCredentials else { return }
    guard !pendingOperations.isEmpty else { return }

    var stillPending: [PendingNotionOperation] = []
    for operation in pendingOperations {
      do {
        switch operation.kind {
        case .upsertStage:
          guard let stage = operation.stage else { continue }
          try await notionClient.upsertStage(stage, config: configStore.config)
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
    pendingOperations = stillPending
    persist()
    diagnostics?.log(
      severity: stillPending.isEmpty ? .info : .warning,
      category: "notion-queue",
      message: "Queue flush done.",
      metadata: ["remaining": "\(stillPending.count)"]
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

  var weeklyKPI: WeeklyStageKPI {
    let now = Date()
    let weekStart = now.startOfWeekMonday()
    let addedCount = stages.filter { $0.createdAt >= weekStart }.count
    let appliedCount = stages.filter {
      $0.status == .applied && $0.updatedAt >= weekStart
    }.count
    let totalCount = stages.count

    let grouped = Dictionary(grouping: stages, by: \.status)
    let progress = StageStatus.allCases.map { status in
      let count = grouped[status]?.count ?? 0
      let ratio = totalCount > 0 ? Double(count) / Double(totalCount) : 0
      return WeeklyStageProgress(status: status, count: count, ratio: ratio)
    }

    return WeeklyStageKPI(
      weekStart: weekStart,
      addedCount: addedCount,
      appliedCount: appliedCount,
      totalCount: totalCount,
      progressByStatus: progress
    )
  }

  var blockers: [StageBlocker] {
    let now = Date()
    return stages.compactMap { stage in
      let days = Calendar.current.dateComponents([.day], from: stage.updatedAt, to: now).day ?? 0
      if stage.status == .open && days > 7 {
        return StageBlocker(
          stage: stage,
          stagnantDays: days,
          reason: "Ouvert > 7 jours",
          suggestedStatus: .applied
        )
      }
      if stage.status == .applied && days > 10 {
        return StageBlocker(
          stage: stage,
          stagnantDays: days,
          reason: "Candidature > 10 jours sans update",
          suggestedStatus: .interview
        )
      }
      return nil
    }
    .sorted { $0.stagnantDays > $1.stagnantDays }
  }

  var qualityIssues: [StageQualityIssue] {
    var issues: [StageQualityIssue] = []
    for stage in stages {
      if stage.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(
          StageQualityIssue(
            stage: stage,
            field: .company,
            suggestedValue: inferCompany(from: stage.url)
          )
        )
      }
      if stage.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(
          StageQualityIssue(
            stage: stage,
            field: .url,
            suggestedValue: ""
          )
        )
      }
      if stage.deadline == nil {
        issues.append(
          StageQualityIssue(
            stage: stage,
            field: .deadline,
            suggestedValue: suggestDeadline(for: stage) ?? ""
          )
        )
      }
    }
    return issues
  }

  func applyQualityFix(_ issue: StageQualityIssue) {
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
    persist()
  }

  var sortedTodos: [TodoItem] {
    todos.sorted { $0.dueDate < $1.dueDate }
  }

  var pendingQueueCount: Int {
    pendingOperations.count
  }

  private func syncSingleStageIfPossible(_ stage: Stage) async {
    guard let configStore else { return }
    guard configStore.config.hasNotionCredentials else { return }
    do {
      try await notionClient.upsertStage(stage, config: configStore.config)
      syncMessage = "Stage synced to Notion."
      diagnostics?.log(category: "notion", message: "Stage synced.", metadata: ["stageID": stage.id])
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
      syncMessage = "Stage queued (offline/retry): \(error.localizedDescription)"
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
      stages[idIndex] = merged
      return merged
    }

    if let duplicateIndex = stages.firstIndex(where: { isDuplicate($0, incoming) }) {
      var merged = incoming
      let existing = stages[duplicateIndex]
      merged.id = existing.id
      merged.createdAt = existing.createdAt
      merged.updatedAt = Date()
      if merged.source.isEmpty { merged.source = existing.source }
      stages[duplicateIndex] = merged
      return merged
    }

    stages.append(incoming)
    stages.sort { $0.updatedAt > $1.updatedAt }
    return incoming
  }

  private struct TodoTemplate {
    var tag: String
    var title: String
    var daysFromNow: Int
    var notes: String
  }

  private func createAutomationTodos(for stage: Stage, status: StageStatus) {
    let label = stage.displayLabel.isEmpty ? "Stage" : stage.displayLabel
    let notes = [stage.url, stage.deadline?.shortDate].compactMap { value in
      guard let value else { return nil }
      let cleaned = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
      return cleaned.isEmpty ? nil : cleaned
    }
    .joined(separator: "\n")

    let templates: [TodoTemplate]
    switch status {
    case .open:
      templates = [
        .init(tag: "open-apply", title: "Postuler: \(label)", daysFromNow: 3, notes: notes),
      ]
    case .applied:
      templates = [
        .init(tag: "applied-followup", title: "Relance candidature: \(label)", daysFromNow: 5, notes: notes),
        .init(tag: "applied-rh", title: "Suivi RH: \(label)", daysFromNow: 7, notes: notes),
      ]
    case .interview:
      templates = [
        .init(tag: "interview-prepare", title: "Prepa entretien: \(label)", daysFromNow: 2, notes: notes),
        .init(tag: "interview-followup", title: "Suivi RH: \(label)", daysFromNow: 4, notes: notes),
      ]
    case .rejected:
      templates = []
    }

    templates.forEach { template in
      let automationTag = "\(stage.id)|\(template.tag)"
      guard !todos.contains(where: { $0.automationTag == automationTag }) else { return }

      let todo = TodoItem(
        title: template.title,
        dueDate: Date().addingDays(template.daysFromNow),
        status: .notStarted,
        notes: template.notes,
        relatedStageID: stage.id,
        automationTag: automationTag,
        createdAt: Date()
      )
      todos.append(todo)
    }
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
      todos = decoded
    }
    if
      let data = defaults.data(forKey: queueStorageKey),
      let decoded = try? decoder.decode([PendingNotionOperation].self, from: data)
    {
      pendingOperations = decoded
    }
  }

  private func persist() {
    if let stageData = try? encoder.encode(stages) {
      defaults.set(stageData, forKey: stagesStorageKey)
    }
    if let todoData = try? encoder.encode(todos) {
      defaults.set(todoData, forKey: todosStorageKey)
    }
    if let queueData = try? encoder.encode(pendingOperations) {
      defaults.set(queueData, forKey: queueStorageKey)
    }
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

  private func persistSyncMetadata() {
    defaults.set(lastSuccessfulNotionSyncDate, forKey: lastSuccessfulSyncDateKey)
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
    persist()
  }

  private func isLikelyNotionPageID(_ value: String) -> Bool {
    value.range(of: #"[0-9a-fA-F]{32}"#, options: .regularExpression) != nil ||
      value.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, options: .regularExpression) != nil
  }
}
