import Foundation
import GRDB

struct StagesReadModel: Identifiable, Hashable {
  var id: String
  var title: String
  var company: String
  var status: StageStatus
  var updatedAt: Date
  var closeDate: Date?
  var hasTodos: Bool
}

struct StagesListViewState: Hashable {
  var items: [StagesReadModel]
  var totalCount: Int
  var hasMore: Bool
  var blockersCount: Int
  var pendingQueueCount: Int

  static let empty = StagesListViewState(
    items: [],
    totalCount: 0,
    hasMore: false,
    blockersCount: 0,
    pendingQueueCount: 0
  )
}

struct StageDetailViewState: Hashable {
  var stage: Stage
  var relatedTodos: [TodoItem]
}

final class StageRepository: @unchecked Sendable {
  private static let ftsTableName = "stages_fts"
  private let appDatabase: AppDatabase

  init(appDatabase: AppDatabase) {
    self.appDatabase = appDatabase
  }

  private func write(_ context: String, _ block: (Database) throws -> Void) {
    do {
      try appDatabase.dbQueue.write(block)
    } catch {
      NSLog("StageRepository.\(context) write failed: \(error)")
    }
  }

  func replaceStages(_ stages: [Stage]) {
    let records = stages.map(StageRecord.init)
    write("replaceStages") { db in
      try db.execute(sql: "DELETE FROM \(StageRecord.databaseTableName)")
      for var record in records {
        try record.insert(db)
      }
      try rebuildSearchIndex(db: db)
    }
  }

  func upsertStage(_ stage: Stage) {
    upsertStages([stage])
  }

  func upsertStages(_ stages: [Stage]) {
    guard !stages.isEmpty else { return }
    let records = stages.map(StageRecord.init)
    write("upsertStages") { db in
      for var record in records {
        try record.save(db)
      }
      try syncSearchIndex(records: records, db: db)
    }
  }

  func deleteStage(id: String) {
    deleteStages(ids: [id])
  }

  func deleteStages(ids: Set<String>) {
    guard !ids.isEmpty else { return }
    write("deleteStages") { db in
      let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
      let arguments = StatementArguments(ids.map { $0 })
      try db.execute(
        sql: "DELETE FROM \(StageRecord.databaseTableName) WHERE id IN (\(placeholders))",
        arguments: arguments
      )
      try deleteFromSearchIndex(stageIDs: ids, db: db)
    }
  }

  func replaceTodos(_ todos: [TodoItem]) {
    let records = todos.map(TodoRecord.init)
    write("replaceTodos") { db in
      try db.execute(sql: "DELETE FROM \(TodoRecord.databaseTableName)")
      for var record in records {
        try record.insert(db)
      }
    }
  }

  func upsertTodos(_ todos: [TodoItem]) {
    guard !todos.isEmpty else { return }
    let records = todos.map(TodoRecord.init)
    write("upsertTodos") { db in
      for var record in records {
        try record.save(db)
      }
    }
  }

  func deleteTodos(ids: Set<String>) {
    guard !ids.isEmpty else { return }
    write("deleteTodos") { db in
      let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
      try db.execute(
        sql: "DELETE FROM \(TodoRecord.databaseTableName) WHERE id IN (\(placeholders))",
        arguments: StatementArguments(ids.map { $0 })
      )
    }
  }

  func fetchAllStages() -> [Stage] {
    (try? appDatabase.dbQueue.read { db in
      try StageRecord
        .order(Column("updatedAt").desc)
        .fetchAll(db)
        .map { $0.makeStage() }
    }) ?? []
  }

  func fetchAllTodos() -> [TodoItem] {
    (try? appDatabase.dbQueue.read { db in
      try TodoRecord
        .order(Column("dueDate").asc)
        .fetchAll(db)
        .map { $0.makeTodo() }
    }) ?? []
  }

