import Foundation

enum GoogleCalendarError: LocalizedError {
  case invalidResponse
  case requestFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Invalid Google Calendar response."
    case let .requestFailed(message):
      return "Google Calendar request failed: \(message)"
    }
  }
}

struct GoogleCalendarService {
  private let baseURL = "https://www.googleapis.com/calendar/v3"

  func listCalendars(accessToken: String) async throws -> [GoogleCalendarDescriptor] {
    let response = try await request(path: "users/me/calendarList", accessToken: accessToken)
    let items = response["items"] as? [[String: Any]] ?? []
    return items.compactMap { item in
      guard let id = item["id"] as? String else { return nil }
      let name = (item["summary"] as? String) ?? id
      let primary = (item["primary"] as? Bool) ?? false
      return GoogleCalendarDescriptor(id: id, name: name, isPrimary: primary)
    }
  }

  func fetchEvents(
    accessToken: String,
    calendarIDs: [String],
    timeMin: Date,
    timeMax: Date
  ) async throws -> [CalendarEvent] {
    let ids = calendarIDs.isEmpty ? ["primary"] : calendarIDs
    var all: [CalendarEvent] = []
    for id in ids {
      let query: [URLQueryItem] = [
        .init(name: "timeMin", value: timeMin.iso8601String),
        .init(name: "timeMax", value: timeMax.iso8601String),
        .init(name: "singleEvents", value: "true"),
        .init(name: "orderBy", value: "startTime"),
        .init(name: "maxResults", value: "250"),
      ]
      let payload = try await request(
        path: "calendars/\(id.urlPathEncoded)/events",
        queryItems: query,
        accessToken: accessToken
      )
      let items = payload["items"] as? [[String: Any]] ?? []
      let mapped = items.compactMap { item in
        parseEvent(item: item, calendarNameFallback: id)
      }
      all.append(contentsOf: mapped)
    }
    return all.sorted { $0.start < $1.start }
  }

  func createEvent(
    accessToken: String,
    calendarID: String,
    summary: String,
    location: String,
    description: String,
    start: Date,
    end: Date
  ) async throws -> String {
    guard let url = URL(string: "\(baseURL)/calendars/\(calendarID.urlPathEncoded)/events") else {
      throw GoogleCalendarError.invalidResponse
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let payload: [String: Any] = [
      "summary": summary,
      "location": location,
      "description": description,
      "start": ["dateTime": start.iso8601String],
      "end": ["dateTime": end.iso8601String],
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else {
      throw GoogleCalendarError.invalidResponse
    }
    if !(200...299).contains(http.statusCode) {
      let message = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw GoogleCalendarError.requestFailed(message)
    }
    guard
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = object["id"] as? String
    else {
      throw GoogleCalendarError.invalidResponse
    }
    return id
  }

  private func request(
    path: String,
    queryItems: [URLQueryItem] = [],
    accessToken: String
  ) async throws -> [String: Any] {
    var components = URLComponents(string: "\(baseURL)/\(path)")
    if !queryItems.isEmpty {
      components?.queryItems = queryItems
    }
    guard let url = components?.url else {
      throw GoogleCalendarError.invalidResponse
    }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    req.addValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else {
      throw GoogleCalendarError.invalidResponse
    }
    if !(200...299).contains(http.statusCode) {
      let message = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw GoogleCalendarError.requestFailed(message)
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw GoogleCalendarError.invalidResponse
    }
    return object
  }

  private func parseEvent(item: [String: Any], calendarNameFallback: String) -> CalendarEvent? {
    guard let id = item["id"] as? String else { return nil }
    let summary = (item["summary"] as? String) ?? "Event"
    let location = (item["location"] as? String) ?? ""
    let description = (item["description"] as? String) ?? ""
    let htmlLink = (item["htmlLink"] as? String) ?? ""
    let attendees = ((item["attendees"] as? [[String: Any]]) ?? [])
      .compactMap { $0["email"] as? String }

    let startPayload = item["start"] as? [String: Any] ?? [:]
    let endPayload = item["end"] as? [String: Any] ?? [:]
    let startDate = parseGoogleDate(startPayload)
    let endDate = parseGoogleDate(endPayload) ?? startDate?.addingTimeInterval(60 * 60)
    guard let startDate, let endDate else { return nil }
    let isAllDay = startPayload["date"] != nil

    let meetingLink = extractMeetingLink(from: description) ?? extractMeetingLink(from: htmlLink) ?? ""
    let eventType = detectEventType(summary: summary, description: description, location: location)

    return CalendarEvent(
      id: id,
      summary: summary,
      location: location,
      description: description,
      start: startDate,
      end: endDate,
      sourceUrl: htmlLink,
      meetingLink: meetingLink,
      calendarName: calendarNameFallback,
      isAllDay: isAllDay,
      sourceType: .google,
      eventType: eventType,
      attendees: attendees
    )
  }

  private func parseGoogleDate(_ payload: [String: Any]) -> Date? {
    if let dateTime = payload["dateTime"] as? String {
      if let date = Date.iso8601WithFractionalSeconds.date(from: dateTime) {
        return date
      }
      if let date = Date.fallbackISO8601.date(from: dateTime) {
        return date
      }
    }
    if let allDay = payload["date"] as? String {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      return formatter.date(from: allDay)
    }
    return nil
  }

  private func extractMeetingLink(from text: String) -> String? {
    let pattern = #"https?://[^\s]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: nsRange), let range = Range(match.range, in: text) else {
      return nil
    }
    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func detectEventType(summary: String, description: String, location: String) -> EventType {
    let combined = "\(summary) \(description) \(location)".normalizedToken
    if combined.contains("deadline") || combined.contains("date limite") || combined.contains("due") {
      return .deadline
    }
    if combined.contains("entretien") || combined.contains("interview") {
      return .interview
    }
    if combined.contains("meet") || combined.contains("teams") || combined.contains("zoom") || combined.contains("google meet") {
      return .meeting
    }
    return .defaultType
  }
}

private extension String {
  var urlPathEncoded: String {
    addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
  }
}
