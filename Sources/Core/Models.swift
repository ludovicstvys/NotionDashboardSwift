import Foundation

enum StageStatus: String, Codable, CaseIterable, Identifiable {
  case open = "Ouvert"
  case applied = "Candidature"
  case interview = "Entretien"
  case rejected = "Refuse"

  var id: String { rawValue }

  var key: String {
    switch self {
    case .open: return "open"
    case .applied: return "applied"
    case .interview: return "interview"
    case .rejected: return "rejected"
    }
  }

  var colorName: String {
    switch self {
    case .open: return "blue"
    case .applied: return "green"
    case .interview: return "orange"
    case .rejected: return "red"
    }
  }

  var defaultWipLimit: Int {
    switch self {
    case .open: return 20
    case .applied: return 15
    case .interview: return 8
    case .rejected: return 999
    }
  }

  static func fromNotion(_ value: String, statusMap: NotionStatusMap) -> StageStatus {
    let clean = value.normalizedToken
    if clean == statusMap.open.normalizedToken || clean.hasPrefix("ouv") { return .open }
    if clean == statusMap.applied.normalizedToken || clean.contains("candid") || clean.contains("postul") {
      return .applied
    }
    if clean == statusMap.interview.normalizedToken || clean.contains("entre") || clean.contains("interview") {
      return .interview
    }
    if clean == statusMap.rejected.normalizedToken || clean.contains("refus") || clean.contains("reject") {
      return .rejected
    }
    return .open
  }

  func notionName(using map: NotionStatusMap) -> String {
    switch self {
    case .open: return map.open
    case .applied: return map.applied
    case .interview: return map.interview
    case .rejected: return map.rejected
    }
  }
}

struct NotionFieldMap: Codable, Hashable {
  var jobTitle: String = "Job Title"
  var company: String = "Entreprise"
  var location: String = "Lieu"
  var url: String = "lien offre"
  var status: String = "Status"
  var closeDate: String = "Date de fermeture"
  var notes: String = "Notes"
}

struct NotionStatusMap: Codable, Hashable {
  var open: String = "Ouvert"
  var applied: String = "Candidature"
  var interview: String = "Entretien"
  var rejected: String = "Refuse"
}

struct AppConfig: Codable, Hashable {
  static let defaultGoogleOAuthClientID = "608348086080-dp8647muci5st4em00pdgvrba75jq3db.apps.googleusercontent.com"

