import SwiftUI

struct StagesView: View {
  @EnvironmentObject private var appRouter: AppRouter
  @EnvironmentObject private var stageStore: StageStore
  @EnvironmentObject private var stagesViewModel: StagesViewModel
  @State private var searchText: String = ""
  @State private var debouncedSearchText: String = ""
  @State private var searchDebounceTask: Task<Void, Never>?

  var body: some View {
#if os(macOS)
    NavigationStack {
      GeometryReader { proxy in
        let metrics = WorkspaceLayoutMetrics(width: proxy.size.width)
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
          overviewPanel(metrics: metrics)
          commandBar
          listAndDetailBoard(width: proxy.size.width)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.regularPanelPadding)
        .padding(.bottom, metrics.panelGap)
        .frame(maxWidth: metrics.contentMaxWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
      .searchable(text: $searchText, placement: .automatic)
      .background(WorkspaceBackground().equatable())
      .navigationTitle("Stages")
      .safeAreaInset(edge: .bottom) {
        FooterMessageHost(message: stageStore.syncMessage.isEmpty ? nil : stageStore.syncMessage)
      }
    }
    .onAppear {
      stagesViewModel.reload(resetPagination: true)
      if debouncedSearchText != searchText {
        debouncedSearchText = searchText
      }
    }
    .onChange(of: searchText) { value in
      searchDebounceTask?.cancel()
      searchDebounceTask = Task {
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
          debouncedSearchText = value
          stagesViewModel.updateSearchQuery(value)
        }
      }
    }
    .instrumentedScreen("StagesView")
#else
    NavigationStack {
      GeometryReader { proxy in
        let metrics = WorkspaceLayoutMetrics(width: proxy.size.width)
        ScrollView {
          VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            overviewPanel(metrics: metrics)
            commandBar
            listAndDetailBoard(width: proxy.size.width)
          }
          .padding(.horizontal, metrics.horizontalPadding)
          .padding(.vertical, metrics.regularPanelPadding)
          .frame(maxWidth: metrics.contentMaxWidth)
          .frame(maxWidth: .infinity, alignment: .top)
        }
      }
      .searchable(text: $searchText, placement: .automatic)
      .background(WorkspaceBackground().equatable())
      .navigationTitle("Stages")
      .safeAreaInset(edge: .bottom) {
        FooterMessageHost(message: stageStore.syncMessage.isEmpty ? nil : stageStore.syncMessage)
      }
    }
    .onAppear {
      stagesViewModel.reload(resetPagination: true)
      if debouncedSearchText != searchText {
        debouncedSearchText = searchText
      }
    }
    .onChange(of: searchText) { value in
      searchDebounceTask?.cancel()
      searchDebounceTask = Task {
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
          debouncedSearchText = value
          stagesViewModel.updateSearchQuery(value)
        }
      }
    }
    .instrumentedScreen("StagesView")
