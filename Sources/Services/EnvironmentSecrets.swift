import Foundation

struct EnvironmentSecrets {
  let googleOAuthClientID: String?
  let googleOAuthClientSecret: String?

  static func load() -> EnvironmentSecrets {
    let environment = ProcessInfo.processInfo.environment
    let envFileValues = loadDotEnvValues()

    return EnvironmentSecrets(
      googleOAuthClientID: firstNonEmptyValue(
        environment["GOOGLE_OAUTH_CLIENT_ID"],
        envFileValues["GOOGLE_OAUTH_CLIENT_ID"]
      ),
      googleOAuthClientSecret: firstNonEmptyValue(
        environment["GOOGLE_OAUTH_CLIENT_SECRET"],
        envFileValues["GOOGLE_OAUTH_CLIENT_SECRET"]
      )
    )
  }

  private static func loadDotEnvValues() -> [String: String] {
    for url in candidateDotEnvURLs() {
      guard
        let data = try? Data(contentsOf: url),
        let text = String(data: data, encoding: .utf8)
      else {
        continue
      }
      return parseDotEnv(text)
    }
    return [:]
  }

  private static func candidateDotEnvURLs() -> [URL] {
    var candidates: [URL] = []

    candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appendingPathComponent(".env"))
    candidates.append(AppSupportDirectory.fileURL(".env"))

#if os(macOS)
    candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".env"))
#endif

    if let resourceURL = Bundle.main.resourceURL {
      let bundleURL = resourceURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      candidates.append(bundleURL.appendingPathComponent(".env"))
    }

    return candidates
  }

  private static func parseDotEnv(_ text: String) -> [String: String] {
    var values: [String: String] = [:]

    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty, !line.hasPrefix("#"), let separatorIndex = line.firstIndex(of: "=") else {
        continue
      }

      let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty else { continue }

      let rawValue = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
      values[key] = normalizedValue(rawValue)
    }

    return values
  }

  private static func normalizedValue(_ value: String) -> String {
    guard value.count >= 2 else { return value }
    if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
      return String(value.dropFirst().dropLast())
    }
    return value
  }

  private static func firstNonEmptyValue(_ values: String?...) -> String? {
    values
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty })
  }
}
