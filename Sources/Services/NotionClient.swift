import Foundation

enum NotionClientError: LocalizedError {
  case missingCredentials
  case invalidDatabaseID
  case invalidPageID
  case invalidResponse
  case network(String)
  case rateLimited(retryAfter: Double, message: String)
  case api(status: Int, message: String)
  case noWritableProperties
  case retryExhausted(lastError: String)

  var errorDescription: String? {
    switch self {
    case .missingCredentials:
      return "Missing Notion token or database ID."
    case .invalidDatabaseID:
      return "Invalid Notion database ID."
    case .invalidPageID:
      return "Invalid Notion page ID."
    case .invalidResponse:
      return "Invalid Notion response."
    case let .network(message):
      return "Network error: \(message)"
    case let .rateLimited(retryAfter, message):
      return "Notion rate limited. Retry in \(Int(retryAfter))s. \(message)"
    case let .api(status, message):
      return "Notion API error (\(status)): \(message)"
    case .noWritableProperties:
      return "No writable properties found in Notion mapping."
    case let .retryExhausted(lastError):
      return "Notion request failed after retries: \(lastError)"
    }
  }

  var isRetryable: Bool {
    switch self {
    case .network, .rateLimited, .retryExhausted:
      return true
    case let .api(status, _):
      return status == 408 || status == 409 || status == 429 || status == 500 || status == 502 || status == 503 || status == 504
    default:
      return false
    }
  }
}

struct NotionClient {
  private let session: URLSession
  private let notionVersion = "2022-06-28"
  private let baseURL = "https://api.notion.com/v1"
  private let maxRetries: Int
  private let diagnostics: DiagnosticsStore?

  init(
    session: URLSession = .shared,
    maxRetries: Int = 4,
    diagnostics: DiagnosticsStore? = nil
  ) {
    self.session = session
    self.maxRetries = max(0, maxRetries)
    self.diagnostics = diagnostics
  }

  func testConnection(config: AppConfig) async throws {
    let token = config.notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let dbID = normalizeDbId(config.notionDbId)
    guard !token.isEmpty else { throw NotionClientError.missingCredentials }
    guard !dbID.isEmpty else { throw NotionClientError.invalidDatabaseID }
    _ = try await notionRequest(token: token, path: "databases/\(dbID)", method: "GET", body: nil)
  }

