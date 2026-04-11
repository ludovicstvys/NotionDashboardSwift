import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum StageDisplayMode: String, CaseIterable, Identifiable {
  case kanban = "Kanban"
  case list = "List"

  var id: String { rawValue }
}

struct StagesView: View {
  @EnvironmentObject private var stageStore: StageStore
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var diagnosticsStore: DiagnosticsStore
  @State private var displayMode: StageDisplayMode = .kanban
  @State private var searchText: String = ""
  @State private var showAddSheet: Bool = false
  @State private var showImportSheet: Bool = false
  @State private var importPrefillURL: String = ""
  @State private var autoPromptDone: Bool = false

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            overviewPanel(width: proxy.size.width)
            commandBar

            if displayMode == .kanban {
              kanbanBoard
            } else {
              listBoard
            }
          }
          .padding(.horizontal, horizontalPadding(for: proxy.size.width))
          .padding(.vertical, 28)
          .frame(maxWidth: 1_440)
          .frame(maxWidth: .infinity, alignment: .top)
        }
      }
      .searchable(text: $searchText, placement: .automatic)
      .background(WorkspaceBackground())
      .navigationTitle("Stages")
      .animation(.snappy(duration: 0.26), value: filteredStages.count)
      .animation(.snappy(duration: 0.26), value: displayMode)
      .sheet(isPresented: $showAddSheet) {
        AddStageSheet { draft in
          Task {
            await stageStore.addStage(draft: draft)
          }
        }
      }
      .sheet(isPresented: $showImportSheet) {
        PipelineImportSheet(initialURL: importPrefillURL) { preview in
          let draft = StageDraft(
            title: preview.title,
            company: preview.company,
            url: preview.url,
            location: preview.location,
            status: .open,
            deadline: preview.deadline,
            notes: preview.description,
            source: preview.source
          )
          Task {
            await stageStore.addStage(draft: draft)
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if !stageStore.syncMessage.isEmpty {
          Text(stageStore.syncMessage)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.84))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspacePalette.panelBase.opacity(0.94))
        }
      }
    }
    .onAppear {
      Task {
        guard configStore.config.pipelineAutoImportEnabled else { return }
        guard !autoPromptDone else { return }
        if let candidate = readClipboardURL(), PipelineImportService().canImport(urlString: candidate) {
          autoPromptDone = true
          importPrefillURL = candidate
          showImportSheet = true
          diagnosticsStore.log(
            category: "pipeline",
            message: "Auto pipeline prompt opened from clipboard.",
            metadata: ["url": candidate]
          )
        } else if let candidate = readClipboardURL() {
          diagnosticsStore.log(
            category: "pipeline",
            message: "Clipboard URL not supported for pipeline auto-import.",
            metadata: ["url": candidate]
          )
        }
      }
    }
  }

  private func overviewPanel(width: CGFloat) -> some View {
    WorkspacePanel(tint: .blue, padding: width >= 900 ? 28 : 22) {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 12) {
            Text("PIPELINE COMMAND")
              .font(.caption2.weight(.bold))
              .tracking(2.4)
              .foregroundStyle(Color.white.opacity(0.70))

            Text("Keep the board moving,\nnot just populated.")
              .font(.system(size: width >= 1_120 ? 44 : 36, weight: .bold, design: .serif))
              .foregroundStyle(.white)
              .fixedSize(horizontal: false, vertical: true)

            Text("Stages now use the same control-room language as Home: pressure, queue health, WIP, and the actions that unblock the board.")
              .font(.subheadline)
              .foregroundStyle(Color.white.opacity(0.72))
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)

          VStack(alignment: .trailing, spacing: 10) {
            WorkspaceBadge(text: displayMode.rawValue, tint: .orange)
            WorkspaceBadge(text: searchText.isEmpty ? "All stages" : "Filtered", tint: .teal)
          }
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
          stageMetric(title: "Total", value: "\(stageStore.stages.count)", detail: "current pipeline", tint: .blue)
          stageMetric(title: "Filtered", value: "\(filteredStages.count)", detail: searchText.isEmpty ? "visible now" : "matching search", tint: .teal)
          stageMetric(title: "Blockers", value: "\(stageStore.blockers.count)", detail: stageStore.blockers.isEmpty ? "no delay alert" : "needs follow-up", tint: .pink)
          stageMetric(title: "Queue", value: "\(stageStore.pendingQueueCount)", detail: "waiting before applied", tint: .orange)
        }
      }
    }
  }

  private var commandBar: some View {
    WorkspaceCommandBar(
      title: "Actions",
      subtitle: "Primary pipeline actions stay close to the board, not hidden in the chrome."
    ) {
      Button {
        showAddSheet = true
      } label: {
        Label("Add stage", systemImage: "plus.circle.fill")
      }
      .buttonStyle(.borderedProminent)
      .tint(.teal)

      Button {
        showImportSheet = true
      } label: {
        Label("Import URL", systemImage: "square.and.arrow.down")
      }
      .buttonStyle(.bordered)

      Button {
        Task { await stageStore.syncFromNotion() }
      } label: {
        Label(stageStore.isSyncingNotion ? "Syncing..." : "Sync Notion", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.bordered)

      Picker("Mode", selection: $displayMode) {
        ForEach(StageDisplayMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 180)

      WorkspaceBadge(text: "\(filteredStages.count) visible", tint: .blue)
    }
  }

  private var listBoard: some View {
    WorkspacePanel(
      title: "Pipeline list",
      subtitle: "A denser review mode for scanning every stage without losing the new visual hierarchy.",
      tint: .teal
    ) {
      if filteredStages.isEmpty {
        stageEmptyState(
          title: "No stage found",
          message: searchText.isEmpty ? "Add a stage manually or import one from a job URL." : "No stage matches the current search."
        )
      } else {
        LazyVStack(spacing: 14) {
          ForEach(filteredStages) { stage in
            StageCardView(
              stage: stage,
              limitExceeded: false,
              onStatusChange: { newStatus in
                Task { await stageStore.updateStageStatus(stageID: stage.id, to: newStatus) }
              },
              onDelete: {
                stageStore.deleteStage(stageID: stage.id)
              }
            )
          }
        }
      }
    }
  }

  private var kanbanBoard: some View {
    WorkspacePanel(
      title: "Pipeline board",
      subtitle: "Each column shows pressure against WIP limits with the same visual rhythm as the Home control board.",
      tint: .orange
    ) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 16) {
          ForEach(StageStatus.allCases) { status in
            kanbanColumn(for: status)
          }
        }
        .padding(.vertical, 4)
      }
    }
  }

  private func kanbanColumn(for status: StageStatus) -> some View {
    let items = filteredStages.filter { $0.status == status }
    let limit = configStore.config.wipLimit(for: status)
    let exceeded = items.count > limit

    return VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(status.rawValue)
            .font(.headline)
            .foregroundStyle(.white)
          Text(exceeded ? "Above WIP target" : "Within target")
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.62))
        }
        Spacer(minLength: 8)
        WorkspaceBadge(text: "\(items.count)/\(limit)", tint: exceeded ? .red : statusColor(status))
      }

      if items.isEmpty {
        stageEmptyState(title: "No stage", message: "This column is currently empty.")
      } else {
        VStack(spacing: 12) {
          ForEach(items) { stage in
            StageCardView(
              stage: stage,
              limitExceeded: exceeded,
              onStatusChange: { newStatus in
                Task { await stageStore.updateStageStatus(stageID: stage.id, to: newStatus) }
              },
              onDelete: {
                stageStore.deleteStage(stageID: stage.id)
              }
            )
          }
        }
      }
    }
    .padding(18)
    .frame(width: 328, alignment: .topLeading)
    .workspaceInteractiveSurface(cornerRadius: 24, tint: exceeded ? .red : statusColor(status), raised: false)
  }

  private func stageMetric(title: String, value: String, detail: String, tint: Color) -> some View {
    WorkspaceMetricTile(title: title, value: value, detail: detail, tint: tint)
  }

  private func stageEmptyState(title: String, message: String) -> some View {
    WorkspaceEmptyState(title: title, message: message, tint: .blue, systemImage: "tray")
  }

  private func horizontalPadding(for width: CGFloat) -> CGFloat {
    width >= 900 ? 28 : 18
  }

  private func statusColor(_ status: StageStatus) -> Color {
    switch status {
    case .open:
      return .blue
    case .applied:
      return .green
    case .interview:
      return .orange
    case .rejected:
      return .red
    }
  }

  private var filteredStages: [Stage] {
    let query = searchText.normalizedToken
    guard !query.isEmpty else { return stageStore.stages }
    return stageStore.stages.filter { stage in
      [
        stage.title,
        stage.company,
        stage.status.rawValue,
        stage.location,
        stage.url,
      ]
      .joined(separator: " ")
      .normalizedToken
      .contains(query)
    }
  }
}

