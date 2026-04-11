import Foundation

enum PipelineImportError: LocalizedError {
  case unsupportedSource
  case invalidURL
  case fetchFailed
  case parseFailed

  var errorDescription: String? {
    switch self {
    case .unsupportedSource:
      return "Unsupported source. Use LinkedIn/WelcomeToTheJungle/JobTeaser URL."
    case .invalidURL:
      return "Invalid URL."
    case .fetchFailed:
      return "Unable to fetch source page."
    case .parseFailed:
      return "Unable to parse job posting data."
    }
  }
}

struct PipelineImportService {
  func canImport(urlString: String) -> Bool {
    guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
    return host.contains("linkedin.com") ||
      host.contains("welcometothejungle.com") ||
      host.contains("jobteaser.com")
  }

  func importFromURL(_ urlString: String) async throws -> PipelineImportPreview {
    let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: clean) else { throw PipelineImportError.invalidURL }
    guard canImport(urlString: clean) else { throw PipelineImportError.unsupportedSource }

    var request = URLRequest(url: url)
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123 Safari/537.36",
      forHTTPHeaderField: "User-Agent"
    )
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw PipelineImportError.fetchFailed
    }
    guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
      throw PipelineImportError.fetchFailed
    }

    if let parsed = parseJSONLD(html: html, sourceURL: clean) {
      return parsed
    }

    if let parsed = parseFallbackMeta(html: html, sourceURL: clean) {
      return parsed
    }

    throw PipelineImportError.parseFailed
  }

  private func parseJSONLD(html: String, sourceURL: String) -> PipelineImportPreview? {
    let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
      return nil
    }
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
    let matches = regex.matches(in: html, range: nsRange)
    let decoder = JSONDecoder()

    for match in matches {
      guard let range = Range(match.range(at: 1), in: html) else { continue }
      let raw = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
      guard let data = raw.data(using: .utf8) else { continue }
      if let object = try? decoder.decode(JSONValue.self, from: data) {
        if let preview = findJobPosting(in: object, sourceURL: sourceURL) {
          return preview
        }
      } else if let sanitized = raw
        .replacingOccurrences(of: "\n", with: " ")
        .data(using: .utf8), let object = try? decoder.decode(JSONValue.self, from: sanitized)
      {
        if let preview = findJobPosting(in: object, sourceURL: sourceURL) {
          return preview
        }
      }
    }
    return nil
  }

  private func parseFallbackMeta(html: String, sourceURL: String) -> PipelineImportPreview? {
    let title = extractMeta(html: html, property: "og:title")
      ?? extractTagText(html: html, tag: "title")
      ?? ""
    let description = extractMeta(html: html, property: "og:description")
      ?? extractMeta(html: html, property: "description")
      ?? ""
    let company = extractMeta(html: html, property: "og:site_name") ?? inferCompany(from: sourceURL)
    let location = extractLocationFallback(html: html)

    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return PipelineImportPreview(
      title: title.trimmingCharacters(in: .whitespacesAndNewlines),
      company: company.trimmingCharacters(in: .whitespacesAndNewlines),
      url: sourceURL,
      location: location,
      description: description.trimmingCharacters(in: .whitespacesAndNewlines),
      deadline: extractDeadline(text: "\(title) \(description)"),
      source: URL(string: sourceURL)?.host ?? "pipeline"
    )
  }

  private func findJobPosting(in json: JSONValue, sourceURL: String) -> PipelineImportPreview? {
    switch json {
    case let .object(dict):
      if let type = dict["@type"]?.stringValue?.lowercased(), type.contains("jobposting") {
        let title = dict["title"]?.stringValue ?? ""
        let company = dict["hiringOrganization"]?.objectValue?["name"]?.stringValue
          ?? dict["hiringOrganization"]?.stringValue
          ?? inferCompany(from: sourceURL)
        let location = dict["jobLocation"]?.objectValue?["address"]?.objectValue?["addressLocality"]?.stringValue
          ?? dict["jobLocation"]?.objectValue?["name"]?.stringValue
          ?? ""
        let description = dict["description"]?.stringValue ?? ""
        let deadlineText = dict["validThrough"]?.stringValue ?? ""
        let deadline = parseDate(deadlineText)
        return PipelineImportPreview(
          title: title.isEmpty ? "Job posting" : title,
          company: company,
          url: sourceURL,
          location: location,
          description: description.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression),
          deadline: deadline,
          source: URL(string: sourceURL)?.host ?? "pipeline"
        )
      }
      for value in dict.values {
        if let found = findJobPosting(in: value, sourceURL: sourceURL) {
          return found
        }
      }
      return nil
    case let .array(values):
      for value in values {
        if let found = findJobPosting(in: value, sourceURL: sourceURL) {
          return found
        }
      }
      return nil
    default:
      return nil
    }
  }

  private func inferCompany(from urlString: String) -> String {
    guard let host = URL(string: urlString)?.host else { return "" }
    let trimmed = host.replacingOccurrences(of: "www.", with: "")
    let parts = trimmed.split(separator: ".")
    guard parts.count >= 2 else { return trimmed.capitalized }
    return String(parts[parts.count - 2]).capitalized
  }

  private func parseDate(_ raw: String) -> Date? {
    if let value = Date.iso8601WithFractionalSeconds.date(from: raw) { return value }
    if let value = Date.fallbackISO8601.date(from: raw) { return value }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: raw)
  }

  private func extractMeta(html: String, property: String) -> String? {
    let pattern = #"<meta[^>]*(?:property|name)=["']\#(property)["'][^>]*content=["']([^"']+)["'][^>]*>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
    guard let match = regex.firstMatch(in: html, range: nsRange), let range = Range(match.range(at: 1), in: html) else {
      return nil
    }
    return String(html[range])
  }

  private func extractTagText(html: String, tag: String) -> String? {
    let pattern = #"<\#(tag)[^>]*>(.*?)</\#(tag)>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
      return nil
    }
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
    guard let match = regex.firstMatch(in: html, range: nsRange), let range = Range(match.range(at: 1), in: html) else {
      return nil
    }
    return String(html[range]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
  }

  private func extractLocationFallback(html: String) -> String {
    let candidates = [
      #"<meta[^>]*name=["']job_location["'][^>]*content=["']([^"']+)["'][^>]*>"#,
      #"<span[^>]*class=["'][^"']*location[^"']*["'][^>]*>(.*?)</span>"#,
    ]
    for pattern in candidates {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
        continue
      }
      let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
      guard let match = regex.firstMatch(in: html, range: nsRange), let range = Range(match.range(at: 1), in: html) else {
        continue
      }
      let text = String(html[range]).replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
      let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !cleaned.isEmpty { return cleaned }
    }
    return ""
  }

  private func extractDeadline(text: String) -> Date? {
    let candidates = [
      #"\b\d{4}-\d{2}-\d{2}\b"#,
      #"\b\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4}\b"#,
    ]
    for pattern in candidates {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
      guard let match = regex.firstMatch(in: text, range: nsRange), let range = Range(match.range, in: text) else {
        continue
      }
      let raw = String(text[range]).replacingOccurrences(of: ".", with: "/")
      if let d = parseDate(raw) {
        return d
      }
      let parts = raw.split(separator: "/")
      if parts.count == 3 {
        let day = String(parts[0]).count == 1 ? "0\(parts[0])" : String(parts[0])
        let month = String(parts[1]).count == 1 ? "0\(parts[1])" : String(parts[1])
        var year = String(parts[2])
        if year.count == 2 { year = "20\(year)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: "\(year)-\(month)-\(day)")
      }
    }
    return nil
  }
}

private enum JSONValue: Decodable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }
  }

  var stringValue: String? {
    if case let .string(v) = self { return v }
    return nil
  }

  var objectValue: [String: JSONValue]? {
    if case let .object(v) = self { return v }
    return nil
  }
}
