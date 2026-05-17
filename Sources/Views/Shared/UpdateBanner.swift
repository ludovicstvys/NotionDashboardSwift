import SwiftUI

#if os(macOS)
struct UpdateBanner: View {
  @ObservedObject var updateStore: UpdateStore
  @State private var isDismissed = false

  var body: some View {
    if let manifest = updateStore.availableUpdate, !isDismissed {
      HStack(spacing: 14) {
        Image(systemName: "sparkles")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(WorkspacePalette.accent)
          .padding(8)
          .background(WorkspacePalette.accent.opacity(0.18))
          .clipShape(Circle())

        VStack(alignment: .leading, spacing: 2) {
          Text("Update available")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
          Text("Version \(manifest.versionLabel) is ready to install.")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.72))
        }

        Spacer(minLength: 8)

        if manifest.releaseNotesURL != nil {
          Button("Release notes") {
            updateStore.openReleaseNotesURL()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        Button("Install…") {
          Task { await updateStore.checkForUpdates(userInitiated: true) }
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkspacePalette.accent)
        .controlSize(.small)

        Button {
          isDismissed = true
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss update banner")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(WorkspacePalette.panelRaised.opacity(0.96))
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(WorkspacePalette.accent.opacity(0.32), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
      .padding(.horizontal, 18)
      .padding(.top, 12)
      .transition(.move(edge: .top).combined(with: .opacity))
      .onChange(of: manifest.id) { _ in
        isDismissed = false
      }
    }
  }
}
#endif
