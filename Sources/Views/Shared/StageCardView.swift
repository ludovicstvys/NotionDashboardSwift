import SwiftUI

struct StageCardView: View {
  let stage: Stage
  let limitExceeded: Bool
  let onStatusChange: (StageStatus) -> Void
  let onDelete: () -> Void

  @Environment(\.openURL) private var openURL
  @EnvironmentObject private var focusStore: FocusStore
  @State private var blockedMessage: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(stage.company.isEmpty ? "Unknown company" : stage.company)
            .font(.headline)
            .foregroundStyle(.white)
          Text(stage.title.isEmpty ? "Stage" : stage.title)
            .font(.subheadline)
            .foregroundStyle(Color.white.opacity(0.72))
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        WorkspaceBadge(text: stage.status.rawValue, tint: colorForStatus(stage.status))
      }

      HStack(spacing: 8) {
        if let deadline = stage.deadline {
          stageMetaChip(text: deadline.shortDate, systemImage: "clock", tint: limitExceeded ? .red : .orange)
        }
        if !stage.location.isEmpty {
          stageMetaChip(text: stage.location, systemImage: "mappin.and.ellipse", tint: .teal)
        }
        if !stage.source.isEmpty {
          stageMetaChip(text: stage.source, systemImage: "shippingbox", tint: .white, usesNeutralStyle: true)
        }
      }

      if !stage.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(stage.notes)
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.68))
          .lineLimit(3)
      }

      HStack(spacing: 8) {
        if !stage.url.isEmpty {
          Button {
            guard let url = URL(string: stage.url) else { return }
            if focusStore.isBlocked(url: url) {
              blockedMessage = focusStore.blockedReason(for: url)
              return
            }
            openURL(url)
          } label: {
            Label("Open offer", systemImage: "link")
          }
          .buttonStyle(.bordered)
          .font(.caption.weight(.semibold))
          .tint(.teal)
        }

        Menu {
          ForEach(StageStatus.allCases) { status in
            if status != stage.status {
              Button(status.rawValue) {
                onStatusChange(status)
              }
            }
          }
        } label: {
          Label("Move", systemImage: "arrow.triangle.2.circlepath")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.orange)

        Button(role: .destructive, action: onDelete) {
          Label("Delete", systemImage: "trash")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .workspaceInteractiveSurface(cornerRadius: 22, tint: limitExceeded ? .red : colorForStatus(stage.status))
    .alert("Blocked", isPresented: Binding(get: { !blockedMessage.isEmpty }, set: { if !$0 { blockedMessage = "" } })) {
      Button("OK", role: .cancel) {
        blockedMessage = ""
      }
    } message: {
      Text(blockedMessage)
    }
  }

  private func stageMetaChip(text: String, systemImage: String, tint: Color, usesNeutralStyle: Bool = false) -> some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
      Text(text)
        .lineLimit(1)
    }
    .font(.caption2.weight(.semibold))
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background((usesNeutralStyle ? Color.white : tint).opacity(usesNeutralStyle ? 0.08 : 0.18))
    .foregroundStyle(usesNeutralStyle ? Color.white.opacity(0.72) : tint)
    .clipShape(Capsule())
  }

  private func colorForStatus(_ status: StageStatus) -> Color {
    switch status {
    case .open: return .blue
    case .applied: return .green
    case .interview: return .orange
    case .rejected: return .red
    }
  }
}
