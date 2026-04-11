import SwiftUI

enum WorkspacePalette {
  static let backgroundTop = Color(red: 0.04, green: 0.06, blue: 0.11)
  static let backgroundBottom = Color(red: 0.08, green: 0.10, blue: 0.16)
  static let panelBase = Color(red: 0.08, green: 0.10, blue: 0.15).opacity(0.96)
  static let panelRaised = Color(red: 0.11, green: 0.13, blue: 0.20).opacity(0.98)
  static let innerCard = Color.white.opacity(0.07)
  static let line = Color.white.opacity(0.10)
  static let subtleText = Color.white.opacity(0.66)
  static let primaryText = Color.white
}

struct WorkspaceBackground: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          WorkspacePalette.backgroundTop,
          WorkspacePalette.backgroundBottom,
          Color(red: 0.11, green: 0.13, blue: 0.19),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      RadialGradient(
        colors: [Color.teal.opacity(0.22), .clear],
        center: .topLeading,
        startRadius: 30,
        endRadius: 420
      )
      .offset(x: -140, y: -120)

      RadialGradient(
        colors: [Color.orange.opacity(0.18), .clear],
        center: .topTrailing,
        startRadius: 30,
        endRadius: 420
      )
      .offset(x: 140, y: -180)

      RadialGradient(
        colors: [Color.white.opacity(0.06), .clear],
        center: .bottomTrailing,
        startRadius: 20,
        endRadius: 500
      )
      .offset(x: 180, y: 220)

      WorkspaceGridPattern()
        .blendMode(.softLight)
        .opacity(0.22)
    }
  }
}

private struct WorkspaceGridPattern: View {
  var body: some View {
    GeometryReader { proxy in
      Path { path in
        let width = proxy.size.width
        let height = proxy.size.height
        stride(from: 0.0, through: width, by: 36.0).forEach { x in
          path.move(to: CGPoint(x: x, y: 0))
          path.addLine(to: CGPoint(x: x, y: height))
        }
        stride(from: 0.0, through: height, by: 36.0).forEach { y in
          path.move(to: CGPoint(x: 0, y: y))
          path.addLine(to: CGPoint(x: width, y: y))
        }
      }
      .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
    }
    .ignoresSafeArea()
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
            .font(.title3.weight(.bold))
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
          .tracking(2.0)
          .foregroundStyle(WorkspacePalette.subtleText)
        Text(subtitle)
          .font(.subheadline.weight(.semibold))
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
          .frame(width: 8, height: 8)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(WorkspacePalette.subtleText)
      }

      Text(value)
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      Text(detail)
        .font(.caption)
        .foregroundStyle(Color.white.opacity(0.60))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
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
          .fill(tint.opacity(0.16))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      )
      .foregroundStyle(tint)
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

#if os(macOS)
  @State private var isHovered = false
#endif

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

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
#if os(macOS)
      .scaleEffect(isHovered ? 1.008 : 1.0)
      .brightness(isHovered ? 0.01 : 0.0)
      .animation(.snappy(duration: 0.22), value: isHovered)
      .onHover { hovering in
        isHovered = hovering
      }
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
}
