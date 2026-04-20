import Foundation
import GRDB

struct CalendarViewState: Hashable {
  var groupedEvents: [CalendarEventGroup]
  var upcomingEvents: [CalendarEvent]
  var upcomingCount: Int
  var todayCount: Int
  var nextUpcomingEvent: CalendarEvent?

  static let empty = CalendarViewState(
    groupedEvents: [],
    upcomingEvents: [],
    upcomingCount: 0,
    todayCount: 0,
    nextUpcomingEvent: nil
  )
}

final class CalendarRepository: @unchecked Sendable {
  private let appDatabase: AppDatabase

  init(appDatabase: AppDatabase) {
    self.appDatabase = appDatabase
  }

  func replaceEvents(_ events: [CalendarEvent]) {
    let records = events.map(CalendarEventRecord.init)
    try? appDatabase.dbQueue.write { db in
      try db.execute(sql: "DELETE FROM \(CalendarEventRecord.databaseTableName)")
      for var record in records {
        try record.insert(db)
      }
    }
  }

  func upsertEvents(_ events: [CalendarEvent]) {
    guard !events.isEmpty else { return }
    let records = events.map(CalendarEventRecord.init)
    try? appDatabase.dbQueue.write { db in
      for var record in records {
        try record.save(db)
      }
    }
  }

  func deleteEvents(ids: Set<String>) {
    guard !ids.isEmpty else { return }
    try? appDatabase.dbQueue.write { db in
      let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
      try db.execute(
        sql: "DELETE FROM \(CalendarEventRecord.databaseTableName) WHERE id IN (\(placeholders))",
        arguments: StatementArguments(ids.map { $0 })
      )
    }
  }

  func replaceEvents(inRange range: DateInterval, with events: [CalendarEvent]) {
    let records = events.map(CalendarEventRecord.init)
    try? appDatabase.dbQueue.write { db in
      try db.execute(
        sql: """
        DELETE FROM \(CalendarEventRecord.databaseTableName)
        WHERE start <= ? AND end >= ?
        """,
        arguments: [range.end, range.start]
      )
      for var record in records {
        try record.save(db)
      }
    }
  }

  func fetchViewState() -> CalendarViewState {
    let now = Date()
    let threshold = now.addingTimeInterval(-3600)
    let upcoming = (try? appDatabase.dbQueue.read { db in
      try CalendarEventRecord
        .filter(Column("end") >= threshold)
        .order(Column("start").asc)
        .fetchAll(db)
        .map { $0.makeEvent() }
    }) ?? []
    let todayCount = upcoming.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }.count
    let grouped = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.start) }
    let groups = grouped.keys.sorted().map { day in
      CalendarEventGroup(day: day, items: grouped[day] ?? [])
    }

    return CalendarViewState(
      groupedEvents: groups,
      upcomingEvents: Array(upcoming.prefix(6)),
      upcomingCount: upcoming.count,
      todayCount: todayCount,
      nextUpcomingEvent: upcoming.first
    )
  }

  func fetchEvent(id: String) -> CalendarEvent? {
    try? appDatabase.dbQueue.read { db in
      try CalendarEventRecord.fetchOne(db, key: id)?.makeEvent()
    }
  }
}
