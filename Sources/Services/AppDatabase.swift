import Foundation
import GRDB

struct StageRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
  static let databaseTableName = "stages"

  var id: String
  var notionPageID: String?
  var title: String
  var company: String
  var url: String
  var location: String
  var status: String
  var deadline: Date?
  var notes: String
  var source: String
  var createdAt: Date
  var updatedAt: Date
  var searchableText: String

  init(stage: Stage) {
    self.id = stage.id
    self.notionPageID = stage.notionPageID
    self.title = stage.title
    self.company = stage.company
    self.url = stage.url
    self.location = stage.location
    self.status = stage.status.key
    self.deadline = stage.deadline
    self.notes = stage.notes
    self.source = stage.source
    self.createdAt = stage.createdAt
    self.updatedAt = stage.updatedAt
    self.searchableText = [
      stage.title,
      stage.company,
      stage.location,
      stage.notes,
      stage.source,
      stage.url,
    ]
    .map(\.normalizedToken)
    .joined(separator: " ")
  }

  func makeStage() -> Stage {
    Stage(
      id: id,
      notionPageID: notionPageID,
      title: title,
      company: company,
      url: url,
      location: location,
      status: StageRecord.stageStatus(from: status),
      deadline: deadline,
      notes: notes,
      source: source,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  private static func stageStatus(from rawValue: String) -> StageStatus {
    StageStatus.allCases.first(where: { $0.key == rawValue }) ?? .open
  }
}

struct TodoRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
  static let databaseTableName = "todos"

  var id: String
  var title: String
  var dueDate: Date
  var status: String
  var notes: String
  var relatedStageID: String
  var automationTag: String
  var createdAt: Date

  init(todo: TodoItem) {
    self.id = todo.id
    self.title = todo.title
    self.dueDate = todo.dueDate
    self.status = todo.status.rawValue
    self.notes = todo.notes
    self.relatedStageID = todo.relatedStageID
    self.automationTag = todo.automationTag
    self.createdAt = todo.createdAt
  }

  func makeTodo() -> TodoItem {
    TodoItem(
      id: id,
      title: title,
      dueDate: dueDate,
      status: TodoStatus(rawValue: status) ?? .notStarted,
      notes: notes,
      relatedStageID: relatedStageID,
      automationTag: automationTag,
      createdAt: createdAt
    )
  }
}

struct CalendarEventRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
  static let databaseTableName = "calendar_events"

  var id: String
  var summary: String
  var location: String
  var eventDescription: String
  var start: Date
  var end: Date
  var sourceUrl: String
  var meetingLink: String
  var calendarName: String
  var isAllDay: Bool
  var sourceType: String
  var eventType: String
  var attendeesJSON: String

  init(event: CalendarEvent) {
    self.id = event.id
    self.summary = event.summary
    self.location = event.location
    self.eventDescription = event.description
    self.start = event.start
    self.end = event.end
    self.sourceUrl = event.sourceUrl
    self.meetingLink = event.meetingLink
    self.calendarName = event.calendarName
    self.isAllDay = event.isAllDay
    self.sourceType = event.sourceType.rawValue
    self.eventType = event.eventType.rawValue
    let data = try? JSONEncoder().encode(event.attendees)
    self.attendeesJSON = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
  }

  func makeEvent() -> CalendarEvent {
    let attendeesData = attendeesJSON.data(using: .utf8) ?? Data("[]".utf8)
    let attendees = (try? JSONDecoder().decode([String].self, from: attendeesData)) ?? []
    return CalendarEvent(
      id: id,
      summary: summary,
      location: location,
      description: eventDescription,
      start: start,
      end: end,
      sourceUrl: sourceUrl,
      meetingLink: meetingLink,
      calendarName: calendarName,
      isAllDay: isAllDay,
      sourceType: CalendarEvent.SourceType(rawValue: sourceType) ?? .local,
      eventType: EventType(rawValue: eventType) ?? .defaultType,
      attendees: attendees
    )
  }
}

struct SyncStateRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
  static let databaseTableName = "sync_state"

  var key: String
  var value: String
}

final class AppDatabase: @unchecked Sendable {
  let dbQueue: DatabaseQueue

  init() {
    self.dbQueue = try! DatabaseQueue(path: AppDatabase.databaseURL.path)
    try! migrator.migrate(dbQueue)
  }