  func fetchListState(searchQuery: String, limit: Int, offset: Int, pendingQueueCount: Int) -> StagesListViewState {
    let query = searchQuery.normalizedToken
    return (try? appDatabase.dbQueue.read { db in
      let items = try fetchStagePage(db: db, searchQuery: query, limit: limit, offset: offset)
      let totalCount = try fetchStageCount(db: db, searchQuery: query)
      let blockersCount = try fetchBlockersCount(db: db)
      return StagesListViewState(
        items: items,
        totalCount: totalCount,
        hasMore: offset + items.count < totalCount,
        blockersCount: blockersCount,
        pendingQueueCount: pendingQueueCount
      )
    }) ?? .empty
  }

  func fetchStagePage(searchQuery: String, limit: Int, offset: Int) -> [StagesReadModel] {
    (try? appDatabase.dbQueue.read { db in
      try fetchStagePage(db: db, searchQuery: searchQuery, limit: limit, offset: offset)
    }) ?? []
  }

  func fetchStageDetail(stageID: String) -> StageDetailViewState? {
    guard let stage = fetchStage(stageID: stageID) else { return nil }
    let todos = fetchTodos(for: stageID)
    return StageDetailViewState(stage: stage, relatedTodos: todos)
  }

  func fetchStage(stageID: String) -> Stage? {
    try? appDatabase.dbQueue.read { db in
      try StageRecord.fetchOne(db, key: stageID)?.makeStage()
    }
  }

  func fetchStageCount(searchQuery: String = "") -> Int {
    (try? appDatabase.dbQueue.read { db in
      try fetchStageCount(db: db, searchQuery: searchQuery)
    }) ?? 0
  }

  func fetchStatusCounts() -> [StageStatus: Int] {
    (try? appDatabase.dbQueue.read { db in
      struct StatusRow: FetchableRecord, Decodable {
        var status: String
        var count: Int
      }

      let rows = try StatusRow.fetchAll(
        db,
        sql: """
        SELECT status, COUNT(*) AS count
        FROM \(StageRecord.databaseTableName)
        GROUP BY status
        """
      )
      return rows.reduce(into: Dictionary(uniqueKeysWithValues: StageStatus.allCases.map { ($0, 0) })) { result, row in
        let status = StageStatus.allCases.first(where: { $0.key == row.status }) ?? .open
        result[status] = row.count
      }
    }) ?? Dictionary(uniqueKeysWithValues: StageStatus.allCases.map { ($0, 0) })
  }

