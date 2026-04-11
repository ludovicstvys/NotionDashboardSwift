import Foundation

extension Date {
  static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static let fallbackISO8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  static let shortDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
  }()

  static let shortDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  var shortDateTime: String {
    Date.shortDateTimeFormatter.string(from: self)
  }

  var shortDate: String {
    Date.shortDateFormatter.string(from: self)
  }

  var iso8601String: String {
    Date.iso8601WithFractionalSeconds.string(from: self)
  }

  func startOfWeekMonday(calendar: Calendar = .current) -> Date {
    var cal = calendar
    cal.firstWeekday = 2
    let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
    return cal.date(from: components) ?? self
  }

  func addingDays(_ days: Int, calendar: Calendar = .current) -> Date {
    calendar.date(byAdding: .day, value: days, to: self) ?? self
  }
}

extension String {
  var normalizedToken: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .folding(options: .diacriticInsensitive, locale: .current)
      .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
