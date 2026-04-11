import SwiftUI

extension View {
  @ViewBuilder
  func plainTextInputBehavior() -> some View {
#if os(iOS)
    textInputAutocapitalization(.never)
      .autocorrectionDisabled()
#else
    self
#endif
  }
}