struct PipelineImportSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var diagnosticsStore: DiagnosticsStore
  let initialURL: String
  let onImport: (PipelineImportPreview) -> Void
  @State private var urlText: String = ""
  @State private var preview: PipelineImportPreview?
  @State private var isLoading = false
  @State private var statusMessage: String = ""
  private let service = PipelineImportService()

  var body: some View {
    NavigationStack {
      Form {
        Section("Source URL") {
          TextField("https://www.linkedin.com/jobs/view/...", text: $urlText)
            .plainTextInputBehavior()
          HStack {
            Button("Load preview") {
              Task { await fetchPreview() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .disabled(isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if isLoading {
              ProgressView()
            }
          }
          if !statusMessage.isEmpty {
            Text(statusMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if let preview {
          Section("Preview") {
            Text("Title: \(preview.title)")
            Text("Company: \(preview.company)")
            if !preview.location.isEmpty {
              Text("Location: \(preview.location)")
            }
            if let deadline = preview.deadline {
              Text("Deadline: \(deadline.shortDate)")
            }
            Text("Source: \(preview.source)")
            Text("URL: \(preview.url)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
      }
      .navigationTitle("Pipeline import")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Import") {
            guard let preview else { return }
            onImport(preview)
            dismiss()
          }
          .disabled(preview == nil)
        }
      }
    }
    .frame(minWidth: 520, minHeight: 420)
    .onAppear {
      if urlText.isEmpty && !initialURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        urlText = initialURL
      }
    }
  }

  private func fetchPreview() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let loaded = try await service.importFromURL(urlText)
      preview = loaded
      statusMessage = "Preview loaded."
      diagnosticsStore.log(
        category: "pipeline",
        message: "Pipeline preview loaded.",
        metadata: ["url": loaded.url, "source": loaded.source]
      )
    } catch {
      preview = nil
      statusMessage = error.localizedDescription
      diagnosticsStore.log(
        severity: .warning,
        category: "pipeline",
        message: "Pipeline preview failed.",
        metadata: ["url": urlText, "error": error.localizedDescription]
      )
    }
  }
}

private func readClipboardURL() -> String? {
#if os(iOS)
  return UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string
#elseif os(macOS)
  let pb = NSPasteboard.general
  return pb.string(forType: .string)
#else
  return nil
#endif
}

struct AddStageSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft = StageDraft()
  @State private var hasDeadline = false
  let onSave: (StageDraft) -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("Stage") {
          TextField("Title", text: $draft.title)
          TextField("Company", text: $draft.company)
          TextField("URL", text: $draft.url)
          TextField("Location", text: $draft.location)
          Picker("Status", selection: $draft.status) {
            ForEach(StageStatus.allCases) { status in
              Text(status.rawValue).tag(status)
            }
          }
        }

        Section("Deadline") {
          Toggle("Has deadline", isOn: $hasDeadline.animation())
          if hasDeadline {
            DatePicker(
              "Deadline",
              selection: Binding<Date>(
                get: { draft.deadline ?? Date().addingDays(3) },
                set: { draft.deadline = $0 }
              ),
              displayedComponents: .date
            )
          }
        }

        Section("Notes") {
          TextField("Source (manual/linkedin/jobteaser...)", text: $draft.source)
          TextField("Notes", text: $draft.notes, axis: .vertical)
            .lineLimit(3...8)
        }
      }
      .navigationTitle("New stage")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if !hasDeadline {
              draft.deadline = nil
            }
            onSave(draft)
            dismiss()
          }
          .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .frame(minWidth: 500, minHeight: 460)
  }
}
