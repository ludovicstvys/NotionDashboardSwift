import SwiftUI

struct StageCardView: View {
  let stage: Stage
  let limitExceeded: Bool
  let isHighlighted: Bool
  let onStatusChange: (StageStatus) -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(stage.company.isEmpty ? "Unknown company" : stage.company)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
          Text(stage.title.isEmpty ? "Stage" : stage.title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.78))
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        WorkspaceBadge(text: stage.status.rawValue, tint: colorForStatus(stage.status))
      }

      HStack(spacing: 8) {
        if let deadline = stage.deadline {
          stageMetaChip(text: deadline.shortDate, systemImage: "clock", tint: limitExceeded ? .red : WorkspacePalette.warning)
        }
        if !stage.location.isEmpty {
          stageMetaChip(text: stage.location, systemImage: "mappin.and.ellipse", tint: WorkspacePalette.accent)
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
          ProtectedLinkButton(title: "Open offer", systemImage: "link", urlString: stage.url, tint: WorkspacePalette.accent)
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
        .tint(WorkspacePalette.warning)

        Button(role: .destructive, action: onDelete) {
          Label("Delete", systemImage: "trash")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(WorkspacePalette.panelRaised)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(isHighlighted ? WorkspacePalette.accent.opacity(0.34) : Color.white.opacity(0.08), lineWidth: 1)
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
    case .open: return WorkspacePalette.accent
    case .applied: return WorkspacePalette.success
    case .interview: return WorkspacePalette.warning
    case .rejected: return .red
    }
  }
}

struct StageListRowView: View, Equatable {
  let item: StagesReadModel
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(item.company.isEmpty ? "Unknown company" : item.company)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(1)

        Spacer(minLength: 8)

        WorkspaceBadge(text: item.status.rawValue, tint: colorForStatus(item.status))
      }

      Text(item.title.isEmpty ? "Stage" : item.title)
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.white.opacity(0.72))
        .lineLimit(2)

      HStack(spacing: 8) {
        Text(item.updatedAt.shortDate)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(Color.white.opacity(0.66))
          .lineLimit(1)

        if let closeDate = item.closeDate {
          Text(closeDate.shortDate)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WorkspacePalette.warning)
            .lineLimit(1)
        }

        if item.hasTodos {
          Image(systemName: "checklist")
            .font(.caption2.weight(.bold))
            .foregroundStyle(WorkspacePalette.accent)
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(isSelected ? WorkspacePalette.panelRaised : WorkspacePalette.panelBase.opacity(0.54))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(isSelected ? WorkspacePalette.accent.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
    )
  }

  private func colorForStatus(_ status: StageStatus) -> Color {
    switch status {
    case .open: return WorkspacePalette.accent
    case .applied: return WorkspacePalette.success
    case .interview: return WorkspacePalette.warning
    case .rejected: return .red
    }
  }
}

struct StageDetailPanel: View {
  let detail: StageDetailViewState
  let onStatusChange: (StageStatus) -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      detailHeader

      if detail.relatedTodos.isEmpty {
        WorkspaceEmptyState(
          title: "No related todo",
          message: "This stage currently has no linked follow-up item.",
          tint: WorkspacePalette.accentSoft,
          systemImage: "checklist"
        )
      } else {
        WorkspacePanel(title: "Related todos", subtitle: "Follow-up items linked to this selected stage.", tint: WorkspacePalette.accentSoft) {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(detail.relatedTodos.prefix(6)) { todo in
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                  Text(todo.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                  Text(todo.dueDate.shortDate)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.66))
                }
                Spacer()
                WorkspaceBadge(text: todo.status.rawValue, tint: todoColor(todo.status))
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
    }
  }

  private var detailHeader: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text(detail.stage.company.isEmpty ? "Unknown company" : detail.stage.company)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
          Text(detail.stage.title.isEmpty ? "Stage" : detail.stage.title)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 12)

        WorkspaceBadge(text: detail.stage.status.rawValue, tint: stageColor(detail.stage.status))
      }

      HStack(spacing: 8) {
        if let deadline = detail.stage.deadline {
          infoChip(title: deadline.shortDate, systemImage: "clock", tint: WorkspacePalette.warning)
        }
        if !detail.stage.location.isEmpty {
          infoChip(title: detail.stage.location, systemImage: "mappin.and.ellipse", tint: WorkspacePalette.accent)
        }
        if !detail.stage.source.isEmpty {
          infoChip(title: detail.stage.source, systemImage: "shippingbox", tint: .white, neutral: true)
        }
      }

      if !detail.stage.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Notes")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.64))
          Text(detail.stage.notes)
            .font(.subheadline)
            .foregroundStyle(Color.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      HStack(spacing: 8) {
        if !detail.stage.url.isEmpty {
          ProtectedLinkButton(title: "Open offer", systemImage: "link", urlString: detail.stage.url, tint: WorkspacePalette.accent)
        }

        Menu {
          ForEach(StageStatus.allCases) { status in
            if status != detail.stage.status {
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
        .tint(WorkspacePalette.warning)

        Button(role: .destructive, action: onDelete) {
          Label("Delete", systemImage: "trash")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(WorkspacePalette.panelRaised)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(WorkspacePalette.warning.opacity(0.20), lineWidth: 1)
    )
  }

  private func infoChip(title: String, systemImage: String, tint: Color, neutral: Bool = false) -> some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
      Text(title)
        .lineLimit(1)
    }
    .font(.caption2.weight(.semibold))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background((neutral ? Color.white : tint).opacity(neutral ? 0.08 : 0.16))
    .foregroundStyle(neutral ? Color.white.opacity(0.74) : tint)
    .clipShape(Capsule())
  }

  private func stageColor(_ status: StageStatus) -> Color {
    switch status {
    case .open: return WorkspacePalette.accent
    case .applied: return WorkspacePalette.success
    case .interview: return WorkspacePalette.warning
    case .rejected: return .red
    }
  }

  private func todoColor(_ status: TodoStatus) -> Color {
    switch status {
    case .notStarted: return WorkspacePalette.warning
    case .inProgress: return WorkspacePalette.accent
    case .done: return WorkspacePalette.success
    }
  }
}