  func fetchStages(config: AppConfig, updatedAfter: Date? = nil) async throws -> [Stage] {
    let token = config.notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let dbID = normalizeDbId(config.notionDbId)
    guard !token.isEmpty else { throw NotionClientError.missingCredentials }
    guard !dbID.isEmpty else { throw NotionClientError.invalidDatabaseID }

    let pages = try await queryDatabasePages(
      token: token,
      databaseID: dbID,
      limit: nil,
      updatedAfter: updatedAfter
    )
    return pages.compactMap { parseStage(from: $0, config: config) }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  func fetchTodos(config: AppConfig, stagePageIDToLocalID: [String: String]) async throws -> [TodoItem] {
    let token = config.notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let dbID = normalizeDbId(config.notionTodoDbId)
    guard !token.isEmpty else { throw NotionClientError.missingCredentials }
    guard !dbID.isEmpty else { return [] }

    let pages = try await queryDatabasePages(
      token: token,
      databaseID: dbID,
      limit: nil,
      updatedAfter: nil
    )
    return pages.compactMap { parseTodo(from: $0, stagePageIDToLocalID: stagePageIDToLocalID) }
      .sorted { $0.dueDate < $1.dueDate }
  }

  func upsertStage(_ stage: Stage, config: AppConfig, knownPageID: String? = nil) async throws -> String {
    let token = config.notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let dbID = normalizeDbId(config.notionDbId)
    guard !token.isEmpty else { throw NotionClientError.missingCredentials }
    guard !dbID.isEmpty else { throw NotionClientError.invalidDatabaseID }

    let schema = try await notionRequest(token: token, path: "databases/\(dbID)", method: "GET", body: nil)
    let properties = buildProperties(for: stage, schema: schema, config: config)
    guard !properties.isEmpty else { throw NotionClientError.noWritableProperties }

    if let pageID = knownPageID?.trimmingCharacters(in: .whitespacesAndNewlines), !pageID.isEmpty {
      let response = try await notionRequest(
        token: token,
        path: "pages/\(pageID)",
        method: "PATCH",
        body: ["properties": properties]
      )
      return (response["id"] as? String) ?? pageID
    } else {
      let response = try await notionRequest(
        token: token,
        path: "pages",
        method: "POST",
        body: [
          "parent": ["database_id": dbID],
          "properties": properties,
        ]
      )
      guard let createdPageID = response["id"] as? String, !createdPageID.isEmpty else {
        throw NotionClientError.invalidResponse
      }
      return createdPageID
    }
  }

  func updateStageStatus(pageID: String, status: StageStatus, config: AppConfig) async throws {
    let token = config.notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let dbID = normalizeDbId(config.notionDbId)
    guard !token.isEmpty else { throw NotionClientError.missingCredentials }
    guard !dbID.isEmpty else { throw NotionClientError.invalidDatabaseID }
    guard isLikelyNotionID(pageID) else { throw NotionClientError.invalidPageID }

    let schema = try await notionRequest(token: token, path: "databases/\(dbID)", method: "GET", body: nil)
    let schemaProps = schema["properties"] as? [String: Any] ?? [:]
    let statusField = config.notionFieldMap.status
    guard
      let statusSchema = schemaProps[statusField] as? [String: Any],
      let type = statusSchema["type"] as? String
    else {
      throw NotionClientError.noWritableProperties
    }

    let statusName = status.notionName(using: config.notionStatusMap)
    let value: [String: Any]
    if type == "status" {
      value = ["status": ["name": statusName]]
    } else if type == "select" {
      value = ["select": ["name": statusName]]
    } else {
      value = ["rich_text": [["text": ["content": statusName]]]]
    }

    _ = try await notionRequest(
      token: token,
      path: "pages/\(pageID)",
      method: "PATCH",
      body: ["properties": [statusField: value]]
    )
  }

  func updateTodoStatus(pageID: String, status: TodoStatus, config: AppConfig) async throws {
    let token = config.notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let dbID = normalizeDbId(config.notionTodoDbId)
    guard !token.isEmpty else { throw NotionClientError.missingCredentials }
    guard !dbID.isEmpty else { throw NotionClientError.invalidDatabaseID }
    guard isLikelyNotionID(pageID) else { throw NotionClientError.invalidPageID }

    let schema = try await notionRequest(token: token, path: "databases/\(dbID)", method: "GET", body: nil)
    let schemaProps = schema["properties"] as? [String: Any] ?? [:]
    let statusField = propertyName(namedAnyOf: ["Status", "Todo Status", "Etat", "État"], in: schemaProps)
      ?? firstPropertyName(ofType: "status", in: schemaProps)
      ?? firstPropertyName(ofType: "select", in: schemaProps)
      ?? "Status"
    guard
      let statusSchema = schemaProps[statusField] as? [String: Any],
      let type = statusSchema["type"] as? String
    else {
      throw NotionClientError.noWritableProperties
    }

    let value: [String: Any]
    switch type {
    case "status":
      value = ["status": ["name": status.rawValue]]
    case "select":
      value = ["select": ["name": status.rawValue]]
    default:
      value = ["rich_text": [["text": ["content": status.rawValue]]]]
    }

    _ = try await notionRequest(
      token: token,
      path: "pages/\(pageID)",
      method: "PATCH",
      body: ["properties": [statusField: value]]
    )
  }

  func updateTodo(
    _ todo: TodoItem,
    config: AppConfig,
    knownPageID: String? = nil,
    relatedStagePageID: String? = nil
  ) async throws -> String {
    let token = config.notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let dbID = normalizeDbId(config.notionTodoDbId)
    guard !token.isEmpty else { throw NotionClientError.missingCredentials }
    guard !dbID.isEmpty else { throw NotionClientError.invalidDatabaseID }

    let schema = try await notionRequest(token: token, path: "databases/\(dbID)", method: "GET", body: nil)
    let properties = buildTodoProperties(
      for: todo,
      schema: schema,
      config: config,
      relatedStagePageID: relatedStagePageID
    )
    guard !properties.isEmpty else { throw NotionClientError.noWritableProperties }

    if let pageID = knownPageID?.trimmingCharacters(in: .whitespacesAndNewlines), !pageID.isEmpty {
      let response = try await notionRequest(
        token: token,
        path: "pages/\(pageID)",
        method: "PATCH",
        body: ["properties": properties]
      )
      return (response["id"] as? String) ?? pageID
    } else {
      let response = try await notionRequest(
        token: token,
        path: "pages",
        method: "POST",
        body: [
          "parent": ["database_id": dbID],
          "properties": properties,
        ]
      )
      guard let createdPageID = response["id"] as? String, !createdPageID.isEmpty else {
        throw NotionClientError.invalidResponse
      }
      return createdPageID
    }
  }

  private func notionRequest(
    token: String,
    path: String,
    method: String,
    body: [String: Any]?
  ) async throws -> [String: Any] {
    guard let url = URL(string: "\(baseURL)/\(path)") else {
      throw NotionClientError.invalidResponse
    }

    var lastError: Error?
    var attempt = 0
    var delay: Double = 0.6

    while attempt <= maxRetries {
      var request = URLRequest(url: url)
      request.httpMethod = method
      request.addValue("application/json", forHTTPHeaderField: "Content-Type")
      request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.addValue(notionVersion, forHTTPHeaderField: "Notion-Version")
      if let body {
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
      }

      do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
          throw NotionClientError.invalidResponse
        }

        if (200...299).contains(http.statusCode) {
          log(.info, category: "notion", message: "\(method) \(path) OK", metadata: ["attempt": "\(attempt + 1)"])
          if data.isEmpty { return [:] }
          guard
            let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
          else {
            return [:]
          }
          return object
        }

        let message = notionErrorMessage(from: data)
        if http.statusCode == 429 {
          let retryAfterHeader = http.value(forHTTPHeaderField: "Retry-After")
          let retryAfter = Double(retryAfterHeader ?? "") ?? 2.0
          let error = NotionClientError.rateLimited(retryAfter: retryAfter, message: message)
          if attempt < maxRetries {
            log(
              .warning,
              category: "notion",
              message: "Rate limited, retrying.",
              metadata: ["path": path, "after": "\(retryAfter)", "attempt": "\(attempt + 1)"]
            )
            try await sleep(seconds: retryAfter)
            attempt += 1
            continue
          }
          throw error
        }

        let error = NotionClientError.api(status: http.statusCode, message: message)
        if error.isRetryable, attempt < maxRetries {
          log(
            .warning,
            category: "notion",
            message: "Retryable HTTP status.",
            metadata: ["status": "\(http.statusCode)", "path": path, "attempt": "\(attempt + 1)"]
          )
          try await sleep(seconds: delay)
          attempt += 1
          delay *= 1.8
          continue
        }
        throw error
      } catch {
        lastError = error
        let notionError = mapNetworkError(error)
        if notionError.isRetryable, attempt < maxRetries {
          log(
            .warning,
            category: "notion",
            message: "Network retry.",
            metadata: ["path": path, "attempt": "\(attempt + 1)", "error": notionError.localizedDescription]
          )
          try await sleep(seconds: delay)
          attempt += 1
          delay *= 1.8
          continue
        }
        throw notionError
      }
    }