  var notionToken: String = ""
  var notionDbId: String = ""
  var notionTodoDbId: String = ""
  var bdfApiKey: String = ""
  var googlePlacesApiKey: String = ""
  var googleOAuthClientID: String = AppConfig.defaultGoogleOAuthClientID
  var googleOAuthRedirectURI: String = AppConfig.recommendedGoogleOAuthRedirectURI(for: AppConfig.defaultGoogleOAuthClientID)
  var googleOAuthScopes: [String] = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/calendar.events",
  ]
  var googleAccessToken: String = ""
  var googleRefreshToken: String = ""
  var googleTokenExpiration: Date? = nil
  var googleSelectedCalendarIDs: [String] = []
  var googleDefaultCalendarID: String = ""
  var externalIcalUrl: String = ""
  var pipelineAutoImportEnabled: Bool = true
  var focusModeEnabled: Bool = false
  var pomodoroWorkMinutes: Int = 25
  var pomodoroBreakMinutes: Int = 5
  var urlBlockerRules: [String] = []
  var reminderPrefs: ReminderPrefs = .defaults
  var marketSymbols: [String] = ["^GSPC", "EURUSD=X", "BTC-USD"]
  var newsEnabled: Bool = true
  var marketsEnabled: Bool = true
  var notionFieldMap: NotionFieldMap = .init()
  var notionStatusMap: NotionStatusMap = .init()
  var wipLimits: [String: Int] = AppConfig.defaultWipLimits()

  static func defaultWipLimits() -> [String: Int] {
    var result: [String: Int] = [:]
    StageStatus.allCases.forEach { status in
      result[status.key] = status.defaultWipLimit
    }
    return result
  }

  init() {}

  static var defaults: AppConfig { .init() }

  static func recommendedGoogleOAuthScheme(for clientID: String) -> String? {
    let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    let suffix = ".apps.googleusercontent.com"
    guard trimmed.hasSuffix(suffix) else { return nil }
    let prefix = String(trimmed.dropLast(suffix.count))
    guard !prefix.isEmpty else { return nil }
    return "com.googleusercontent.apps.\(prefix)"
  }

  static func recommendedGoogleOAuthRedirectURI(for clientID: String) -> String {
    guard let scheme = recommendedGoogleOAuthScheme(for: clientID) else {
      return ""
    }
    return "\(scheme):/oauth2redirect"
  }

  static func usesManagedGoogleOAuthRedirectURI(_ redirectURI: String, clientID: String) -> Bool {
    let trimmed = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ||
      trimmed == recommendedGoogleOAuthRedirectURI(for: clientID)
  }

  var hasNotionCredentials: Bool {
    !notionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !notionDbId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var hasGoogleOAuthCredentials: Bool {
    !googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !googleOAuthRedirectURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func wipLimit(for status: StageStatus) -> Int {
    wipLimits[status.key] ?? status.defaultWipLimit
  }

  enum CodingKeys: String, CodingKey {
    case notionToken
    case notionDbId
    case notionTodoDbId
    case bdfApiKey
    case googlePlacesApiKey
    case googleOAuthClientID
    case googleOAuthRedirectURI
    case googleOAuthScopes
    case googleAccessToken
    case googleRefreshToken
    case googleTokenExpiration
    case googleSelectedCalendarIDs
    case googleDefaultCalendarID
    case externalIcalUrl
    case pipelineAutoImportEnabled
    case focusModeEnabled
    case pomodoroWorkMinutes
    case pomodoroBreakMinutes
    case urlBlockerRules
    case reminderPrefs
    case marketSymbols
    case newsEnabled
    case marketsEnabled
    case notionFieldMap
    case notionStatusMap
    case wipLimits
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    notionToken = try c.decodeIfPresent(String.self, forKey: .notionToken) ?? ""
    notionDbId = try c.decodeIfPresent(String.self, forKey: .notionDbId) ?? ""
    notionTodoDbId = try c.decodeIfPresent(String.self, forKey: .notionTodoDbId) ?? ""
    bdfApiKey = try c.decodeIfPresent(String.self, forKey: .bdfApiKey) ?? ""
    googlePlacesApiKey = try c.decodeIfPresent(String.self, forKey: .googlePlacesApiKey) ?? ""
    googleOAuthClientID = try c.decodeIfPresent(String.self, forKey: .googleOAuthClientID) ?? AppConfig.defaultGoogleOAuthClientID
    googleOAuthRedirectURI = try c.decodeIfPresent(String.self, forKey: .googleOAuthRedirectURI) ??
      AppConfig.recommendedGoogleOAuthRedirectURI(for: googleOAuthClientID)
    googleOAuthScopes = try c.decodeIfPresent([String].self, forKey: .googleOAuthScopes) ?? [
      "https://www.googleapis.com/auth/calendar.readonly",
      "https://www.googleapis.com/auth/calendar.events",
    ]
    googleAccessToken = try c.decodeIfPresent(String.self, forKey: .googleAccessToken) ?? ""
    googleRefreshToken = try c.decodeIfPresent(String.self, forKey: .googleRefreshToken) ?? ""
    googleTokenExpiration = try c.decodeIfPresent(Date.self, forKey: .googleTokenExpiration)
    googleSelectedCalendarIDs = try c.decodeIfPresent([String].self, forKey: .googleSelectedCalendarIDs) ?? []
    googleDefaultCalendarID = try c.decodeIfPresent(String.self, forKey: .googleDefaultCalendarID) ?? ""
    externalIcalUrl = try c.decodeIfPresent(String.self, forKey: .externalIcalUrl) ?? ""
    pipelineAutoImportEnabled = try c.decodeIfPresent(Bool.self, forKey: .pipelineAutoImportEnabled) ?? true
    focusModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .focusModeEnabled) ?? false
    pomodoroWorkMinutes = try c.decodeIfPresent(Int.self, forKey: .pomodoroWorkMinutes) ?? 25
    pomodoroBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .pomodoroBreakMinutes) ?? 5
    urlBlockerRules = try c.decodeIfPresent([String].self, forKey: .urlBlockerRules) ?? []
    reminderPrefs = try c.decodeIfPresent(ReminderPrefs.self, forKey: .reminderPrefs) ?? .defaults
    marketSymbols = try c.decodeIfPresent([String].self, forKey: .marketSymbols) ?? ["^GSPC", "EURUSD=X", "BTC-USD"]
    newsEnabled = try c.decodeIfPresent(Bool.self, forKey: .newsEnabled) ?? true
    marketsEnabled = try c.decodeIfPresent(Bool.self, forKey: .marketsEnabled) ?? true
    notionFieldMap = try c.decodeIfPresent(NotionFieldMap.self, forKey: .notionFieldMap) ?? .init()
    notionStatusMap = try c.decodeIfPresent(NotionStatusMap.self, forKey: .notionStatusMap) ?? .init()
    wipLimits = try c.decodeIfPresent([String: Int].self, forKey: .wipLimits) ?? AppConfig.defaultWipLimits()
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(notionToken, forKey: .notionToken)
    try c.encode(notionDbId, forKey: .notionDbId)
    try c.encode(notionTodoDbId, forKey: .notionTodoDbId)
    try c.encode(bdfApiKey, forKey: .bdfApiKey)
    try c.encode(googlePlacesApiKey, forKey: .googlePlacesApiKey)
    try c.encode(googleOAuthClientID, forKey: .googleOAuthClientID)
    try c.encode(googleOAuthRedirectURI, forKey: .googleOAuthRedirectURI)
    try c.encode(googleOAuthScopes, forKey: .googleOAuthScopes)
    try c.encode(googleAccessToken, forKey: .googleAccessToken)
    try c.encode(googleRefreshToken, forKey: .googleRefreshToken)
    try c.encodeIfPresent(googleTokenExpiration, forKey: .googleTokenExpiration)
    try c.encode(googleSelectedCalendarIDs, forKey: .googleSelectedCalendarIDs)
    try c.encode(googleDefaultCalendarID, forKey: .googleDefaultCalendarID)
    try c.encode(externalIcalUrl, forKey: .externalIcalUrl)
    try c.encode(pipelineAutoImportEnabled, forKey: .pipelineAutoImportEnabled)
    try c.encode(focusModeEnabled, forKey: .focusModeEnabled)
    try c.encode(pomodoroWorkMinutes, forKey: .pomodoroWorkMinutes)
    try c.encode(pomodoroBreakMinutes, forKey: .pomodoroBreakMinutes)
    try c.encode(urlBlockerRules, forKey: .urlBlockerRules)
    try c.encode(reminderPrefs, forKey: .reminderPrefs)
    try c.encode(marketSymbols, forKey: .marketSymbols)
    try c.encode(newsEnabled, forKey: .newsEnabled)
    try c.encode(marketsEnabled, forKey: .marketsEnabled)
    try c.encode(notionFieldMap, forKey: .notionFieldMap)
    try c.encode(notionStatusMap, forKey: .notionStatusMap)
    try c.encode(wipLimits, forKey: .wipLimits)
  }
}

