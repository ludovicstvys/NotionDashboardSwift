import SwiftUI

struct RootView: View {
  @EnvironmentObject private var appRouter: AppRouter
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var updateStore: UpdateStore
  @EnvironmentObject private var stageStore: StageStore
  @EnvironmentObject private var calendarStore: CalendarStore

  var body: some View {
    Group {
#if os(macOS)
      NavigationSplitView {
        sidebar
      } detail: {
        detailContainer
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .tint(.teal)
#else
      TabView(selection: Binding(
        get: { appRouter.destination },
        set: { appRouter.select($0) }
      )) {
        DashboardView()
          .tag(RootDestination.home)
          .tabItem {
            Label("Home", systemImage: "rectangle.grid.2x2.fill")
          }

        StagesView()
          .tag(RootDestination.stages)
          .tabItem {
            Label("Stages", systemImage: "square.grid.2x2.fill")
          }

        CalendarView()
          .tag(RootDestination.calendar)
          .tabItem {
            Label("Calendar", systemImage: "calendar")
          }

        SettingsView()
          .tag(RootDestination.settings)
          .tabItem {
            Label("Settings", systemImage: "gearshape.fill")
          }
      }
      .tint(.teal)
#endif
    }
    .task(priority: .background) {
      async let updateCheck: Void = updateStore.performLaunchCheckIfNeeded()
      async let notionBootstrap: Void = stageStore.prepareForLaunch()
      async let calendarBootstrap: Void = calendarStore.prepareForLaunch(icalURL: configStore.config.externalIcalUrl)
      _ = await (updateCheck, notionBootstrap, calendarBootstrap)
    }
  }

  private var detailContainer: some View {
    Group {
      switch appRouter.destination {
      case .home:
        DashboardView()
      case .stages:
        StagesView()
      case .calendar:
        CalendarView()
      case .settings:
        SettingsView()
      }
    }
  }

#if os(macOS)
  private var sidebar: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          brandBlock
          navigationBlock
          statusBlock
        }
        .padding(18)
      }

      sidebarFooter
        .padding(16)
    }
    .frame(minWidth: 250, idealWidth: 290, maxWidth: 340)
    .background {
      ZStack {
        WorkspaceBackground().equatable()
        Color.black.opacity(0.18)
      }
    }
  }

  private var brandBlock: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .center, spacing: 12) {
        Image("DashboardLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 42, height: 42)
          .padding(6)
          .background(WorkspacePalette.innerCard)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(WorkspacePalette.line, lineWidth: 1)
          }

        VStack(alignment: .leading, spacing: 3) {
          Text("NotionDashboard")
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
          Text("Student workspace")
            .font(.caption.weight(.semibold))
            .foregroundStyle(WorkspacePalette.subtleText)
        }
      }

    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(WorkspacePalette.panelRaised.opacity(0.86))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(WorkspacePalette.line, lineWidth: 1)
    }
  }

  private var navigationBlock: some View {
    VStack(alignment: .leading, spacing: 10) {
      sidebarSectionTitle("Navigate")
      VStack(spacing: 8) {
        ForEach(RootDestination.allCases) { destination in
          sidebarButton(for: destination)
        }
      }
    }
  }

  private var statusBlock: some View {
    VStack(alignment: .leading, spacing: 10) {
      sidebarSectionTitle("Signals")
      VStack(spacing: 8) {
        sidebarSignalRow(
          title: "Sync queue",
          value: stageStore.pendingQueueCount == 0 ? "Clear" : "\(stageStore.pendingQueueCount)",
          systemImage: "arrow.triangle.2.circlepath",
          tint: stageStore.pendingQueueCount == 0 ? WorkspacePalette.success : WorkspacePalette.warning
        )
        sidebarSignalRow(
          title: "Version",
          value: updateStore.availableUpdate == nil ? updateStore.currentVersion : "Update",
          systemImage: "sparkles",
          tint: updateStore.availableUpdate == nil ? WorkspacePalette.accentSoft : WorkspacePalette.accent
        )
      }
    }
  }

  private var sidebarFooter: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(WorkspacePalette.success)
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 2) {
        Text("Local workspace")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.82))
        Text("Data stays on this Mac")
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.50))
      }
      Spacer()
    }
    .padding(12)
    .background(WorkspacePalette.innerCard.opacity(0.70))
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private func sidebarButton(for destination: RootDestination) -> some View {
    let isSelected = appRouter.destination == destination
    return Button {
      appRouter.select(destination)
    } label: {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isSelected ? destination.tint.opacity(0.18) : WorkspacePalette.innerCard)
          Image(systemName: destination.systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isSelected ? destination.tint : Color.white.opacity(0.68))
        }
        .frame(width: 38, height: 38)

        VStack(alignment: .leading, spacing: 2) {
          Text(destination.title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.82))
          Text(destination.sidebarSubtitle)
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(isSelected ? 0.58 : 0.42))
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        sidebarAccessory(for: destination, isSelected: isSelected)
      }
      .padding(11)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(isSelected ? WorkspacePalette.panelRaised.opacity(0.96) : Color.white.opacity(0.001))
      )
      .overlay(alignment: .leading) {
        if isSelected {
          RoundedRectangle(cornerRadius: 2)
            .fill(destination.tint)
            .frame(width: 3, height: 32)
            .padding(.leading, 2)
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(isSelected ? destination.tint.opacity(0.26) : Color.clear, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func sidebarAccessory(for destination: RootDestination, isSelected: Bool) -> some View {
    if destination == .settings, updateStore.availableUpdate != nil {
      Text("New")
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WorkspacePalette.accent.opacity(0.28))
        .clipShape(Capsule())
    } else if destination == .stages, stageStore.pendingQueueCount > 0 {
      Text("\(stageStore.pendingQueueCount)")
        .font(.caption2.weight(.bold))
        .foregroundStyle(isSelected ? .white : WorkspacePalette.warning)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WorkspacePalette.warning.opacity(0.16))
        .clipShape(Capsule())
    } else {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(isSelected ? WorkspacePalette.success : Color.white.opacity(0.28))
    }
  }

  private func sidebarSectionTitle(_ title: String) -> some View {
    Text(title.uppercased())
      .font(.caption2.weight(.bold))
      .tracking(1.6)
      .foregroundStyle(Color.white.opacity(0.42))
      .padding(.horizontal, 6)
  }

  private func sidebarSignalRow(title: String, value: String, systemImage: String, tint: Color) -> some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.caption.weight(.bold))
        .foregroundStyle(tint)
        .frame(width: 22)
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.72))
      Spacer()
      Text(value)
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.16))
        .clipShape(Capsule())
    }
    .padding(12)
    .background(WorkspacePalette.innerCard)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(WorkspacePalette.line, lineWidth: 1)
    }
  }

#endif
}

private extension RootDestination {
  var sidebarSubtitle: String {
    switch self {
    case .home:
      return "Today, todos, signals"
    case .stages:
      return "Applications pipeline"
    case .calendar:
      return "Day schedule"
    case .settings:
      return "Connections and sync"
    }
  }

  var tint: Color {
    switch self {
    case .home:
      return WorkspacePalette.accent
    case .stages:
      return WorkspacePalette.accentSoft
    case .calendar:
      return WorkspacePalette.warning
    case .settings:
      return WorkspacePalette.success
    }
  }
}