#endif
  }

  private func overviewPanel(metrics: WorkspaceLayoutMetrics) -> some View {
    WorkspaceHeroPanel(tint: WorkspacePalette.accentSoft, padding: metrics.regularPanelPadding) {
      VStack(alignment: .leading, spacing: metrics.panelGap) {
        HStack(alignment: .top, spacing: metrics.panelGap) {
          VStack(alignment: .leading, spacing: 10) {
            Text("PIPELINE CONTROL")
              .font(.caption2.weight(.bold))
              .tracking(1.8)
              .foregroundStyle(Color.white.opacity(0.70))

            Text("Decision-ready funnel.\nFast to scan.")
              .font(.system(size: metrics.sizeClass == .wide ? 38 : 33, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)

            Text("Track every opportunity with a tighter visual index, stronger state contrast, and an inspection panel built for quick triage.")
              .font(.subheadline)
              .foregroundStyle(Color.white.opacity(0.72))
          }

          Spacer(minLength: 0)

          VStack(alignment: .trailing, spacing: 10) {
            WorkspaceBadge(text: debouncedSearchText.isEmpty ? "All stages" : "Filtered", tint: WorkspacePalette.accent)
            WorkspaceBadge(text: "\(stagesViewModel.listState.totalCount) total", tint: WorkspacePalette.warning)
          }
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
          WorkspaceMetricTile(title: "Loaded", value: "\(stagesViewModel.listState.items.count)", detail: "rows on screen", tint: WorkspacePalette.accentSoft)
          WorkspaceMetricTile(title: "Matching", value: "\(stagesViewModel.listState.totalCount)", detail: "matching records", tint: WorkspacePalette.accent)
          WorkspaceMetricTile(title: "Queue", value: "\(stagesViewModel.listState.pendingQueueCount)", detail: "pending sync ops", tint: WorkspacePalette.warning)
          WorkspaceMetricTile(title: "Status", value: stagesViewModel.listState.hasMore ? "Paged" : "Ready", detail: stagesViewModel.listState.hasMore ? "more records available" : "full page loaded", tint: WorkspacePalette.success)
        }
      }
    }
  }

  @ViewBuilder
  private func listAndDetailBoard(width: CGFloat) -> some View {
    let metrics = WorkspaceLayoutMetrics(width: width)
#if os(macOS)
    if metrics.sizeClass == .wide {
      HStack(alignment: .top, spacing: metrics.panelGap) {
        listPanel
          .frame(minWidth: 360, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity, alignment: .top)
        detailPanel
          .frame(minWidth: 360, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity, alignment: .top)
      }
      .frame(maxWidth: .infinity, minHeight: 640, maxHeight: .infinity, alignment: .top)
    } else {
      VStack(alignment: .leading, spacing: 24) {
        listPanel
        detailPanel
      }
    }
#else
    VStack(alignment: .leading, spacing: 24) {
      listPanel
      detailPanel
    }
#endif
  }
  
  private var commandBar: some View {
    WorkspaceCommandBar(
      title: "Command lane",
      subtitle: "Search, sync, and review the funnel without losing selection context."
    ) {
      Button {
        Task { await stageStore.syncFromNotion() }
      } label: {
        Label(stageStore.isSyncingNotion ? "Syncing..." : "Sync", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.borderedProminent)
      .tint(WorkspacePalette.accent)

      WorkspaceBadge(text: "\(stagesViewModel.listState.items.count) loaded", tint: WorkspacePalette.accentSoft)
      WorkspaceBadge(text: stagesViewModel.listState.hasMore ? "More pages" : "Fully loaded", tint: .white)
    }
  }

  private var listPanel: some View {
    WorkspacePanel(
      title: "Pipeline index",
      subtitle: "A fast moving list of active opportunities and their latest state.",
      tint: WorkspacePalette.accent
    ) {
      if stagesViewModel.listState.items.isEmpty {
        WorkspaceEmptyState(
          title: "No stage found",
          message: debouncedSearchText.isEmpty ? "No stage is available in the local pipeline." : "No stage matches the current search.",
          tint: WorkspacePalette.accent,
          systemImage: "tray"
        )
      } else {
        stageListContent
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var stageListContent: some View {
#if os(macOS)
    List(stagesViewModel.listState.items) { item in
      stageListButton(for: item)
        .listRowInsets(EdgeInsets(top: 6, leading: 2, bottom: 6, trailing: 2))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .frame(minHeight: 520)
#else
    LazyVStack(spacing: 10) {
      ForEach(stagesViewModel.listState.items) { item in
        stageListButton(for: item)
      }
    }
#endif
  }

  private func stageListButton(for item: StagesReadModel) -> some View {
    Button {
      if let url = WidgetDeepLink.stage(item.id) {
        appRouter.handle(url: url)
      }
      stagesViewModel.selectStage(id: item.id)
    } label: {
      StageListRowView(
        item: item,
        isSelected: stagesViewModel.selectedStageDetail?.stage.id == item.id
      )
      .equatable()
    }
    .buttonStyle(.plain)
    .onAppear {
      stagesViewModel.loadMoreIfNeeded(currentItemID: item.id)
    }
  }

  private var detailPanel: some View {
    WorkspacePanel(
      title: "Opportunity brief",
      subtitle: "The selected record expands here with movement, notes, and linked follow-ups.",
      tint: WorkspacePalette.warning
    ) {
      if let detail = stagesViewModel.selectedStageDetail {
        StageDetailPanel(
          detail: detail,
          onStatusChange: { newStatus in
            Task { await stageStore.updateStageStatus(stageID: detail.stage.id, to: newStatus) }
          },
          onDelete: {
            stageStore.deleteStage(stageID: detail.stage.id)
            stagesViewModel.reload(resetPagination: true)
          }
        )
      } else {
        WorkspaceEmptyState(
          title: "No stage selected",
          message: "Select a row in the list to inspect the full record without rebuilding the whole screen.",
          tint: WorkspacePalette.warning,
          systemImage: "sidebar.right"
        )
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }
}
