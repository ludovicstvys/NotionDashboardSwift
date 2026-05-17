import SwiftUI

// Identifiable wrapper so any Error can drive a SwiftUI .alert.
struct AppErrorAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String

  init(title: String = "Something went wrong", error: Error) {
    self.title = title
    if let local = error as? LocalizedError, let description = local.errorDescription {
      self.message = description
    } else {
      self.message = error.localizedDescription
    }
  }

  init(title: String, message: String) {
    self.title = title
    self.message = message
  }
}

extension View {
  // Single point for error presentation. Pair a @State var with this modifier
  // and assign on catch sites.
  // Example:
  //   @State private var errorAlert: AppErrorAlert?
  //   .errorAlert($errorAlert)
  //   ...
  //   catch { errorAlert = AppErrorAlert(error: error) }
  func errorAlert(_ binding: Binding<AppErrorAlert?>) -> some View {
    alert(item: binding) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
      )
    }
  }
}