struct Stage: Identifiable, Codable, Hashable {
  var id: String = UUID().uuidString
  var title: String
  var company: String
  var url: String
  var location: String
  var status: StageStatus
  var deadline: Date?
  var notes: String
  var source: String
  var createdAt: Date
  var updatedAt: Date

  var displayLabel: String {
    [company, title].filter { !$0.isEmpty }.joined(separator: " - ")
  }
}

struct StageDraft: Equatable {
  var title: String = ""
  var company: String = ""
  var url: String = ""
  var location: String = ""
  var status: StageStatus = .open
  var deadline: Date? = nil
  var notes: String = ""
  var source: String = "manual"
}

enum TodoStatus: String, Codable, CaseIterable, Identifiable {
  case notStarted = "Not Started"
  case inProgress = "In Progress"
  case done = "Done"

  var id: String { rawValue }
}

struct TodoItem: Identifiable, Codable, Hashable {
  var id: String = UUID().uuidString
  var title: String
  var dueDate: Date
  var status: TodoStatus
  var notes: String
  var relatedStageID: String
  var automationTag: String
  var createdAt: Date
}

struct WeeklyStageProgress: Hashable {
  var status: StageStatus
  var count: Int
  var ratio: Double
}

struct WeeklyStageKPI: Hashable {
  var weekStart: Date
  var addedCount: Int
  var appliedCount: Int
  var totalCount: Int
  var progressByStatus: [WeeklyStageProgress]
}

struct StageBlocker: Identifiable, Hashable {
  var id: String { stage.id }
  var stage: Stage
  var stagnantDays: Int
  var reason: String
  var suggestedStatus: StageStatus
}

struct StageQualityIssue: Identifiable, Hashable {
  enum Field: String, Hashable {
    case company
    case url
    case deadline
  }

  var id: String { "\(stage.id)|\(field.rawValue)" }
  var stage: Stage
  var field: Field
  var suggestedValue: String
}

struct CalendarEvent: Identifiable, Codable, Hashable {
  enum SourceType: String, Codable, Hashable {
    case google
    case ical
    case notion
    case local
  }

