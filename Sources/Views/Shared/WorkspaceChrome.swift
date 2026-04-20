import SwiftUI

enum WorkspaceSizeClass {
  case compact
  case medium
  case wide

  init(width: CGFloat) {
    if width >= 1_120 {
      self = .wide
    } else if width >= 900 {
      self = .medium
    } else {
      self = .compact
    }
  }
}

struct WorkspaceLayoutMetrics {
  let sizeClass: WorkspaceSizeClass
  let horizontalPadding: CGFloat
  let contentMaxWidth: CGFloat
  let sectionSpacing: CGFloat
  let panelGap: CGFloat
  let compactPanelPadding: CGFloat
  let regularPanelPadding: CGFloat

  init(width: CGFloat) {
    let sizeClass = WorkspaceSizeClass(width: width)
    self.sizeClass = sizeClass
    contentMaxWidth = 1_440

    switch sizeClass {
    case .wide:
      horizontalPadding = 28
      sectionSpacing = 24
      panelGap = 20
      compactPanelPadding = 22
      regularPanelPadding = 28
    case .medium:
      horizontalPadding = 24
      sectionSpacing = 22
      panelGap = 18
      compactPanelPadding = 20
      regularPanelPadding = 24
    case .compact:
      horizontalPadding = 18
      sectionSpacing = 20
      panelGap = 16
      compactPanelPadding = 18
      regularPanelPadding = 22
    }
  }
}

enum WorkspacePalette {
  static let backgroundTop = Color(red: 0.04, green: 0.08, blue: 0.10)
  static let backgroundBottom = Color(red: 0.08, green: 0.12, blue: 0.14)
  static let panelBase = Color(red: 0.10, green: 0.14, blue: 0.16).opacity(0.97)
  static let panelRaised = Color(red: 0.14, green: 0.18, blue: 0.20).opacity(0.985)
  static let innerCard = Color.white.opacity(0.055)
  static let line = Color.white.opacity(0.08)
  static let subtleText = Color.white.opacity(0.64)
  static let primaryText = Color.white
  static let accent = Color(red: 0.18, green: 0.73, blue: 0.80)
  static let accentSoft = Color(red: 0.57, green: 0.87, blue: 0.83)
  static let success = Color(red: 0.42, green: 0.85, blue: 0.56)
  static let warning = Color(red: 0.98, green: 0.70, blue: 0.30)
}

struct WorkspaceBackground: View, Equatable {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          WorkspacePalette.backgroundTop,
          WorkspacePalette.backgroundBottom,
          Color(red: 0.12, green: 0.14, blue: 0.18),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      RadialGradient(
        colors: [WorkspacePalette.accent.opacity(0.18), .clear],
        center: .topLeading,
        startRadius: 30,
        endRadius: 420
      )
      .offset(x: -140, y: -120)

      RadialGradient(
        colors: [Color.white.opacity(0.07), .clear],
        center: .top,
        startRadius: 30,
        endRadius: 360
      )
      .offset(x: 0, y: -220)

      RadialGradient(
        colors: [WorkspacePalette.accentSoft.opacity(0.10), .clear],
        center: .bottomTrailing,
        startRadius: 20,
        endRadius: 500
      )
      .offset(x: 180, y: 220)

      LinearGradient(
        colors: [
          Color.white.opacity(0.05),
          .clear,
          Color.white.opacity(0.03),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .blendMode(.softLight)
      .opacity(0.28)
    }
  }
}

struct WorkspacePanel<Content: View>: View {
  let title: String?
  let subtitle: String?
  let tint: Color
  let padding: CGFloat
  let content: Content

  init(
    title: String? = nil,
    subtitle: String? = nil,
    tint: Color = .teal,
    padding: CGFloat = 24,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.tint = tint
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let title {
        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(WorkspacePalette.primaryText)
          if let subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(WorkspacePalette.subtleText)
          }
        }
      }

      content
    }
    .padding(padding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .workspaceInteractiveSurface(cornerRadius: 30, tint: tint)
  }
}

struct WorkspaceCommandBar<Content: View>: View {
  let title: String
  let subtitle: String
  let tint: Color
  let content: Content

  init(
    title: String,
    subtitle: String,
    tint: Color = .teal,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.tint = tint
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title.uppercased())
          .font(.caption2.weight(.bold))
          .tracking(1.8)
          .foregroundStyle(WorkspacePalette.subtleText)
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(WorkspacePalette.primaryText)
      }

      Spacer(minLength: 0)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          content
        }
        .fixedSize(horizontal: true, vertical: false)
      }
      .frame(maxWidth: 640)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .workspaceInteractiveSurface(cornerRadius: 22, tint: tint, raised: false)
  }
}

