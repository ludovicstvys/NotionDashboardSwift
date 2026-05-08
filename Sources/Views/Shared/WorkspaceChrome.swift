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
  static let backgroundTop = Color(red: 0.020, green: 0.028, blue: 0.042)
  static let backgroundBottom = Color(red: 0.048, green: 0.060, blue: 0.084)
  static let panelBase = Color(red: 0.062, green: 0.076, blue: 0.108).opacity(0.988)
  static let panelRaised = Color(red: 0.090, green: 0.110, blue: 0.146).opacity(0.994)
  static let innerCard = Color.white.opacity(0.048)
  static let innerCardStrong = Color.white.opacity(0.078)
  static let line = Color.white.opacity(0.082)
  static let lineStrong = Color.white.opacity(0.16)
  static let subtleText = Color.white.opacity(0.64)
  static let secondaryText = Color.white.opacity(0.80)
  static let primaryText = Color.white
  static let accent = Color(red: 0.961, green: 0.620, blue: 0.153)
  static let accentSoft = Color(red: 0.386, green: 0.780, blue: 0.965)
  static let success = Color(red: 0.373, green: 0.824, blue: 0.600)
  static let warning = Color(red: 0.639, green: 0.541, blue: 0.957)
  static let danger = Color(red: 0.93, green: 0.41, blue: 0.38)
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
          Color(red: 0.062, green: 0.074, blue: 0.098),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      RadialGradient(
        colors: [WorkspacePalette.accent.opacity(0.18), .clear],
        center: .topLeading,
        startRadius: 30,
        endRadius: 560
      )
      .offset(x: -140, y: -120)

      RadialGradient(
        colors: [Color.white.opacity(0.055), .clear],
        center: .top,
        startRadius: 30,
        endRadius: 420
      )
      .offset(x: 0, y: -220)

      RadialGradient(
        colors: [WorkspacePalette.warning.opacity(0.11), .clear],
        center: .trailing,
        startRadius: 24,
        endRadius: 380
      )
      .offset(x: 60, y: 40)

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
          Color.white.opacity(0.018),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .blendMode(.softLight)
      .opacity(0.24)
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
              .font(.system(size: 20, weight: .semibold, design: .rounded))
              .foregroundStyle(WorkspacePalette.primaryText)
            if let subtitle {
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(WorkspacePalette.subtleText)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          Spacer(minLength: 0)

          RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(
              LinearGradient(
                colors: [tint.opacity(0.95), tint.opacity(0.28)],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(width: 26, height: 6)
            .shadow(color: tint.opacity(0.34), radius: 10, x: 0, y: 0)
            .padding(.top, 7)
        }

        Rectangle()
          .fill(WorkspacePalette.line.opacity(0.72))
          .frame(height: 1)
          .padding(.top, 2)
      }

      content
    }
    .padding(padding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .workspaceInteractiveSurface(cornerRadius: 24, tint: tint)
    .workspaceReveal()
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
          .frame(width: 240, height: 240)
          .blur(radius: 34)
          .offset(x: 74, y: -100)
      }
      .overlay(alignment: .bottomLeading) {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color.white.opacity(0.12), .clear],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: 180, height: 2)
          .padding(.leading, 2)
          .padding(.bottom, 2)
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
      .workspaceReveal(distance: 20)
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
        .tracking(1.4)
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
    .background(WorkspacePalette.innerCardStrong)
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
          .tracking(1.6)
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
    .overlay(alignment: .topTrailing) {
      Circle()
        .fill(tint.opacity(0.16))
        .frame(width: 76, height: 76)
        .blur(radius: 18)
        .offset(x: 22, y: -18)
    }
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
        Capsule(style: .continuous)
          .fill(tint.opacity(0.9))
          .frame(width: 18, height: 5)
      }

      Text(value)
        .font(.system(size: 30, weight: .semibold, design: .rounded))
        .foregroundStyle(WorkspacePalette.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      Text(detail)
        .font(.caption)
        .foregroundStyle(Color.white.opacity(0.58))
        .lineSpacing(1)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 122, maxHeight: .infinity, alignment: .leading)
    .background(
      LinearGradient(
        colors: [
          Color.white.opacity(0.092),
          tint.opacity(0.13),
          WorkspacePalette.innerCard,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(WorkspacePalette.line, lineWidth: 1)
    }
    .overlay(alignment: .bottomTrailing) {
      Circle()
        .fill(tint.opacity(0.12))
        .frame(width: 54, height: 54)
        .blur(radius: 8)
        .offset(x: 10, y: 10)
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
        .lineSpacing(1)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .frame(minHeight: 96, alignment: .topLeading)
    .background(WorkspacePalette.innerCardStrong)
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
          .fill(
            LinearGradient(
              colors: [tint.opacity(0.22), Color.white.opacity(0.08)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(tint.opacity(0.26), lineWidth: 1)
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
    .animation(.snappy(duration: 0.22), value: message)
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
          .fill(
            LinearGradient(
              colors: [
                raised ? WorkspacePalette.panelRaised : WorkspacePalette.innerCardStrong,
                WorkspacePalette.panelBase,
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
      .overlay(
        shape
          .stroke(
            Color.white.opacity(raised ? 0.12 : 0.085),
            lineWidth: 1
          )
      )
      .overlay(alignment: .topLeading) {
        Capsule(style: .continuous)
          .fill(
            LinearGradient(
              colors: [tint.opacity(0.95), tint.opacity(0.10)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: 92, height: 3)
          .padding(.top, 14)
          .padding(.leading, 16)
      }
      .shadow(color: .black.opacity(raised ? 0.22 : 0.10), radius: raised ? 20 : 8, x: 0, y: raised ? 12 : 5)
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

private struct WorkspaceRevealModifier: ViewModifier {
  let distance: CGFloat
  @State private var isVisible = false

  func body(content: Content) -> some View {
    content
      .opacity(isVisible ? 1 : 0.01)
      .offset(y: isVisible ? 0 : distance)
      .scaleEffect(isVisible ? 1 : 0.985, anchor: .top)
      .animation(.snappy(duration: 0.34), value: isVisible)
      .onAppear {
        guard !isVisible else { return }
        isVisible = true
      }
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

  func workspaceReveal(distance: CGFloat = 14) -> some View {
    modifier(WorkspaceRevealModifier(distance: distance))
  }
}
