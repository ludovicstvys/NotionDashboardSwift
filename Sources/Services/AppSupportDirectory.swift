import Foundation
#if os(macOS)
import Darwin
#endif

enum AppSupportDirectory {
  private static let folderName = "NotionDashboard"

  static var url: URL {
#if os(macOS)
    if let homeURL = realHomeURL {
      let directoryURL = homeURL
        .appendingPathComponent("Library/Application Support", isDirectory: true)
        .appendingPathComponent(folderName, isDirectory: true)
      try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      return directoryURL
    }
#endif
    let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let directoryURL = baseURL.appendingPathComponent(folderName, isDirectory: true)
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
  }

  static func fileURL(_ fileName: String) -> URL {
    url.appendingPathComponent(fileName, isDirectory: false)
  }
}

enum LegacyPreferences {
  static let bundleIdentifier = "com.loldashboard.notiondashboard.macos"

  static func data(forKey key: String) -> Data? {
#if os(macOS)
    guard
      let url = preferencesURL(),
      let plistData = try? Data(contentsOf: url),
      let plist = try? PropertyListSerialization.propertyList(
        from: plistData,
        options: [],
        format: nil
      ) as? [String: Any]
    else {
      return nil
    }
    return plist[key] as? Data
#else
    return nil
#endif
  }

#if os(macOS)
  private static func preferencesURL() -> URL? {
    realHomeURL?
      .appendingPathComponent("Library/Preferences", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier).plist", isDirectory: false)
  }
#endif
}

#if os(macOS)
private var realHomeURL: URL? {
  guard let homePointer = getpwuid(getuid())?.pointee.pw_dir else { return nil }
  return URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
}
#endif