  private var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()

    migrator.registerMigration("createStageTables") { db in
      try db.create(table: StageRecord.databaseTableName, ifNotExists: true) { table in
        table.column("id", .text).notNull().primaryKey()
        table.column("notionPageID", .text)
        table.column("title", .text).notNull()
        table.column("company", .text).notNull()
        table.column("url", .text).notNull()
        table.column("location", .text).notNull()
        table.column("status", .text).notNull()
        table.column("deadline", .datetime)
        table.column("notes", .text).notNull()
        table.column("source", .text).notNull()
        table.column("createdAt", .datetime).notNull()
        table.column("updatedAt", .datetime).notNull()
        table.column("searchableText", .text).notNull()
      }
      try db.create(index: "idx_stages_status", on: StageRecord.databaseTableName, columns: ["status"])
      try db.create(index: "idx_stages_updatedAt", on: StageRecord.databaseTableName, columns: ["updatedAt"])
      try db.create(index: "idx_stages_notionPageID", on: StageRecord.databaseTableName, columns: ["notionPageID"])
      try db.create(index: "idx_stages_searchableText", on: StageRecord.databaseTableName, columns: ["searchableText"])

      try db.create(table: TodoRecord.databaseTableName, ifNotExists: true) { table in
        table.column("id", .text).notNull().primaryKey()
        table.column("title", .text).notNull()
        table.column("dueDate", .datetime).notNull()
        table.column("status", .text).notNull()
        table.column("notes", .text).notNull()
        table.column("relatedStageID", .text).notNull()
        table.column("automationTag", .text).notNull()
        table.column("createdAt", .datetime).notNull()
      }
      try db.create(index: "idx_todos_relatedStageID", on: TodoRecord.databaseTableName, columns: ["relatedStageID"])
      try db.create(index: "idx_todos_dueDate", on: TodoRecord.databaseTableName, columns: ["dueDate"])

      try db.create(table: CalendarEventRecord.databaseTableName, ifNotExists: true) { table in
        table.column("id", .text).notNull().primaryKey()
        table.column("summary", .text).notNull()
        table.column("location", .text).notNull()
        table.column("eventDescription", .text).notNull()
        table.column("start", .datetime).notNull()
        table.column("end", .datetime).notNull()
        table.column("sourceUrl", .text).notNull()
        table.column("meetingLink", .text).notNull()
        table.column("calendarName", .text).notNull()
        table.column("isAllDay", .boolean).notNull()
        table.column("sourceType", .text).notNull()
        table.column("eventType", .text).notNull()
        table.column("attendeesJSON", .text).notNull()
      }
      try db.create(index: "idx_calendar_events_start", on: CalendarEventRecord.databaseTableName, columns: ["start"])
      try db.create(index: "idx_calendar_events_end", on: CalendarEventRecord.databaseTableName, columns: ["end"])

      try db.create(table: SyncStateRecord.databaseTableName, ifNotExists: true) { table in
        table.column("key", .text).notNull().primaryKey()
        table.column("value", .text).notNull()
      }
    }

    migrator.registerMigration("addPerformanceIndexesV2") { db in
      try db.create(index: "idx_stages_status_updatedAt", on: StageRecord.databaseTableName, columns: ["status", "updatedAt"])
      try db.create(index: "idx_todos_status_dueDate", on: TodoRecord.databaseTableName, columns: ["status", "dueDate"])
      try db.create(index: "idx_calendar_events_end_start", on: CalendarEventRecord.databaseTableName, columns: ["end", "start"])
    }

    migrator.registerMigration("addStageSearchFTSV3") { db in
      try db.execute(sql: """
      CREATE VIRTUAL TABLE IF NOT EXISTS stages_fts
      USING fts5(stageID UNINDEXED, searchableText, tokenize = 'unicode61 remove_diacritics 2')
      """)
      try db.execute(sql: "DELETE FROM stages_fts")
      try db.execute(sql: """
      INSERT INTO stages_fts(stageID, searchableText)
      SELECT id, searchableText FROM \(StageRecord.databaseTableName)
      """)
    }

    return migrator
  }

  private static var databaseURL: URL {
    let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let folderURL = baseURL.appendingPathComponent("NotionDashboard", isDirectory: true)
    try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    return folderURL.appendingPathComponent("dashboard.sqlite")
  }
}
