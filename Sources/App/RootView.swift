import SwiftUI

struct RootView: View {
  @EnvironmentObject private var appRouter: AppRouter
  @EnvironmentObject private var updateStore: UpdateStore
  @EnvironmentObject private var stageStore: StageStore

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
      _ = await (updateCheck, notionBootstrap)
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
    List(selection: Binding(
      get: { appRouter.destination },
      set: { appRouter.select($0) }
    )) {
      Section {
        WorkspaceSidebarHeader(
          title: "NotionDashboard",
          subtitle: "A cleaner workspace focused on today, pipeline visibility, and calendar execution.",
          primaryBadge: updateStore.availableUpdate == nil ? "Current" : "Update ready",
          primaryTint: updateStore.availableUpdate == nil ? WorkspacePalette.success : WorkspacePalette.accent,
          secondaryBadge: stageStore.pendingQueueCount == 0 ? "Queue clear" : "\(stageStore.pendingQueueCount) queued",
          secondaryTint: stageStore.pendingQueueCount == 0 ? WorkspacePalette.accentSoft : WorkspacePalette.warning
        )
        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 14, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
      }

      Section {
        ForEach(RootDestination.allCases) { destination in
          sidebarRow(for: destination)
            .tag(destination)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }
    }
    .navigationTitle("Workspace")
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .background(WorkspaceBackground().equatable())
  }

  private func sidebarRow(for destination: RootDestination) -> some View {
    let isSelected = appRouter.destination == destination

    return HStack(spacing: 12) {
      Image(systemName: destination.systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isSelected ? WorkspacePalette.accentSoft : Color.white.opacity(0.72))
        .frame(width: 18)

      Text(destination.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.80))

      Spacer(minLength: 8)

      if destination == .settings, updateStore.availableUpdate != nil {
        Circle()
          .fill(WorkspacePalette.accent)
          .frame(width: 8, height: 8)
      } else if destination == .stages, stageStore.pendingQueueCount > 0 {
        Text("\(stageStore.pendingQueueCount)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(isSelected ? .white : WorkspacePalette.warning)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(isSelected ? WorkspacePalette.panelRaised : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(isSelected ? WorkspacePalette.accent.opacity(0.22) : Color.clear, lineWidth: 1)
    )
  }
#endif
}
