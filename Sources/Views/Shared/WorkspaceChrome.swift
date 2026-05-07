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
  static let backgroundTop = Color(red: 0.035, green: 0.043, blue: 0.055)
  static let backgroundBottom = Color(red: 0.055, green: 0.067, blue: 0.085)
  static let panelBase = Color(red: 0.082, green: 0.098, blue: 0.123).opacity(0.985)
  static let panelRaised = Color(red: 0.112, green: 0.130, blue: 0.160).opacity(0.99)
  static let innerCard = Color.white.opacity(0.060)
  static let line = Color.white.opacity(0.095)
  static let subtleText = Color.white.opacity(0.66)
  static let secondaryText = Color.white.opacity(0.78)
  static let primaryText = Color.white
  static let accent = Color(red: 0.17, green: 0.64, blue: 0.92)
  static let accentSoft = Color(red: 0.36, green: 0.82, blue: 0.72)
  static let success = Color(red: 0.35, green: 0.78, blue: 0.46)
  static let warning = Color(red: 0.96, green: 0.67, blue: 0.25)
  static let danger = Color(red: 0.95, green: 0.35, blue: 0.35)
}

enum WorkspaceColor {
  static func hex(_ value: String?) -> Color? {
    guard let value else { return nil }
    let clean = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard clean.count == 6 else { return nil }
    var rgb: UInt64 = 0
    guard Scanner(string: clean).scanHexInt64(&rgb) else { return nil }
    return Color(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255
    )
  }
}

struct WorkspaceBackground: View, Equatable {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          WorkspacePalette.backgroundTop,
          WorkspacePalette.backgroundBottom,
          Color(red: 0.070, green: 0.078, blue: 0.100),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      RadialGradient(
        colors: [WorkspacePalette.accent.opacity(0.13), .clear],
        center: .topLeading,
        startRadius: 30,
        endRadius: 520
      )
      .offset(x: -140, y: -120)

      RadialGradient(
        colors: [Color.white.opacity(0.045), .clear],
        center: .top,
        startRadius: 30,
        endRadius: 360
      )
      .offset(x: 0, y: -220)

      RadialGradient(
        colors: [WorkspacePalette.accentSoft.opacity(0.08), .clear],
        center: .bottomTrailing,
        startRadius: 20,
        endRadius: 500
      )
      .offset(x: 180, y: 220)

      LinearGradient(
        colors: [
          Color.white.opacity(0.035),
          .clear,
          Color.white.opacity(0.02),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .blendMode(.softLight)
      .opacity(0.22)
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
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            Text(title)
              .font(.headline.weight(.semibold))
              .foregroundStyle(WorkspacePalette.primaryText)
            if let subtitle {
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(WorkspacePalette.subtleText)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          Spacer(minLength: 0)

          Circle()
            .fill(tint)
            .frame(width: 9, height: 9)
            .shadow(color: tint.opacity(0.38), radius: 8, x: 0, y: 0)
            .padding(.top, 5)
        }

        Rectangle()
          .fill(WorkspacePalette.line)
          .frame(height: 1)
          .padding(.top, 2)
      }

      content
    }
    .padding(padding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .workspaceInteractiveSurface(cornerRadius: 24, tint: tint)
  }
}

struct WorkspaceHeroPanel<Content: View>: View {
  let tint: Color
  let padding: CGFloat
  let content: Content

  init(
    tint: Color = .teal,
    padding: CGFloat = 28,
    @ViewBuilder content: () -> Content
  ) {
    self.tint = tint
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                WorkspacePalette.panelRaised,
                WorkspacePalette.panelBase,
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
      .overlay(alignment: .topTrailing) {
        Circle()
          .fill(tint.opacity(0.18))
          .frame(width: 220, height: 220)
          .blur(radius: 28)
          .offset(x: 68, y: -92)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .stroke(
            LinearGradient(
              colors: [Color.white.opacity(0.16), Color.white.opacity(0.045)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1
          )
      }
      .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 16)
  }
}

struct WorkspaceStatusPill: View {
  let title: String
  let value: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title.uppercased())
        .font(.caption2.weight(.bold))
        .tracking(1.2)
        .foregroundStyle(WorkspacePalette.subtleText)
      HStack(spacing: 7) {
        Circle()
          .fill(tint)
          .frame(width: 7, height: 7)
        Text(value)
          .font(.caption.weight(.bold))
          .foregroundStyle(WorkspacePalette.primaryText)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(WorkspacePalette.innerCard)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(WorkspacePalette.line, lineWidth: 1)
    }
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
    .workspaceInteractiveSurface(cornerRadius: 18, tint: tint, raised: false)
  }
}

struct WorkspaceMetricTile: View {
  let title: String
  let value: String
  let detail: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 8) {
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(WorkspacePalette.subtleText)
        Spacer(minLength: 0)
        Circle()
          .fill(tint)
          .frame(width: 8, height: 8)
      }

      Text(value)
        .font(.system(size: 28, weight: .semibold, design: .rounded))
        .foregroundStyle(WorkspacePalette.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      Text(detail)
        .font(.caption)
        .foregroundStyle(Color.white.opacity(0.60))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 122, maxHeight: .infinity, alignment: .leading)
    .background(WorkspacePalette.innerCard)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(alignment: .leading) {
      RoundedRectangle(cornerRadius: 2)
        .fill(tint)
        .frame(width: 3)
        .padding(.vertical, 18)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(WorkspacePalette.line, lineWidth: 1)
    }
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
    .background(WorkspacePalette.innerCard)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(WorkspacePalette.line, lineWidth: 1)
    }
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
          .fill(tint.opacity(0.13))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(tint.opacity(0.18), lineWidth: 1)
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
          .font(.caption.weight(.semibold))
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
            Color.white.opacity(raised ? 0.115 : 0.080),
            lineWidth: 1
          )
      )
      .shadow(color: .black.opacity(raised ? 0.18 : 0.08), radius: raised ? 18 : 7, x: 0, y: raised ? 10 : 4)
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
