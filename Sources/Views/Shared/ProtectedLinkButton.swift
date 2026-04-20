import SwiftUI

struct ProtectedLinkButton: View {
  @Environment(\.openURL) private var openURL
  @EnvironmentObject private var focusStore: FocusStore
  @State private var blockedMessage: String = ""

  let title: String
  let systemImage: String
  let urlString: String
  let tint: Color

  var body: some View {
    Button {
      guard let url = normalizedURL(from: urlString) else { return }
      if focusStore.isBlocked(url: url) {
        blockedMessage = focusStore.blockedReason(for: url)
        return
      }
      openURL(url)
    } label: {
      Label(title, systemImage: systemImage)
    }
    .buttonStyle(.bordered)
    .font(.caption.weight(.semibold))
    .tint(tint)
    .alert("Blocked", isPresented: Binding(get: { !blockedMessage.isEmpty }, set: { if !$0 { blockedMessage = "" } })) {
      Button("OK", role: .cancel) { blockedMessage = "" }
    } message: {
      Text(blockedMessage)
    }
  }

  private func normalizedURL(from raw: String) -> URL? {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    if let url = URL(string: clean), url.host != nil {
      return url
    }
    if clean.contains("://"), let url = URL(string: clean) {
      return url
    }
    return URL(string: "https://\(clean)")
  }
}