    throw NotionClientError.retryExhausted(lastError: (lastError?.localizedDescription ?? "Unknown error"))
  }

  private func queryDatabasePages(
    token: String,
    databaseID: String,
    limit: Int?,
    updatedAfter: Date? = nil
  ) async throws -> [[String: Any]] {
    var rows: [[String: Any]] = []
    var cursor: String? = nil

    while limit.map({ rows.count < $0 }) ?? true {
      let pageSize = limit.map { min(100, max(1, $0 - rows.count)) } ?? 100
      var body: [String: Any] = ["page_size": pageSize]
      body["sorts"] = [["timestamp": "last_edited_time", "direction": "descending"]]
      if let cursor {
        body["start_cursor"] = cursor
      }
      if let updatedAfter {
        body["filter"] = [
          "timestamp": "last_edited_time",
          "last_edited_time": ["after": updatedAfter.iso8601String]
        ]
      }

      let response = try await notionRequest(
        token: token,
        path: "databases/\(databaseID)/query",
        method: "POST",
        body: body
      )

      if let results = response["results"] as? [[String: Any]] {
        rows.append(contentsOf: results)
      }
      let hasMore = response["has_more"] as? Bool ?? false
      let nextCursor = response["next_cursor"] as? String
      if !hasMore || nextCursor == nil {
        break
      }
      cursor = nextCursor
    }

    if let limit {
      return Array(rows.prefix(limit))
    }
    return rows
  }

  private func parseStage(from page: [String: Any], config: AppConfig) -> Stage? {
    let props = page["properties"] as? [String: Any] ?? [:]
    let map = config.notionFieldMap

    let titleField = props[map.jobTitle] as? [String: Any] ?? firstTitleProperty(from: props)
    let title = propertyText(titleField)
    let company = propertyText(props[map.company] as? [String: Any])
    let url = propertyText(props[map.url] as? [String: Any])
    let location = propertyText(props[map.location] as? [String: Any])
    let statusRaw = propertyText(props[map.status] as? [String: Any])
    let notes = propertyText(props[map.notes] as? [String: Any])
    let deadline = propertyDate(props[map.closeDate] as? [String: Any])
    let status = StageStatus.fromNotion(statusRaw, statusMap: config.notionStatusMap)

    let id = (page["id"] as? String) ?? UUID().uuidString
    let createdAt = parseISODate(page["created_time"] as? String) ?? Date()
    let updatedAt = parseISODate(page["last_edited_time"] as? String) ?? createdAt

    return Stage(
      id: id,
      notionPageID: id,
      title: title.isEmpty ? "Stage" : title,
      company: company,
      url: url,
      location: location,
      status: status,
      deadline: deadline,
      notes: notes,
      source: "notion",
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  private func parseTodo(from page: [String: Any], stagePageIDToLocalID: [String: String]) -> TodoItem? {
    let props = page["properties"] as? [String: Any] ?? [:]

    let titleField =
      property(namedAnyOf: ["Task", "Name", "Title", "Todo"], in: props) ??
      firstTitleProperty(from: props)
    let statusField =
      property(namedAnyOf: ["Status", "Todo Status", "Etat", "État"], in: props) ??
      firstProperty(ofType: "status", in: props) ??
      firstProperty(ofType: "select", in: props)
    let dueDateField =
      property(namedAnyOf: ["Due Date", "Due", "Deadline", "Date", "When", "Echeance", "Échéance"], in: props) ??
      firstProperty(ofType: "date", in: props)
    let notesField =
      property(namedAnyOf: ["Notes", "Description", "Details"], in: props) ??
      firstProperty(ofType: "rich_text", in: props)
    let relationField =
      property(namedAnyOf: ["Stage", "Stages", "Opportunity", "Application", "Job"], in: props) ??
      firstProperty(ofType: "relation", in: props)

    let title = propertyText(titleField)
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

    let statusRaw = propertyText(statusField).normalizedToken
    let status: TodoStatus
    if statusRaw.contains("done") || statusRaw.contains("term") || statusRaw.contains("fini") {
      status = .done
    } else if statusRaw.contains("progress") || statusRaw.contains("cours") {
      status = .inProgress
    } else {
      status = .notStarted
    }

    let dueDate = propertyDate(dueDateField) ?? parseISODate(page["created_time"] as? String) ?? Date()
    let notes = propertyText(notesField)
    let relationPageIDs = propertyRelationIDs(relationField)
    let relatedStageID = relationPageIDs.compactMap { stagePageIDToLocalID[$0] }.first ?? ""
    let pageID = (page["id"] as? String) ?? UUID().uuidString
    let createdAt = parseISODate(page["created_time"] as? String) ?? Date()

    return TodoItem(
      id: pageID,
      title: title,
      dueDate: dueDate,
      status: status,
      notes: notes,
      relatedStageID: relatedStageID,
      automationTag: "notion:\(pageID)",
      createdAt: createdAt
    )
  }

  private func buildProperties(
    for stage: Stage,
    schema: [String: Any],
    config: AppConfig
  ) -> [String: Any] {
    let map = config.notionFieldMap
    let schemaProps = schema["properties"] as? [String: Any] ?? [:]

    var properties: [String: Any] = [:]
    let titleField = schemaProps[map.jobTitle] != nil ? map.jobTitle : firstTitlePropertyName(from: schemaProps)

    func propertyType(_ key: String) -> String? {
      (schemaProps[key] as? [String: Any])?["type"] as? String
    }

    func setText(_ key: String, value: String) {
      guard !key.isEmpty else { return }
      guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      guard let type = propertyType(key) else { return }

      switch type {
      case "title":
        properties[key] = ["title": [["text": ["content": value]]]]
      case "rich_text":
        properties[key] = ["rich_text": [["text": ["content": value]]]]
      case "url":
        properties[key] = ["url": value]
      case "select":
        properties[key] = ["select": ["name": value]]
      case "status":
        properties[key] = ["status": ["name": value]]
      case "multi_select":
        properties[key] = ["multi_select": [["name": value]]]
      default:
        break
      }
    }

    func setDate(_ key: String, value: Date?) {
      guard !key.isEmpty else { return }
      guard let value else { return }
      guard let type = propertyType(key) else { return }
      let dateText = toNotionDate(value)
      switch type {
      case "date":
        properties[key] = ["date": ["start": dateText]]
      case "rich_text":
        properties[key] = ["rich_text": [["text": ["content": dateText]]]]
      case "title":
        properties[key] = ["title": [["text": ["content": dateText]]]]
      default:
        break
      }
    }

    setText(titleField, value: stage.title)
    setText(map.company, value: stage.company)
    setText(map.location, value: stage.location)
    setText(map.url, value: stage.url)
    setText(map.notes, value: stage.notes)
    setText(map.status, value: stage.status.notionName(using: config.notionStatusMap))
    setDate(map.closeDate, value: stage.deadline)

    return properties
  }

  private func buildTodoProperties(
    for todo: TodoItem,
    schema: [String: Any],
    config: AppConfig,
    relatedStagePageID: String? = nil
  ) -> [String: Any] {
    let schemaProps = schema["properties"] as? [String: Any] ?? [:]
    var properties: [String: Any] = [:]

    let titleField = propertyName(namedAnyOf: ["Task", "Name", "Title", "Todo"], in: schemaProps)
      ?? firstTitlePropertyName(from: schemaProps)

    func propertyType(_ key: String) -> String? {
      (schemaProps[key] as? [String: Any])?["type"] as? String
    }

    func setText(_ key: String, value: String) {
      guard !key.isEmpty else { return }
      guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      guard let type = propertyType(key) else { return }
      switch type {
      case "title":
        properties[key] = ["title": [["text": ["content": value]]]]
      case "rich_text":
        properties[key] = ["rich_text": [["text": ["content": value]]]]
      case "select":
        properties[key] = ["select": ["name": value]]
      default:
        break
      }
    }

    if !titleField.isEmpty {
      setText(titleField, value: todo.title)
    }

    if let statusField = propertyName(namedAnyOf: ["Status", "Todo Status", "Etat", "État"], in: schemaProps) {
      switch propertyType(statusField) {
      case "status":
        properties[statusField] = ["status": ["name": todo.status.rawValue]]
      case "select":
        properties[statusField] = ["select": ["name": todo.status.rawValue]]
      case "rich_text":
        properties[statusField] = ["rich_text": [["text": ["content": todo.status.rawValue]]]]
      default:
        break
      }
    }

    if let dueDateField = propertyName(namedAnyOf: ["Due Date", "Due", "Deadline", "Date", "When", "Echeance", "Échéance"], in: schemaProps) {
      if propertyType(dueDateField) == "date" {
        properties[dueDateField] = ["date": ["start": iso8601DateFormatter.string(from: todo.dueDate)]]
      }
    }

    if let notesField = propertyName(namedAnyOf: ["Notes", "Description", "Details"], in: schemaProps) {
      if propertyType(notesField) == "rich_text" {
        properties[notesField] = ["rich_text": [["text": ["content": todo.notes]]]]
      }
    }

    if let relationField = propertyName(namedAnyOf: ["Stage", "Stages", "Opportunity", "Application", "Job"], in: schemaProps),
       propertyType(relationField) == "relation",
       let relatedStagePageID,
       !relatedStagePageID.isEmpty {
      properties[relationField] = ["relation": [["id": relatedStagePageID]]]
    }

    return properties
  }

  private var iso8601DateFormatter: ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  private func parseISODate(_ raw: String?) -> Date? {
    guard let raw else { return nil }
    if let value = Date.iso8601WithFractionalSeconds.date(from: raw) {
      return value
    }
    if let value = Date.fallbackISO8601.date(from: raw) {
      return value
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: raw)
  }

  private func toNotionDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private func propertyText(_ property: [String: Any]?) -> String {
    guard let property else { return "" }
    let type = property["type"] as? String ?? ""
    switch type {
    case "title":
      let items = property["title"] as? [[String: Any]] ?? []
      return items.compactMap { $0["plain_text"] as? String }.joined()
    case "rich_text":
      let items = property["rich_text"] as? [[String: Any]] ?? []
      return items.compactMap { $0["plain_text"] as? String }.joined()
    case "select":
      return (property["select"] as? [String: Any])?["name"] as? String ?? ""
    case "status":
      return (property["status"] as? [String: Any])?["name"] as? String ?? ""
    case "url":
      return property["url"] as? String ?? ""
    case "date":
      return (property["date"] as? [String: Any])?["start"] as? String ?? ""
    case "multi_select":
      let items = property["multi_select"] as? [[String: Any]] ?? []
      return items.compactMap { $0["name"] as? String }.joined(separator: ", ")
    case "checkbox":
      return (property["checkbox"] as? Bool) == true ? "true" : "false"
    default:
      return ""
    }
  }

  private func propertyName(namedAnyOf names: [String], in props: [String: Any]) -> String? {
    names.first(where: { props[$0] != nil })
  }

  private func firstPropertyName(ofType type: String, in props: [String: Any]) -> String? {
    props.first { _, value in
      (value as? [String: Any])?["type"] as? String == type
    }?.key
  }

  private func propertyDate(_ property: [String: Any]?) -> Date? {
    guard let property else { return nil }
    let type = property["type"] as? String ?? ""
    if type == "date" {
      let raw = (property["date"] as? [String: Any])?["start"] as? String
      return parseISODate(raw)
    }
    let text = propertyText(property)
    return parseISODate(text)
  }

  private func propertyRelationIDs(_ property: [String: Any]?) -> [String] {
    guard let property else { return [] }
    let type = property["type"] as? String ?? ""
    guard type == "relation" else { return [] }
    let relation = property["relation"] as? [[String: Any]] ?? []
    return relation.compactMap { $0["id"] as? String }
  }

  private func property(namedAnyOf candidates: [String], in properties: [String: Any]) -> [String: Any]? {
    let normalizedCandidates = Set(candidates.map(\.normalizedToken))
    for (key, value) in properties {
      guard normalizedCandidates.contains(key.normalizedToken) else { continue }
      guard let property = value as? [String: Any] else { continue }
      return property
    }
    return nil
  }

  private func firstProperty(ofType type: String, in properties: [String: Any]) -> [String: Any]? {
    for (_, value) in properties {
      guard let property = value as? [String: Any] else { continue }
      if (property["type"] as? String) == type {
        return property
      }
    }
    return nil
  }

  private func firstTitleProperty(from properties: [String: Any]) -> [String: Any] {
    for (_, value) in properties {
      guard let property = value as? [String: Any] else { continue }
      if (property["type"] as? String) == "title" {
        return property
      }
    }
    return [:]
  }

  private func firstTitlePropertyName(from properties: [String: Any]) -> String {
    for (key, value) in properties {
      guard let property = value as? [String: Any] else { continue }
      if (property["type"] as? String) == "title" {
        return key
      }
    }
    return "Name"
  }

  private func normalizeDbId(_ input: String) -> String {
    let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return "" }

    var candidate = raw
    if raw.lowercased().hasPrefix("http"), let url = URL(string: raw) {
      candidate = url.path
    }
    candidate = candidate.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? candidate
    let parts = candidate.split(separator: "/")
    if let last = parts.last {
      candidate = String(last)
    }

    if let uuid = candidate.range(of: #"[0-9a-fA-F]{32}"#, options: .regularExpression) {
      return String(candidate[uuid])
    }
    if let dashed = candidate.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, options: .regularExpression) {
      return String(candidate[dashed]).replacingOccurrences(of: "-", with: "")
    }
    if let uuid = raw.range(of: #"[0-9a-fA-F]{32}"#, options: .regularExpression) {
      return String(raw[uuid])
    }
    if let dashed = raw.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, options: .regularExpression) {
      return String(raw[dashed]).replacingOccurrences(of: "-", with: "")
    }
    return ""
  }

  private func isLikelyNotionID(_ value: String) -> Bool {
    if value.range(of: #"[0-9a-fA-F]{32}"#, options: .regularExpression) != nil {
      return true
    }
    if value.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, options: .regularExpression) != nil {
      return true
    }
    return false
  }

  private func canonicalURL(_ raw: String) -> String {
    guard var components = URLComponents(string: raw) else { return raw.normalizedToken }
    components.fragment = nil
    components.queryItems = (components.queryItems ?? []).filter { item in
      let key = item.name.normalizedToken
      return !key.hasPrefix("utm ") && key != "trk"
    }
    let urlString = components.url?.absoluteString ?? raw
    return urlString.replacingOccurrences(of: "/", with: "").normalizedToken
  }

  private func isDuplicate(_ lhs: Stage, _ rhs: Stage) -> Bool {
    let leftURL = canonicalURL(lhs.url)
    let rightURL = canonicalURL(rhs.url)
    if !leftURL.isEmpty && leftURL == rightURL { return true }
    return lhs.title.normalizedToken == rhs.title.normalizedToken &&
      lhs.company.normalizedToken == rhs.company.normalizedToken &&
      !lhs.title.normalizedToken.isEmpty
  }

  private func notionErrorMessage(from data: Data) -> String {
    if
      let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
      let msg = object["message"] as? String
    {
      return msg
    }
    return String(data: data, encoding: .utf8) ?? "Unknown error"
  }

  private func mapNetworkError(_ error: Error) -> NotionClientError {
    if let notion = error as? NotionClientError {
      return notion
    }
    if let urlError = error as? URLError {
      return .network(urlError.localizedDescription)
    }
    return .network(error.localizedDescription)
  }

  private func sleep(seconds: Double) async throws {
    let clamped = max(0.1, seconds)
    try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
  }

  private func log(
    _ severity: DiagnosticsSeverity,
    category: String,
    message: String,
    metadata: [String: String] = [:]
  ) {
    guard let diagnostics else { return }
    Task { @MainActor in
      diagnostics.log(severity: severity, category: category, message: message, metadata: metadata)
    }
  }
}