  var id: String
  var summary: String
  var location: String
  var description: String
  var start: Date
  var end: Date
  var sourceUrl: String
  var meetingLink: String
  var calendarName: String
  var isAllDay: Bool
  var sourceType: SourceType = .local
  var eventType: EventType = .defaultType
  var attendees: [String] = []

  var whenText: String {
    if isAllDay {
      return start.shortDate
    }
    return "\(start.shortDateTime) -> \(end.shortDateTime)"
  }

  enum CodingKeys: String, CodingKey {
    case id
    case summary
    case location
    case description
    case start
    case end
    case sourceUrl
    case meetingLink
    case calendarName
    case isAllDay
    case sourceType
    case eventType
    case attendees
  }

  init(
    id: String,
    summary: String,
    location: String,
    description: String,
    start: Date,
    end: Date,
    sourceUrl: String,
    meetingLink: String,
    calendarName: String,
    isAllDay: Bool,
    sourceType: SourceType = .local,
    eventType: EventType = .defaultType,
    attendees: [String] = []
  ) {
    self.id = id
    self.summary = summary
    self.location = location
    self.description = description
    self.start = start
    self.end = end
    self.sourceUrl = sourceUrl
    self.meetingLink = meetingLink
    self.calendarName = calendarName
    self.isAllDay = isAllDay
    self.sourceType = sourceType
    self.eventType = eventType
    self.attendees = attendees
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? "Event"
    location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
    description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    start = try c.decode(Date.self, forKey: .start)
    end = try c.decode(Date.self, forKey: .end)
    sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl) ?? ""
    meetingLink = try c.decodeIfPresent(String.self, forKey: .meetingLink) ?? ""
    calendarName = try c.decodeIfPresent(String.self, forKey: .calendarName) ?? "Calendar"
    isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
    sourceType = try c.decodeIfPresent(SourceType.self, forKey: .sourceType) ?? .local
    eventType = try c.decodeIfPresent(EventType.self, forKey: .eventType) ?? .defaultType
    attendees = try c.decodeIfPresent([String].self, forKey: .attendees) ?? []
  }
}

struct ConnectionsSnapshot: Codable {
  var format: String
  var exportedAt: Date
  var includesSensitiveData: Bool
  var config: AppConfig
}

enum EventType: String, Codable, CaseIterable, Hashable {
  case defaultType = "default"
  case meeting
  case interview
  case deadline
}

struct ReminderPrefs: Codable, Hashable {
  var defaultMinutes: [Int]
  var meetingMinutes: [Int]
  var interviewMinutes: [Int]
  var deadlineMinutes: [Int]

  static var defaults: ReminderPrefs {
    .init(
      defaultMinutes: [30],
      meetingMinutes: [30],
      interviewMinutes: [120, 30],
      deadlineMinutes: [24 * 60, 60]
    )
  }

  func offsets(for eventType: EventType) -> [Int] {
    switch eventType {
    case .meeting:
      return meetingMinutes.isEmpty ? defaultMinutes : meetingMinutes
    case .interview:
      return interviewMinutes.isEmpty ? defaultMinutes : interviewMinutes
    case .deadline:
      return deadlineMinutes.isEmpty ? defaultMinutes : deadlineMinutes
    case .defaultType:
      return defaultMinutes
    }
  }
}

enum DiagnosticsSeverity: String, Codable, CaseIterable, Hashable {
  case info
  case warning
  case error
}

struct DiagnosticsEntry: Identifiable, Codable, Hashable {
  var id: String = UUID().uuidString
  var createdAt: Date
  var severity: DiagnosticsSeverity
  var category: String
  var message: String
  var metadata: [String: String]
}

struct MarketQuote: Identifiable, Codable, Hashable {
  var id: String { symbol }
  var symbol: String
  var shortName: String
  var price: Double
  var changePercent: Double
  var marketTime: Date
}

struct NewsItem: Identifiable, Codable, Hashable {
  var id: String
  var title: String
  var link: String
  var source: String
  var publishedAt: Date
}

struct PendingNotionOperation: Identifiable, Codable, Hashable {
  enum Kind: String, Codable, Hashable {
    case upsertStage
    case updateStatus
  }

  var id: String = UUID().uuidString
  var kind: Kind
  var stage: Stage?
  var stageID: String?
  var status: StageStatus?
  var createdAt: Date
  var retryCount: Int
}

struct PipelineImportPreview: Hashable {
  var title: String
  var company: String
  var url: String
  var location: String
  var description: String
  var deadline: Date?
  var source: String
}

struct GoogleCalendarDescriptor: Identifiable, Codable, Hashable {
  var id: String
  var name: String
  var isPrimary: Bool
}