  func fetchWeeklyKPI() -> WeeklyStageKPI {
    let weekStart = Date().startOfWeekMonday()
    return (try? appDatabase.dbQueue.read { db in
      struct StatusRow: FetchableRecord, Decodable {
        var status: String
        var count: Int
      }

      let totalCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM \(StageRecord.databaseTableName)"
      ) ?? 0
      let addedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM \(StageRecord.databaseTableName) WHERE createdAt >= ?",
        arguments: [weekStart]
      ) ?? 0
      let appliedCount = try Int.fetchOne(
        db,
        sql: """
        SELECT COUNT(*) FROM \(StageRecord.databaseTableName)
        WHERE status = ? AND updatedAt >= ?
        """,
        arguments: [StageStatus.applied.key, weekStart]
      ) ?? 0
      let rows = try StatusRow.fetchAll(
        db,
        sql: """
        SELECT status, COUNT(*) AS count
        FROM \(StageRecord.databaseTableName)
        GROUP BY status
        """
      )
      let countsByKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.status, $0.count) })
      let progressByStatus = StageStatus.allCases.map { status in
        let count = countsByKey[status.key] ?? 0
        let ratio = totalCount == 0 ? 0 : Double(count) / Double(totalCount)
        return WeeklyStageProgress(status: status, count: count, ratio: ratio)
      }
      return WeeklyStageKPI(
        weekStart: weekStart,
        addedCount: addedCount,
        appliedCount: appliedCount,
        totalCount: totalCount,
        progressByStatus: progressByStatus
      )
    }) ?? WeeklyStageKPI(
      weekStart: weekStart,
      addedCount: 0,
      appliedCount: 0,
      totalCount: 0,
      progressByStatus: StageStatus.allCases.map { WeeklyStageProgress(status: $0, count: 0, ratio: 0) }
    )
  }

  func fetchBlockers(limit: Int?) -> [StageBlocker] {
    let now = Date()
    let openCutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
    let appliedCutoff = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now
    let limitSQL = limit.map { "LIMIT \($0)" } ?? ""
    let rows = (try? appDatabase.dbQueue.read { db in
      try StageRecord.fetchAll(
        db,
        sql: """
        SELECT * FROM \(StageRecord.databaseTableName)
        WHERE (status = ? AND updatedAt <= ?)
           OR (status = ? AND updatedAt <= ?)
        ORDER BY updatedAt ASC
        \(limitSQL)
        """,
        arguments: [StageStatus.open.key, openCutoff, StageStatus.applied.key, appliedCutoff]
      )
    }) ?? []

    return rows.compactMap { record in
      let stage = record.makeStage()
      let stagnantDays = Calendar.current.dateComponents([.day], from: stage.updatedAt, to: now).day ?? 0
      switch stage.status {
      case .open:
        return StageBlocker(
          stage: stage,
          stagnantDays: stagnantDays,
          reason: "Ouvert > 7 jours",
          suggestedStatus: .applied
        )
      case .applied:
        return StageBlocker(
          stage: stage,
          stagnantDays: stagnantDays,
          reason: "Candidature > 10 jours sans update",
          suggestedStatus: .interview
        )
      default:
        return nil
      }
    }
  }

  func fetchQualityIssues(limit: Int?) -> [StageQualityIssue] {
    let rowLimit = max((limit ?? 24) * 2, 12)
    let stages = (try? appDatabase.dbQueue.read { db in
      try StageRecord.fetchAll(
        db,
        sql: """
        SELECT * FROM \(StageRecord.databaseTableName)
        WHERE TRIM(company) = '' OR TRIM(url) = '' OR deadline IS NULL
        ORDER BY updatedAt DESC
        LIMIT ?
        """,
        arguments: [rowLimit]
      )
      .map { $0.makeStage() }
    }) ?? []

    let issues = stages.flatMap { stage -> [StageQualityIssue] in
      var result: [StageQualityIssue] = []
      if stage.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(StageQualityIssue(stage: stage, field: .company, suggestedValue: inferCompany(from: stage.url)))
      }
      if stage.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(StageQualityIssue(stage: stage, field: .url, suggestedValue: ""))
      }
      if stage.deadline == nil {
        result.append(StageQualityIssue(stage: stage, field: .deadline, suggestedValue: suggestDeadline(for: stage) ?? ""))
      }
      return result
    }

    guard let limit else { return issues }
    return Array(issues.prefix(limit))
  }

  func fetchStageLabelMap(ids: Set<String>) -> [String: String] {
    guard !ids.isEmpty else { return [:] }
    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
    let sql = """
    SELECT id, company, title FROM \(StageRecord.databaseTableName)
    WHERE id IN (\(placeholders))
    """
    return (try? appDatabase.dbQueue.read { db in
      struct LabelRow: FetchableRecord, Decodable {
        var id: String
        var company: String
        var title: String
      }
      let rows = try LabelRow.fetchAll(db, sql: sql, arguments: StatementArguments(ids.map { $0 }))
      return Dictionary(uniqueKeysWithValues: rows.map { row in
        let label = [row.company, row.title]
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
          .joined(separator: " · ")
        return (row.id, label)
      })
    }) ?? [:]
  }

  private func fetchStageCount(db: Database, searchQuery: String) throws -> Int {
    let sql: String
    let arguments: StatementArguments
    if searchQuery.isEmpty {
      sql = "SELECT COUNT(*) FROM \(StageRecord.databaseTableName)"
      arguments = []
    } else {
      do {
        return try Int.fetchOne(
          db,
          sql: """
          SELECT COUNT(*)
          FROM \(StageRecord.databaseTableName) s
          JOIN \(Self.ftsTableName) f ON f.stageID = s.id
          WHERE \(Self.ftsTableName) MATCH ?
          """,
          arguments: [ftsMatcher(from: searchQuery)]
        ) ?? 0
      } catch {
        sql = "SELECT COUNT(*) FROM \(StageRecord.databaseTableName) WHERE searchableText LIKE ?"
        arguments = ["%\(searchQuery)%"]
      }
    }
    return try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
  }

  func fetchTodos(for stageID: String) -> [TodoItem] {
    (try? appDatabase.dbQueue.read { db in
      try TodoRecord
        .filter(Column("relatedStageID") == stageID)
        .order(Column("dueDate").asc)
        .fetchAll(db)
        .map { $0.makeTodo() }
    }) ?? []
  }

  private func fetchStagePage(db: Database, searchQuery: String, limit: Int, offset: Int) throws -> [StagesReadModel] {
    struct StageListRow: FetchableRecord, Decodable {
      var id: String
      var title: String
      var company: String
      var status: String
      var updatedAt: Date
      var closeDate: Date?
      var hasTodos: Int
    }

    let sql: String
    let arguments: StatementArguments
    if searchQuery.isEmpty {
      sql = """
      SELECT
        s.id,
        s.title,
        s.company,
        s.status,
        s.updatedAt,
        s.deadline AS closeDate,
        EXISTS(
          SELECT 1 FROM \(TodoRecord.databaseTableName) t
          WHERE t.relatedStageID = s.id
          LIMIT 1
        ) AS hasTodos
      FROM \(StageRecord.databaseTableName) s
      ORDER BY s.updatedAt DESC
      LIMIT ? OFFSET ?
      """
      arguments = [limit, offset]
    } else {
      do {
        let rows = try StageListRow.fetchAll(
          db,
          sql: """
          SELECT
            s.id,
            s.title,
            s.company,
            s.status,
            s.updatedAt,
            s.deadline AS closeDate,
            EXISTS(
              SELECT 1 FROM \(TodoRecord.databaseTableName) t
              WHERE t.relatedStageID = s.id
              LIMIT 1
            ) AS hasTodos
          FROM \(StageRecord.databaseTableName) s
          JOIN \(Self.ftsTableName) f ON f.stageID = s.id
          WHERE \(Self.ftsTableName) MATCH ?
          ORDER BY s.updatedAt DESC
          LIMIT ? OFFSET ?
          """,
          arguments: [ftsMatcher(from: searchQuery), limit, offset]
        )
        return rows.map { row in
          StagesReadModel(
            id: row.id,
            title: row.title,
            company: row.company,
            status: StageStatus.allCases.first(where: { $0.key == row.status }) ?? .open,
            updatedAt: row.updatedAt,
            closeDate: row.closeDate,
            hasTodos: row.hasTodos != 0
          )
        }
      } catch {
        sql = """
        SELECT
          s.id,
          s.title,
          s.company,
          s.status,
          s.updatedAt,
          s.deadline AS closeDate,
          EXISTS(
            SELECT 1 FROM \(TodoRecord.databaseTableName) t
            WHERE t.relatedStageID = s.id
            LIMIT 1
          ) AS hasTodos
        FROM \(StageRecord.databaseTableName) s
        WHERE s.searchableText LIKE ?
        ORDER BY s.updatedAt DESC
        LIMIT ? OFFSET ?
        """
        arguments = ["%\(searchQuery)%", limit, offset]
      }
    }

    let rows = try StageListRow.fetchAll(db, sql: sql, arguments: arguments)
    return rows.map { row in
      StagesReadModel(
        id: row.id,
        title: row.title,
        company: row.company,
        status: StageStatus.allCases.first(where: { $0.key == row.status }) ?? .open,
        updatedAt: row.updatedAt,
        closeDate: row.closeDate,
        hasTodos: row.hasTodos != 0
      )
    }
  }

  private func ftsMatcher(from query: String) -> String {
    let tokens = query
      .normalizedToken
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .map(String.init)
      .filter { !$0.isEmpty }
    if tokens.isEmpty {
      return query.normalizedToken
    }
    return tokens.joined(separator: " AND ")
  }

  private func rebuildSearchIndex(db: Database) throws {
    try db.execute(sql: "DELETE FROM \(Self.ftsTableName)")
    try db.execute(
      sql: """
      INSERT INTO \(Self.ftsTableName)(stageID, searchableText)
      SELECT id, searchableText FROM \(StageRecord.databaseTableName)
      """
    )
  }

  private func syncSearchIndex(records: [StageRecord], db: Database) throws {
    for record in records {
      try db.execute(
        sql: "DELETE FROM \(Self.ftsTableName) WHERE stageID = ?",
        arguments: [record.id]
      )
      try db.execute(
        sql: "INSERT INTO \(Self.ftsTableName)(stageID, searchableText) VALUES (?, ?)",
        arguments: [record.id, record.searchableText]
      )
    }
  }

  private func deleteFromSearchIndex(stageIDs: Set<String>, db: Database) throws {
    guard !stageIDs.isEmpty else { return }
    let placeholders = Array(repeating: "?", count: stageIDs.count).joined(separator: ", ")
    try db.execute(
      sql: "DELETE FROM \(Self.ftsTableName) WHERE stageID IN (\(placeholders))",
      arguments: StatementArguments(stageIDs.map { $0 })
    )
  }

  private func fetchBlockersCount(db: Database) throws -> Int {
    let now = Date()
    let openCutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
    let appliedCutoff = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now
    return try Int.fetchOne(
      db,
      sql: """
      SELECT COUNT(*) FROM \(StageRecord.databaseTableName)
      WHERE (status = ? AND updatedAt <= ?)
         OR (status = ? AND updatedAt <= ?)
      """,
      arguments: [StageStatus.open.key, openCutoff, StageStatus.applied.key, appliedCutoff]
    ) ?? 0
  }

  private func inferCompany(from urlString: String) -> String {
    guard let host = URL(string: urlString)?.host else { return "" }
    let trimmedHost = host.replacingOccurrences(of: "www.", with: "")
    let parts = trimmedHost.split(separator: ".")
    guard parts.count >= 2 else { return trimmedHost.capitalized }
    return String(parts[parts.count - 2]).capitalized
  }

  private func suggestDeadline(for stage: Stage) -> String? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let values = [stage.title, stage.notes, stage.url]
    let candidates = values.flatMap(extractDates(from:))
    let future = candidates.filter { $0 >= Date().addingDays(-1) }.sorted()
    guard let first = future.first else { return nil }
    return formatter.string(from: first)
  }

  private func extractDates(from text: String) -> [Date] {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return [] }
    let patterns = [#"\b\d{4}-\d{2}-\d{2}\b"#, #"\b\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4}\b"#]
    return patterns.flatMap { pattern -> [Date] in
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
      let range = NSRange(input.startIndex..<input.endIndex, in: input)
      return regex.matches(in: input, range: range).compactMap { match in
        guard let swiftRange = Range(match.range, in: input) else { return nil }
        return parseDateCandidate(String(input[swiftRange]).replacingOccurrences(of: ".", with: "/"))
      }
    }
  }

  private func parseDateCandidate(_ raw: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    if let iso = formatter.date(from: raw) {
      return iso
    }
    let parts = raw.split(separator: "/")
    guard parts.count == 3 else { return nil }
    let day = parts[0].count == 1 ? "0\(parts[0])" : String(parts[0])
    let month = parts[1].count == 1 ? "0\(parts[1])" : String(parts[1])
    var year = String(parts[2])
    if year.count == 2 {
      year = "20\(year)"
    }
    return formatter.date(from: "\(year)-\(month)-\(day)")
  }
}
