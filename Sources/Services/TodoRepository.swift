import Foundation
import GRDB

final class TodoRepository: @unchecked Sendable {
  private let appDatabase: AppDatabase

  init(appDatabase: AppDatabase) {
    self.appDatabase = appDatabase
  }

  private func write(_ context: String, _ block: (Database) throws -> Void) {
    do {
      try appDatabase.dbQueue.write(block)
    } catch {
      NSLog("TodoRepository.\(context) write failed: \(error)")
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

  func upsertTodo(_ todo: TodoItem) {
    upsertTodos([todo])
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

  func deleteTodo(id: String) {
    deleteTodos(ids: [id])
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

  func fetchSortedTodos() -> [TodoItem] {
    (try? appDatabase.dbQueue.read { db in
      try TodoRecord
        .order(Column("dueDate").asc)
        .fetchAll(db)
        .map { $0.makeTodo() }
    }) ?? []
  }

  func fetchNextTodo() -> TodoItem? {
    try? appDatabase.dbQueue.read { db in
      try TodoRecord
        .filter(Column("status") != TodoStatus.done.rawValue)
        .order(Column("dueDate").asc)
        .fetchOne(db)?
        .makeTodo()
    }
  }

  func fetchVisibleTodos(limit: Int, focusedTodoID: String?) -> [TodoItem] {
    let base = (try? appDatabase.dbQueue.read { db in
      try TodoRecord
        .filter(Column("status") != TodoStatus.done.rawValue)
        .order(Column("dueDate").asc)
        .limit(limit)
        .fetchAll(db)
        .map { $0.makeTodo() }
    }) ?? []

    guard let focusedTodoID else { return base }
    guard !base.contains(where: { $0.id == focusedTodoID }) else { return base }

    let focused = try? appDatabase.dbQueue.read { db in
      try TodoRecord
        .filter(key: focusedTodoID)
        .filter(Column("status") != TodoStatus.done.rawValue)
        .fetchOne(db)?
        .makeTodo()
    }
    guard let focused else { return base }
    return base + [focused]
  }

  func fetchOpenTodoCount() -> Int {
    (try? appDatabase.dbQueue.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM \(TodoRecord.databaseTableName) WHERE status != ?",
        arguments: [TodoStatus.done.rawValue]
      )
    }) ?? 0
  }

  func fetchOverdueTodoCount(relativeTo now: Date = Date()) -> Int {
    let startOfToday = Calendar.current.startOfDay(for: now)
    return (try? appDatabase.dbQueue.read { db in
      try Int.fetchOne(
        db,
        sql: """
        SELECT COUNT(*) FROM \(TodoRecord.databaseTableName)
        WHERE status != ? AND dueDate < ?
        """,
        arguments: [TodoStatus.done.rawValue, startOfToday]
      )
    }) ?? 0
  }
}