struct WorkspaceMetricTile: View {
  let title: String
  let value: String
  let detail: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        Circle()
          .fill(tint)
          .frame(width: 7, height: 7)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(WorkspacePalette.subtleText)
      }

      Text(value)
        .font(.system(size: 26, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      Text(detail)
        .font(.caption)
        .foregroundStyle(Color.white.opacity(0.60))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 118, maxHeight: .infinity, alignment: .leading)
    .workspaceInteractiveSurface(cornerRadius: 20, tint: tint, raised: false)
  }
}

struct WorkspaceEmptyState: View {
  let title: String
  let message: String
  let tint: Color
  let systemImage: String

  init(title: String, message: String, tint: Color = .teal, systemImage: String = "sparkles") {
    self.title = title
    self.message = message
    self.tint = tint
    self.systemImage = systemImage
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label {
        Text(title)
          .font(.subheadline.weight(.semibold))
      } icon: {
        Image(systemName: systemImage)
      }
      .foregroundStyle(WorkspacePalette.primaryText)

      Text(message)
        .font(.caption)
        .foregroundStyle(WorkspacePalette.subtleText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .frame(minHeight: 96, alignment: .topLeading)
    .workspaceInteractiveSurface(cornerRadius: 20, tint: tint, raised: false)
  }
}

struct WorkspaceBadge: View {
  let text: String
  let tint: Color

  var body: some View {
    Text(text)
      .font(.caption.weight(.bold))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    .background(
      Capsule(style: .continuous)
          .fill(tint.opacity(0.14))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(Color.white.opacity(0.06), lineWidth: 1)
      )
      .foregroundStyle(tint)
  }
}

struct FooterMessageHost: View {
  let message: String?

  var body: some View {
    Group {
      if let message, !message.isEmpty {
        Text(message)
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.84))
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(WorkspacePalette.panelBase.opacity(0.94))
          .overlay(
            Rectangle()
              .fill(Color.white.opacity(0.08))
              .frame(height: 1),
            alignment: .top
          )
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.20), value: message)
  }
}

struct WorkspaceSidebarHeader: View {
  let title: String
  let subtitle: String
  let primaryBadge: String
  let primaryTint: Color
  let secondaryBadge: String
  let secondaryTint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.title3.weight(.bold))
          .foregroundStyle(WorkspacePalette.primaryText)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(WorkspacePalette.subtleText)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 8) {
        WorkspaceBadge(text: primaryBadge, tint: primaryTint)
        WorkspaceBadge(text: secondaryBadge, tint: secondaryTint)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .workspaceInteractiveSurface(cornerRadius: 24, tint: primaryTint, raised: false)
  }
}

private struct WorkspaceInteractiveSurfaceModifier: ViewModifier {
  let cornerRadius: CGFloat
  let tint: Color
  let raised: Bool

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

#if os(macOS)
    content
      .background(
        shape
          .fill(raised ? WorkspacePalette.panelRaised : WorkspacePalette.panelBase)
      )
      .overlay(
        shape
          .stroke(
            Color.white.opacity(raised ? 0.12 : 0.08),
            lineWidth: 1
          )
      )
      .overlay(alignment: .topLeading) {
        Capsule(style: .continuous)
          .fill(tint.opacity(0.75))
          .frame(width: 64, height: 3)
          .padding(.top, 12)
          .padding(.leading, 14)
      }
      .shadow(color: .black.opacity(raised ? 0.18 : 0.10), radius: raised ? 16 : 8, x: 0, y: raised ? 10 : 4)
#else
    content
      .background(
        shape
          .fill(
            LinearGradient(
              colors: [
                raised ? WorkspacePalette.panelRaised : WorkspacePalette.innerCard,
                WorkspacePalette.panelBase,
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .overlay(
            shape
              .fill(.ultraThinMaterial)
              .opacity(0.16)
          )
      )
      .overlay(
        shape
          .stroke(
            LinearGradient(
              colors: [
                Color.white.opacity(0.18),
                tint.opacity(0.22),
                Color.white.opacity(0.04),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1
          )
      )
      .overlay(alignment: .topLeading) {
        Capsule(style: .continuous)
          .fill(
            LinearGradient(
              colors: [tint.opacity(0.9), tint.opacity(0.12)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: 82, height: 4)
          .padding(.top, 14)
          .padding(.leading, 16)
      }
      .shadow(color: .black.opacity(raised ? 0.28 : 0.14), radius: raised ? 28 : 14, x: 0, y: raised ? 18 : 10)
#endif
  }
}

extension View {
  func workspaceInteractiveSurface(
    cornerRadius: CGFloat = 30,
    tint: Color = .teal,
    raised: Bool = true
  ) -> some View {
    modifier(WorkspaceInteractiveSurfaceModifier(cornerRadius: cornerRadius, tint: tint, raised: raised))
  }

  func workspaceAlignedCard(minHeight: CGFloat = 0) -> some View {
    frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
  }
}
