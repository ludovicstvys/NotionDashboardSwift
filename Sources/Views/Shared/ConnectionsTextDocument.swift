import SwiftUI
import UniformTypeIdentifiers

struct ConnectionsTextDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plainText, .json] }
  static var writableContentTypes: [UTType] { [.plainText] }

  var text: String

  init(text: String = "") {
    self.text = text
  }

  init(configuration: ReadConfiguration) throws {
    guard
      let data = configuration.file.regularFileContents,
      let string = String(data: data, encoding: .utf8)
    else {
      self.text = ""
      return
    }
    self.text = string
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let data = text.data(using: .utf8) ?? Data()
    return FileWrapper(regularFileWithContents: data)
  }
}
