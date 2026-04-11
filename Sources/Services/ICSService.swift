import Foundation

enum ICSServiceError: LocalizedError {
  case invalidURL
  case fetchFailed
  case invalidContent

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid iCal URL."
    case .fetchFailed:
      return "Unable to fetch iCal feed."
    case .invalidContent:
      return "Invalid iCal content."
    }
  }
}

struct ICSService {
  func fetchEvents(from urlString: String, range: DateInterval? = nil) async throws -> [CalendarEvent] {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), !trimmed.isEmpty else {
      throw ICSServiceError.invalidURL
    }

    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw ICSServiceError.fetchFailed
    }
    guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
      throw ICSServiceError.invalidContent
    }

    let events = parseEvents(icsText: text, sourceURL: url.absoluteString)
    guard let range else {
      return events.sorted { $0.start < $1.start }
    }
    return events.filter { range.contains($0.start) }.sorted { $0.start < $1.start }
  }

  private func parseEvents(icsText: String, sourceURL: String) -> [CalendarEvent] {
    let lines = unfoldLines(icsText)
    var events: [CalendarEvent] = []
    var current: [String: String] = [:]
    var currentParams: [String: [String: String]] = [:]

    for line in lines {
      if line == "BEGIN:VEVENT" {
        current = [:]
        currentParams = [:]
        continue
      }
      if line == "END:VEVENT" {
        if let event = buildEvent(from: current, params: currentParams, sourceURL: sourceURL) {
          events.append(event)
        }
        current = [:]
        currentParams = [:]
        continue
      }

      let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { continue }
      let rawKey = String(parts[0])
      let rawValue = String(parts[1])
      let keyParts = rawKey.split(separator: ";")
      guard let base = keyParts.first else { continue }
      let key = String(base).uppercased()

      var params: [String: String] = [:]
      keyParts.dropFirst().forEach { segment in
        let pair = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pair.count == 2 else { return }
        params[String(pair[0]).uppercased()] = String(pair[1])
      }

      current[key] = rawValue
      currentParams[key] = params
    }

    return events
  }

  private func buildEvent(
    from values: [String: String],
    params: [String: [String: String]],
    sourceURL: String
  ) -> CalendarEvent? {
    guard
      let startRaw = values["DTSTART"],
      let parsedStart = parseDateValue(startRaw, params: params["DTSTART"] ?? [:])
    else { return nil }

    let endRaw = values["DTEND"] ?? startRaw
    let parsedEnd = parseDateValue(endRaw, params: params["DTEND"] ?? params["DTSTART"] ?? [:]) ?? parsedStart
    let uid = values["UID"] ?? UUID().uuidString
    let summary = unescapeText(values["SUMMARY"] ?? "Event")
    let location = unescapeText(values["LOCATION"] ?? "")
    let description = unescapeText(values["DESCRIPTION"] ?? "")
    let url = normalizeURL(values["URL"] ?? "")
    let eventType = detectEventType(summary: summary, description: description, location: location)

    return CalendarEvent(
      id: uid.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression),
      summary: summary,
      location: location,
      description: description,
      start: parsedStart.date,
      end: parsedEnd.date,
      sourceUrl: url.isEmpty ? sourceURL : url,
      meetingLink: extractMeetingLink(from: description).isEmpty ? url : extractMeetingLink(from: description),
      calendarName: "External iCal",
      isAllDay: parsedStart.allDay,
      sourceType: .ical,
      eventType: eventType,
      attendees: []
    )
  }

  private func parseDateValue(_ raw: String, params: [String: String]) -> (date: Date, allDay: Bool)? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    let isDateOnly = (params["VALUE"] ?? "").uppercased() == "DATE" || value.range(of: #"^\d{8}$"#, options: .regularExpression) != nil
    if isDateOnly {
      guard value.count == 8 else { return nil }
      let year = String(value.prefix(4))
      let month = String(value.dropFirst(4).prefix(2))
      let day = String(value.dropFirst(6).prefix(2))
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      guard let date = formatter.date(from: "\(year)-\(month)-\(day)") else { return nil }
      return (date, true)
    }

    if value.hasSuffix("Z") {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      if let date = formatter.date(from: value) {
        return (date, false)
      }
    }

    let localFormatter = DateFormatter()
    localFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
    if let date = localFormatter.date(from: value) {
      return (date, false)
    }

    let compactFormatter = DateFormatter()
    compactFormatter.dateFormat = "yyyyMMdd'T'HHmm"
    if let date = compactFormatter.date(from: value) {
      return (date, false)
    }
    return nil
  }

  private func unfoldLines(_ text: String) -> [String] {
    let raw = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)

    var result: [String] = []
    for line in raw {
      if line.hasPrefix(" ") || line.hasPrefix("\t"), !result.isEmpty {
        result[result.count - 1].append(contentsOf: String(line.dropFirst()))
      } else {
        result.append(line)
      }
    }
    return result
  }

  private func unescapeText(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\n", with: "\n")
      .replacingOccurrences(of: "\\,", with: ",")
      .replacingOccurrences(of: "\\;", with: ";")
      .replacingOccurrences(of: "\\\\", with: "\\")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func normalizeURL(_ value: String) -> String {
    let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return "" }
    guard let url = URL(string: raw) else { return "" }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return "" }
    return url.absoluteString
  }

  private func extractMeetingLink(from text: String) -> String {
    let pattern = #"https?://[^\s]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    guard
      let match = regex.firstMatch(in: text, range: nsRange),
      let range = Range(match.range, in: text)
    else { return "" }
    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func detectEventType(summary: String, description: String, location: String) -> EventType {
    let text = "\(summary) \(description) \(location)".normalizedToken
    if text.contains("deadline") || text.contains("date limite") || text.contains("due") {
      return .deadline
    }
    if text.contains("entretien") || text.contains("interview") {
      return .interview
    }
    if text.contains("meet") || text.contains("zoom") || text.contains("teams") {
      return .meeting
    }
    return .defaultType
  }
}
