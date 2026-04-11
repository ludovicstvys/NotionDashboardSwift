import SwiftUI

private enum RootDestination: String, CaseIterable, Identifiable {
  case home
  case stages
  case calendar
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home:
      return "Home"
    case .stages:
      return "Stages"
    case .calendar:
      return "Calendar"
    case .settings:
      return "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .home:
      return "rectangle.grid.2x2.fill"
    case .stages:
      return "square.grid.2x2.fill"
    case .calendar:
      return "calendar"
    case .settings:
      return "gearshape.fill"
    }
  }
}

struct RootView: View {
  @EnvironmentObject private var updateStore: UpdateStore
  @EnvironmentObject private var stageStore: StageStore
#if os(macOS)
  @State private var selection: RootDestination = .home
#endif

  var body: some View {
    Group {
#if os(macOS)
      NavigationSplitView {
        sidebar
      } detail: {
        detailView(for: selection)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .tint(.teal)
#else
      TabView {
        DashboardView()
          .tabItem {
            Label("Home", systemImage: "rectangle.grid.2x2.fill")
          }

        StagesView()
          .tabItem {
            Label("Stages", systemImage: "square.grid.2x2.fill")
          }

        CalendarView()
          .tabItem {
            Label("Calendar", systemImage: "calendar")
          }

        SettingsView()
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

  @ViewBuilder
  private func detailView(for destination: RootDestination) -> some View {
    switch destination {
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

#if os(macOS)
  private var sidebar: some View {
    List(selection: $selection) {
      Section {
        WorkspaceSidebarHeader(
          title: "Dashboard",
          subtitle: "A calmer shell with content-first navigation and live system state.",
          primaryBadge: updateStore.availableUpdate == nil ? "Up to date" : "Update ready",
          primaryTint: updateStore.availableUpdate == nil ? .green : .teal,
          secondaryBadge: stageStore.pendingQueueCount == 0 ? "Queue clear" : "\(stageStore.pendingQueueCount) queued",
          secondaryTint: stageStore.pendingQueueCount == 0 ? .blue : .orange
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
    .navigationTitle("Dashboard")
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .background(WorkspaceBackground())
  }

  private func sidebarRow(for destination: RootDestination) -> some View {
    let isSelected = selection == destination

    return HStack(spacing: 12) {
      Image(systemName: destination.systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
        .frame(width: 18)

      Text(destination.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.80))

      Spacer(minLength: 8)

      if destination == .settings, updateStore.availableUpdate != nil {
        Circle()
          .fill(Color.teal)
          .frame(width: 8, height: 8)
      } else if destination == .stages, stageStore.pendingQueueCount > 0 {
        Text("\(stageStore.pendingQueueCount)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(isSelected ? .white : .orange)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(isSelected ? WorkspacePalette.innerCard : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(isSelected ? Color.white.opacity(0.10) : Color.clear, lineWidth: 1)
    )
  }
#endif
}
