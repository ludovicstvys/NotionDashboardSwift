import SwiftUI
import UniformTypeIdentifiers

private struct SettingsTextDrafts: Equatable {
  var notionToken: String = ""
  var notionDbId: String = ""
  var notionTodoDbId: String = ""
  var bdfApiKey: String = ""
  var googlePlacesApiKey: String = ""
  var externalIcalUrl: String = ""
  var defaultReminders: String = ""
  var meetingReminders: String = ""
  var interviewReminders: String = ""
  var deadlineReminders: String = ""
  var marketSymbols: String = ""
  var notionJobTitleField: String = ""
  var notionCompanyField: String = ""
  var notionLocationField: String = ""
  var notionURLField: String = ""
  var notionStatusField: String = ""
  var notionNotesField: String = ""
  var notionCloseDateField: String = ""
  var openStatus: String = ""
  var appliedStatus: String = ""
  var interviewStatus: String = ""
  var rejectedStatus: String = ""

  static func from(config: AppConfig) -> Self {
    .init(
      notionToken: config.notionToken,
      notionDbId: config.notionDbId,
      notionTodoDbId: config.notionTodoDbId,
      bdfApiKey: config.bdfApiKey,
      googlePlacesApiKey: config.googlePlacesApiKey,
      externalIcalUrl: config.externalIcalUrl,
      defaultReminders: config.reminderPrefs.defaultMinutes.map(String.init).joined(separator: ","),
      meetingReminders: config.reminderPrefs.meetingMinutes.map(String.init).joined(separator: ","),
      interviewReminders: config.reminderPrefs.interviewMinutes.map(String.init).joined(separator: ","),
      deadlineReminders: config.reminderPrefs.deadlineMinutes.map(String.init).joined(separator: ","),
      marketSymbols: config.marketSymbols.joined(separator: ","),
      notionJobTitleField: config.notionFieldMap.jobTitle,
      notionCompanyField: config.notionFieldMap.company,
      notionLocationField: config.notionFieldMap.location,
      notionURLField: config.notionFieldMap.url,
      notionStatusField: config.notionFieldMap.status,
      notionNotesField: config.notionFieldMap.notes,
      notionCloseDateField: config.notionFieldMap.closeDate,
      openStatus: config.notionStatusMap.open,
      appliedStatus: config.notionStatusMap.applied,
      interviewStatus: config.notionStatusMap.interview,
      rejectedStatus: config.notionStatusMap.rejected
    )
  }
}

struct SettingsView: View {
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var stageStore: StageStore
  @EnvironmentObject private var updateStore: UpdateStore
  @EnvironmentObject private var googleAuthStore: GoogleAuthStore
  @EnvironmentObject private var calendarStore: CalendarStore
  @EnvironmentObject private var notificationScheduler: NotificationScheduler
  @EnvironmentObject private var marketNewsStore: MarketNewsStore
  @EnvironmentObject private var diagnosticsStore: DiagnosticsStore
  @EnvironmentObject private var focusStore: FocusStore

  @State private var exportDocument = ConnectionsTextDocument()
  @State private var showExporter = false
  @State private var showImporter = false
  @State private var manualConnectionsText: String = ""
  @State private var statusMessage: String = ""
  @State private var urlRuleInput: String = ""
  @State private var textDrafts = SettingsTextDrafts()
  @State private var draftCommitTask: Task<Void, Never>?
  @State private var showCoreSettings = true
  @State private var showCalendarSettings = true
  @State private var showProductivitySettings = true
  @State private var showAdvancedSettings = false

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        let metrics = WorkspaceLayoutMetrics(width: proxy.size.width)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            heroPanel(metrics: metrics)
            setupHealthPanel

            settingsSection("Core setup", isExpanded: $showCoreSettings) {
              settingsRow(sizeClass: metrics.sizeClass) {
                updatesPanel
              } right: {
                notionPanel
              }
            }

            settingsSection("Calendar and alerts", isExpanded: $showCalendarSettings) {
              settingsRow(sizeClass: metrics.sizeClass) {
                GoogleCalendarSettingsPanel()
              } right: {
                calendarPanel
              }
            }

            settingsSection("Productivity signals", isExpanded: $showProductivitySettings) {
              settingsRow(sizeClass: metrics.sizeClass) {
                focusPanel
              } right: {
                marketPanel
              }
            }

            settingsSection("Advanced", isExpanded: $showAdvancedSettings) {
              mappingPanel
              importExportPanel
              diagnosticsPanel
            }
          }
          .padding(.horizontal, metrics.horizontalPadding)
          .padding(.vertical, metrics.regularPanelPadding)
          .frame(maxWidth: metrics.contentMaxWidth)
          .frame(maxWidth: .infinity, alignment: .top)
        }
      }
      .background(WorkspaceBackground().equatable())
      .navigationTitle("Settings")
      .safeAreaInset(edge: .bottom) {
        FooterMessageHost(message: footerMessage.isEmpty ? nil : footerMessage)
      }
    }
    .fileExporter(
      isPresented: $showExporter,
      document: exportDocument,
      contentType: .plainText,
      defaultFilename: "connections-config-\(fileStamp())"
    ) { result in
      switch result {
      case .success:
        statusMessage = "Connections exported to .txt."
      case let .failure(error):
        statusMessage = "Export failed: \(error.localizedDescription)"
      }
    }
    .fileImporter(
      isPresented: $showImporter,
      allowedContentTypes: [.plainText, .json],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case let .success(urls):
        guard let url = urls.first else { return }
        importFromFile(url: url)
      case let .failure(error):
        statusMessage = "Import failed: \(error.localizedDescription)"
      }
    }
    .onAppear {
      if manualConnectionsText.isEmpty {
        manualConnectionsText = (try? configStore.exportConnectionsText()) ?? ""
      }
      syncTextDraftsFromConfig()
      Task { await notificationScheduler.refreshAuthorizationStatus() }
    }
    .onDisappear {
      draftCommitTask?.cancel()
    }
    .onChange(of: textDrafts) { _ in
      scheduleDraftCommit()
    }
    .instrumentedScreen("SettingsView")
  }

  private func heroPanel(metrics: WorkspaceLayoutMetrics) -> some View {
    WorkspaceHeroPanel(tint: WorkspacePalette.warning, padding: metrics.regularPanelPadding) {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 12) {
            Text("SETTINGS")
              .font(.caption2.weight(.bold))
              .tracking(1.8)
              .foregroundStyle(Color.white.opacity(0.70))

            Text("Control center.\nNo hidden setup.")
              .font(.system(size: metrics.sizeClass == .wide ? 42 : 34, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)
              .fixedSize(horizontal: false, vertical: true)

            Text("Manage credentials, sync, reminders, exports and diagnostics from predictable grouped controls.")
              .font(.subheadline)
              .foregroundStyle(Color.white.opacity(0.72))
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)

          VStack(alignment: .trailing, spacing: 10) {
            WorkspaceBadge(text: configStore.config.hasNotionCredentials ? "Notion connected" : "Notion missing", tint: configStore.config.hasNotionCredentials ? WorkspacePalette.success : WorkspacePalette.warning)
            WorkspaceBadge(text: googleAuthStore.isAuthenticated ? "Google connected" : "Google idle", tint: googleAuthStore.isAuthenticated ? WorkspacePalette.accent : WorkspacePalette.warning)
          }
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
          settingsMetric(title: "Queue", value: "\(stageStore.pendingQueueCount)", detail: stageStore.pendingQueueCount == 0 ? "nothing pending" : "waiting sync ops", tint: WorkspacePalette.warning)
          settingsMetric(title: "Alerts", value: notificationMetricValue, detail: notificationMetricDetail, tint: .white)
          SettingsFocusMetricTile()
          settingsMetric(title: "Feeds", value: "\(activeFeedCount)", detail: activeFeedCount == 0 ? "no source active" : "calendar and market inputs", tint: WorkspacePalette.accentSoft)
        }
      }
    }
  }

  private var updatesPanel: some View {
    WorkspacePanel(
      title: "Updates",
      subtitle: "Sparkle now checks the signed appcast on GitHub Pages and can install newer macOS builds in place.",
      tint: WorkspacePalette.accent
    ) {
#if os(macOS)
      VStack(alignment: .leading, spacing: 18) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
          settingsMetric(title: "Installed", value: updateStore.currentVersion, detail: "marketing version", tint: WorkspacePalette.accent)
          settingsMetric(title: "Build", value: "\(updateStore.currentBuild)", detail: "local bundle build", tint: WorkspacePalette.warning)
          settingsMetric(title: "Channel", value: updateStore.channel.uppercased(), detail: "release stream", tint: .white)
          settingsMetric(title: "Last check", value: updateStore.lastCheckLabel, detail: "latest Sparkle run", tint: WorkspacePalette.accentSoft)
        }

        Toggle(
          "Automatically check every \(updateStore.checkIntervalLabel)",
          isOn: Binding(
            get: { updateStore.automaticChecksEnabled },
            set: { updateStore.setAutomaticChecksEnabled($0) }
          )
        )
        .toggleStyle(.switch)

        Toggle(
          "Automatically download and install when possible",
          isOn: Binding(
            get: { updateStore.automaticDownloadsEnabled },
            set: { updateStore.setAutomaticDownloadsEnabled($0) }
          )
        )
        .toggleStyle(.switch)
        .disabled(!updateStore.allowsAutomaticDownloads)

        VStack(alignment: .leading, spacing: 8) {
          panelLabel("Status")
          panelMessage("\(updateStore.statusLabel): \(updateStore.detailMessage)")
        }

        HStack(spacing: 10) {
          Button("Check for updates") {
            Task { await updateStore.checkForUpdates(userInitiated: true) }
          }
          .buttonStyle(.borderedProminent)
          .tint(WorkspacePalette.accent)
          .disabled(updateStore.state == .checking)

          if updateStore.availableUpdate?.releaseNotesURL != nil {
            Button("Release notes") {
              updateStore.openReleaseNotesURL()
            }
            .buttonStyle(.bordered)
          }
        }

        if let availableUpdate = updateStore.availableUpdate {
          VStack(alignment: .leading, spacing: 8) {
            panelLabel("Published build ready")
            panelMessage(
              "\(availableUpdate.versionLabel) on channel \(availableUpdate.channel) was published \(availableUpdate.publishedAt?.shortDateTime ?? "recently")."
            )
          }
        }
      }
#else
      VStack(alignment: .leading, spacing: 8) {
        panelLabel("Unavailable on iOS")
        panelMessage("Sparkle updates are only available in the macOS app.")
      }
#endif
    }
  }

  private var setupHealthPanel: some View {
    WorkspacePanel(
      title: "Setup health",
      subtitle: "The minimum viable dashboard setup in one readable checklist.",
      tint: setupHealthTint
    ) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 10) {
          WorkspaceBadge(text: setupHealthTitle, tint: setupHealthTint)
          WorkspaceBadge(text: "\(activeFeedCount) active feed(s)", tint: WorkspacePalette.accentSoft)
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
          settingsMetric(
            title: "Notion",
            value: configStore.config.hasNotionCredentials ? "Ready" : "Missing",
            detail: "pipeline source",
            tint: configStore.config.hasNotionCredentials ? WorkspacePalette.success : WorkspacePalette.warning
          )
          settingsMetric(
            title: "Calendar",
            value: calendarReady ? "Ready" : "Missing",
            detail: calendarStore.sourceSummary,
            tint: calendarReady ? WorkspacePalette.success : WorkspacePalette.warning
          )
          settingsMetric(
            title: "Alerts",
            value: notificationMetricValue,
            detail: notificationMetricDetail,
            tint: notificationsReady ? WorkspacePalette.success : WorkspacePalette.warning
          )
          settingsMetric(
            title: "Focus",
            value: focusStore.isEnabled ? "Running" : (configStore.config.focusModeEnabled ? "On" : "Off"),
            detail: focusStore.focusSummary,
            tint: .pink
          )
        }

        if setupIssues.isEmpty {
          panelMessage("Everything required for the dashboard is configured.")
        } else {
          VStack(alignment: .leading, spacing: 8) {
            panelLabel("Needs attention")
            ForEach(setupIssues, id: \.self) { issue in
              panelMessage(issue)
            }
          }
        }
      }
    }
  }

  private var notionPanel: some View {
    WorkspacePanel(
      title: "Notion and pipeline",
      subtitle: "Credentials, sync controls, offline queue, and external API keys live together.",
      tint: WorkspacePalette.accentSoft
    ) {
      VStack(alignment: .leading, spacing: 18) {
        settingsTextField("Notion token", text: textDraftBinding(\.notionToken), prompt: "Paste your integration token", monospaced: true)
        settingsTextField("Stages database", text: textDraftBinding(\.notionDbId), prompt: "Database ID or URL", monospaced: true)
        settingsTextField("Todo database", text: textDraftBinding(\.notionTodoDbId), prompt: "Todo database ID or URL", monospaced: true)

        HStack(spacing: 10) {
          Button("Test connection") {
            commitTextDrafts()
            Task {
              statusMessage = await stageStore.testNotionConnection()
            }
          }
          .buttonStyle(.bordered)

          Button("Sync from Notion") {
            commitTextDrafts()
            Task { await stageStore.syncFromNotion() }
          }
          .buttonStyle(.borderedProminent)
          .tint(WorkspacePalette.accent)

          Button("Push local to Notion") {
            commitTextDrafts()
            Task { await stageStore.pushAllToNotion() }
          }
          .buttonStyle(.bordered)

          Button("Flush queue (\(stageStore.pendingQueueCount))") {
            Task { await stageStore.flushPendingOperations() }
          }
          .buttonStyle(.bordered)
          .disabled(stageStore.pendingQueueCount == 0 || stageStore.isSyncingNotion)
        }

        settingsDivider

        settingsTextField("Banque de France API key", text: textDraftBinding(\.bdfApiKey), prompt: "Optional market data key", monospaced: true)
        settingsTextField("Google Places API key", text: textDraftBinding(\.googlePlacesApiKey), prompt: "Optional calendar enrichment key", monospaced: true)
        if !stageStore.syncMessage.isEmpty {
          panelMessage(stageStore.syncMessage)
        }
      }
    }
  }

  private var calendarPanel: some View {
    WorkspacePanel(
      title: "Calendar and reminders",
      subtitle: "iCal source, notification authorization, and offsets are grouped by event flow.",
      tint: WorkspacePalette.warning
    ) {
      VStack(alignment: .leading, spacing: 18) {
        settingsTextField("External iCal feed", text: textDraftBinding(\.externalIcalUrl), prompt: "Paste calendar feed", monospaced: true)
        panelHint("The Calendar screen uses this feed when loading external events.")

        HStack(spacing: 10) {
          Button("Request notification permission") {
            Task { await notificationScheduler.requestAuthorization() }
          }
          .buttonStyle(.borderedProminent)
          .tint(WorkspacePalette.warning)

          Button("Reschedule reminders now") {
            commitTextDrafts()
            Task {
              await notificationScheduler.scheduleEventReminders(
                events: calendarStore.events,
                prefs: configStore.config.reminderPrefs
              )
            }
          }
          .buttonStyle(.bordered)

          Button("Schedule daily summary") {
            Task {
              await notificationScheduler.scheduleDailySummary(events: calendarStore.events)
            }
          }
          .buttonStyle(.bordered)
        }

        settingsDivider

        settingsTextField("Default reminders", text: textDraftBinding(\.defaultReminders), prompt: "Ex: 30,10", monospaced: true)
        settingsTextField("Meeting reminders", text: textDraftBinding(\.meetingReminders), prompt: "Ex: 60,15", monospaced: true)
        settingsTextField("Interview reminders", text: textDraftBinding(\.interviewReminders), prompt: "Ex: 1440,120,30", monospaced: true)
        settingsTextField("Deadline reminders", text: textDraftBinding(\.deadlineReminders), prompt: "Ex: 2880,1440,120", monospaced: true)

        if !notificationScheduler.lastStatusMessage.isEmpty {
          panelMessage(notificationScheduler.lastStatusMessage)
        }
      }
    }
  }

  private var focusPanel: some View {
    SettingsFocusPanel(urlRuleInput: $urlRuleInput)
  }

  private var marketPanel: some View {
    WorkspacePanel(
      title: "Markets and news",
      subtitle: "Signal toggles and ticker universe stay in one panel instead of being buried in a long form.",
      tint: WorkspacePalette.success
    ) {
      VStack(alignment: .leading, spacing: 18) {
        Toggle("Enable news", isOn: binding(for: \.newsEnabled))
          .toggleStyle(.switch)
        Toggle("Enable markets", isOn: binding(for: \.marketsEnabled))
          .toggleStyle(.switch)

        settingsTextField("Market symbols", text: textDraftBinding(\.marketSymbols), prompt: "^GSPC, EURUSD=X, BTC-USD", monospaced: true)

        Button("Refresh news + markets") {
          commitTextDrafts()
          Task { await marketNewsStore.refreshAll() }
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkspacePalette.success)
      }
    }
  }

  private var mappingPanel: some View {
    WorkspacePanel(
      title: "Mapping and limits",
      subtitle: "Notion field names, status values, and WIP limits are grouped as one schema panel.",
      tint: WorkspacePalette.warning
    ) {
      VStack(alignment: .leading, spacing: 18) {
        settingsTextField("Job title field", text: textDraftBinding(\.notionJobTitleField), prompt: "Job Title")
        settingsTextField("Company field", text: textDraftBinding(\.notionCompanyField), prompt: "Entreprise")
        settingsTextField("Location field", text: textDraftBinding(\.notionLocationField), prompt: "Lieu")
        settingsTextField("URL field", text: textDraftBinding(\.notionURLField), prompt: "lien offre")
        settingsTextField("Status field", text: textDraftBinding(\.notionStatusField), prompt: "Status")
        settingsTextField("Notes field", text: textDraftBinding(\.notionNotesField), prompt: "Notes")
        settingsTextField("Close date field", text: textDraftBinding(\.notionCloseDateField), prompt: "Date de fermeture")

        settingsDivider

        settingsTextField("Open status", text: textDraftBinding(\.openStatus), prompt: "Ouvert")
        settingsTextField("Applied status", text: textDraftBinding(\.appliedStatus), prompt: "Candidature")
        settingsTextField("Interview status", text: textDraftBinding(\.interviewStatus), prompt: "Entretien")
        settingsTextField("Rejected status", text: textDraftBinding(\.rejectedStatus), prompt: "Refuse")

        settingsDivider

        VStack(alignment: .leading, spacing: 10) {
          panelLabel("WIP limits")
          ForEach(StageStatus.allCases) { status in
            Stepper(
              "\(status.rawValue): \(configStore.config.wipLimit(for: status))",
              value: wipBinding(for: status),
              in: 1 ... 999
            )
          }
        }
      }
    }
  }

  private var importExportPanel: some View {
    WorkspacePanel(
      title: "Import and export",
      subtitle: "Sensitive connection snapshots can be reviewed, exported, and re-imported from a single transport panel.",
      tint: WorkspacePalette.accentSoft
    ) {
      VStack(alignment: .leading, spacing: 18) {
        Text("This export contains sensitive data, including tokens and API keys.")
          .font(.caption)
          .foregroundStyle(WorkspacePalette.warning.opacity(0.95))

        HStack(spacing: 10) {
          Button("Export .txt") {
            prepareConnectionsExport()
          }
          .buttonStyle(.borderedProminent)
          .tint(WorkspacePalette.accent)

          Button("Import file") {
            showImporter = true
          }
          .buttonStyle(.bordered)
        }

        TextEditor(text: $manualConnectionsText)
          .font(.system(.footnote, design: .monospaced))
          .frame(minHeight: 220)
          .padding(10)
          .scrollContentBackground(.hidden)
          .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .fill(WorkspacePalette.innerCard)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .stroke(Color.white.opacity(0.10), lineWidth: 1)
          )

        HStack(spacing: 10) {
          Button("Import text") {
            do {
              try configStore.importConnectionsText(manualConnectionsText)
              syncTextDraftsFromConfig()
              googleAuthStore.refreshAuthState()
              calendarStore.selectedCalendarIDs = Set(configStore.config.googleSelectedCalendarIDs)
              statusMessage = "Connections imported from text."
            } catch {
              statusMessage = "Import text failed: \(error.localizedDescription)"
            }
          }
          .buttonStyle(.bordered)

          Button("Refresh text from current config") {
            commitTextDrafts()
            manualConnectionsText = (try? configStore.exportConnectionsText()) ?? ""
          }
          .buttonStyle(.bordered)
        }

        if !statusMessage.isEmpty {
          panelMessage(statusMessage)
        }
      }
    }
  }

  private var diagnosticsPanel: some View {
    WorkspacePanel(
      title: "Diagnostics",
      subtitle: "Offline queue visibility and recent logs stay visible without falling back to a raw form list.",
      tint: .white
    ) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 12) {
          WorkspaceMetricTile(
            title: "Queue",
            value: "\(stageStore.pendingQueueCount)",
            detail: stageStore.pendingQueueCount == 0 ? "no pending ops" : "awaiting retry",
            tint: WorkspacePalette.warning
          )
          WorkspaceMetricTile(
            title: "Last sync",
            value: stageStore.lastSuccessfulNotionSyncDate?.shortDateTime ?? "Never",
            detail: stageStore.lastSuccessfulNotionSyncDate == nil ? "not synced yet" : "last successful Notion sync",
            tint: WorkspacePalette.success
          )
          Spacer(minLength: 0)
          Button("Clear logs") { diagnosticsStore.clear() }
            .buttonStyle(.bordered)
        }

        if stageStore.pendingQueueCount > 0 {
          VStack(alignment: .leading, spacing: 8) {
            panelLabel("Pending operations")
            HStack(spacing: 8) {
              panelBadge("Upserts: \(pendingOperationCount(kind: .upsertStage))", tint: WorkspacePalette.accent)
              panelBadge("Status: \(pendingOperationCount(kind: .updateStatus))", tint: WorkspacePalette.warning)
            }
            ForEach(stageStore.pendingOperations.prefix(20)) { op in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(op.kind.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                  Spacer()
                  Text("retry: \(op.retryCount)")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.62))
                }
                Text(pendingOperationTitle(op))
                  .font(.caption)
                  .foregroundStyle(Color.white.opacity(0.78))
                if !pendingOperationSubtitle(op).isEmpty {
                  Text(pendingOperationSubtitle(op))
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.58))
                }
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 10)
              .workspaceInteractiveSurface(cornerRadius: 16, tint: WorkspacePalette.warning, raised: false)
            }
          }
        }

        if diagnosticsStore.entries.isEmpty {
          panelHint("No diagnostics yet.")
        } else {
          VStack(alignment: .leading, spacing: 10) {
            panelLabel("Recent entries")
            ForEach(diagnosticsStore.entries.prefix(25)) { entry in
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text(entry.category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                  Spacer()
                  Text(entry.createdAt.shortDateTime)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.62))
                }
                Text(entry.message)
                  .font(.caption)
                  .foregroundStyle(Color.white.opacity(0.80))
                if !entry.metadata.isEmpty {
                  Text(entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " | "))
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.60))
                }
              }
              .padding(14)
              .frame(maxWidth: .infinity, alignment: .leading)
              .workspaceInteractiveSurface(cornerRadius: 18, tint: .white, raised: false)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func settingsRow<Left: View, Right: View>(
    sizeClass: WorkspaceSizeClass,
    @ViewBuilder left: () -> Left,
    @ViewBuilder right: () -> Right
  ) -> some View {
    if sizeClass == .wide {
      HStack(alignment: .top, spacing: 20) {
        left()
        right()
      }
    } else {
      VStack(spacing: 20) {
        left()
        right()
      }
    }
  }

  private func settingsSection<Content: View>(
    _ title: String,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    DisclosureGroup(isExpanded: isExpanded) {
      VStack(alignment: .leading, spacing: 20) {
        content()
      }
      .padding(.top, 16)
    } label: {
      HStack {
        Text(title)
          .font(.headline.weight(.semibold))
          .foregroundStyle(.white)
        Spacer()
        Text(isExpanded.wrappedValue ? "Hide" : "Show")
          .font(.caption.weight(.bold))
          .foregroundStyle(Color.white.opacity(0.62))
      }
    }
    .padding(18)
    .workspaceInteractiveSurface(cornerRadius: 24, tint: WorkspacePalette.accent, raised: false)
  }

  private func settingsTextField(
    _ title: String,
    text: Binding<String>,
    prompt: String,
    monospaced: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      panelLabel(title)
      TextField(prompt, text: text)
        .textFieldStyle(.roundedBorder)
        .plainTextInputBehavior()
        .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
    }
  }

  private func settingsMetric(title: String, value: String, detail: String, tint: Color) -> some View {
    WorkspaceMetricTile(title: title, value: value, detail: detail, tint: tint)
  }

  private var settingsDivider: some View {
    Rectangle()
      .fill(Color.white.opacity(0.08))
      .frame(height: 1)
  }

  private func panelLabel(_ text: String) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(Color.white.opacity(0.68))
  }

  private func panelHint(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(Color.white.opacity(0.60))
      .fixedSize(horizontal: false, vertical: true)
  }

  private func panelMessage(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(Color.white.opacity(0.80))
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .workspaceInteractiveSurface(cornerRadius: 16, tint: .white, raised: false)
  }

  private var notificationMetricValue: String {
    switch notificationScheduler.authorizationStatus {
    case .authorized, .provisional:
      return "Ready"
    case .denied:
      return "Denied"
    case .notDetermined:
      return "Ask"
    case .ephemeral:
      return "Temp"
    @unknown default:
      return "?"
    }
  }

  private var notificationMetricDetail: String {
    switch notificationScheduler.authorizationStatus {
    case .authorized, .provisional:
      return "notifications armed"
    case .denied:
      return "permission blocked"
    case .notDetermined:
      return "permission pending"
    case .ephemeral:
      return "temporary access"
    @unknown default:
      return "unknown state"
    }
  }

  private var activeFeedCount: Int {
    var count = 0
    if googleAuthStore.isAuthenticated { count += 1 }
    if !configStore.config.externalIcalUrl.isEmpty { count += 1 }
    if configStore.config.newsEnabled { count += 1 }
    if configStore.config.marketsEnabled { count += 1 }
    return count
  }

  private var calendarReady: Bool {
    googleAuthStore.isAuthenticated || !configStore.config.externalIcalUrl.isEmpty
  }

  private var notificationsReady: Bool {
    switch notificationScheduler.authorizationStatus {
    case .authorized, .provisional:
      return true
    case .denied, .notDetermined, .ephemeral:
      return false
    @unknown default:
      return false
    }
  }

  private var setupHealthTitle: String {
    setupIssues.isEmpty ? "Healthy" : "\(setupIssues.count) issue(s)"
  }

  private var setupHealthTint: Color {
    setupIssues.isEmpty ? WorkspacePalette.success : WorkspacePalette.warning
  }

  private var setupIssues: [String] {
    var issues: [String] = []
    if !configStore.config.hasNotionCredentials {
      issues.append("Add a Notion token and database ID to enable pipeline sync.")
    }
    if !calendarReady {
      issues.append("Connect Google Calendar or add an external iCal URL.")
    }
    if notificationScheduler.authorizationStatus == .notDetermined {
      issues.append("Request notification permission to enable reminders.")
    }
    if notificationScheduler.authorizationStatus == .denied {
      issues.append("Notifications are blocked in system settings.")
    }
    if configStore.config.marketsEnabled && configStore.config.marketSymbols.isEmpty {
      issues.append("Add at least one market symbol or disable market signals.")
    }
    return issues
  }

  private var footerMessage: String {
    if !statusMessage.isEmpty {
      return statusMessage
    }
    if !stageStore.syncMessage.isEmpty {
      return stageStore.syncMessage
    }
    return ""
  }

  private func importFromFile(url: URL) {
    do {
      let secured = url.startAccessingSecurityScopedResource()
      defer {
        if secured {
          url.stopAccessingSecurityScopedResource()
        }
      }

      let data = try Data(contentsOf: url)
      guard let text = String(data: data, encoding: .utf8) else {
        statusMessage = "Import failed: invalid file encoding."
        return
      }
      try configStore.importConnectionsText(text)
      manualConnectionsText = text
      syncTextDraftsFromConfig()
      googleAuthStore.refreshAuthState()
      calendarStore.selectedCalendarIDs = Set(configStore.config.googleSelectedCalendarIDs)
      statusMessage = "Connections imported from file."
    } catch {
      statusMessage = "Import failed: \(error.localizedDescription)"
    }
  }

  private func fileStamp(date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
  }

  private func binding<Value>(for keyPath: WritableKeyPath<AppConfig, Value>) -> Binding<Value> {
    Binding(
      get: { configStore.config[keyPath: keyPath] },
      set: { newValue in
        configStore.update { config in
          config[keyPath: keyPath] = newValue
        }
      }
      )
  }

  private func panelBadge(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(tint.opacity(0.16))
      .foregroundStyle(tint)
      .clipShape(Capsule())
  }

  private func pendingOperationCount(kind: PendingNotionOperation.Kind) -> Int {
    stageStore.pendingOperations.filter { $0.kind == kind }.count
  }

  private func pendingOperationTitle(_ op: PendingNotionOperation) -> String {
    switch op.kind {
    case .upsertStage:
      if let stage = op.stage {
        return stage.displayLabel.isEmpty ? "Stage" : stage.displayLabel
      }
      return op.stageID ?? "Stage"
    case .updateStatus:
      return op.stageID ?? "Stage status"
    }
  }

  private func pendingOperationSubtitle(_ op: PendingNotionOperation) -> String {
    switch op.kind {
    case .upsertStage:
      return op.stage?.status.rawValue ?? "Waiting for Notion upsert"
    case .updateStatus:
      return op.status?.rawValue ?? "Waiting for Notion status update"
    }
  }

  private var defaultCalendarLabel: String {
    let selected = configStore.config.googleDefaultCalendarID
    guard !selected.isEmpty else { return "Primary" }
    return calendarStore.googleCalendars.first(where: { $0.id == selected })?.name ?? "Primary"
  }

  private func textDraftBinding(_ keyPath: WritableKeyPath<SettingsTextDrafts, String>) -> Binding<String> {
    Binding(
      get: { textDrafts[keyPath: keyPath] },
      set: { newValue in
        textDrafts[keyPath: keyPath] = newValue
      }
    )
  }

  private func syncTextDraftsFromConfig() {
    let snapshot = SettingsTextDrafts.from(config: configStore.config)
    if textDrafts != snapshot {
      textDrafts = snapshot
    }
  }

  private func scheduleDraftCommit() {
    draftCommitTask?.cancel()
    draftCommitTask = Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        commitTextDrafts()
      }
    }
  }

  private func commitTextDrafts() {
    draftCommitTask?.cancel()
    draftCommitTask = nil

    let currentConfig = configStore.config
    let nextSymbols = parseCSV(textDrafts.marketSymbols)
    var nextConfig = currentConfig
    nextConfig.notionToken = normalizedDraftValue(textDrafts.notionToken)
    nextConfig.notionDbId = normalizedDraftValue(textDrafts.notionDbId)
    nextConfig.notionTodoDbId = normalizedDraftValue(textDrafts.notionTodoDbId)
    nextConfig.bdfApiKey = normalizedDraftValue(textDrafts.bdfApiKey)
    nextConfig.googlePlacesApiKey = normalizedDraftValue(textDrafts.googlePlacesApiKey)
    nextConfig.externalIcalUrl = normalizedDraftValue(textDrafts.externalIcalUrl)
    nextConfig.reminderPrefs = ReminderPrefs(
      defaultMinutes: parseReminderList(textDrafts.defaultReminders, fallback: ReminderPrefs.defaults.defaultMinutes),
      meetingMinutes: parseReminderList(textDrafts.meetingReminders, fallback: ReminderPrefs.defaults.meetingMinutes),
      interviewMinutes: parseReminderList(textDrafts.interviewReminders, fallback: ReminderPrefs.defaults.interviewMinutes),
      deadlineMinutes: parseReminderList(textDrafts.deadlineReminders, fallback: ReminderPrefs.defaults.deadlineMinutes)
    )
    nextConfig.marketSymbols = nextSymbols.isEmpty ? AppConfig.defaults.marketSymbols : nextSymbols
    nextConfig.notionFieldMap = NotionFieldMap(
      jobTitle: normalizedDraftValue(textDrafts.notionJobTitleField).ifEmpty("Job Title"),
      company: normalizedDraftValue(textDrafts.notionCompanyField).ifEmpty("Entreprise"),
      location: normalizedDraftValue(textDrafts.notionLocationField).ifEmpty("Lieu"),
      url: normalizedDraftValue(textDrafts.notionURLField).ifEmpty("lien offre"),
      status: normalizedDraftValue(textDrafts.notionStatusField).ifEmpty("Status"),
      closeDate: normalizedDraftValue(textDrafts.notionCloseDateField).ifEmpty("Date de fermeture"),
      notes: normalizedDraftValue(textDrafts.notionNotesField).ifEmpty("Notes")
    )
    nextConfig.notionStatusMap = NotionStatusMap(
      open: normalizedDraftValue(textDrafts.openStatus).ifEmpty("Ouvert"),
      applied: normalizedDraftValue(textDrafts.appliedStatus).ifEmpty("Candidature"),
      interview: normalizedDraftValue(textDrafts.interviewStatus).ifEmpty("Entretien"),
      rejected: normalizedDraftValue(textDrafts.rejectedStatus).ifEmpty("Refuse")
    )

    guard nextConfig != currentConfig else { return }
    configStore.update { config in
      config = nextConfig
    }
    syncTextDraftsFromConfig()
  }

  private func prepareConnectionsExport() {
    commitTextDrafts()
    do {
      let text = try configStore.exportConnectionsText()
      manualConnectionsText = text
      exportDocument = ConnectionsTextDocument(text: text)
      showExporter = true
    } catch {
      statusMessage = "Export preparation failed: \(error.localizedDescription)"
    }
  }

  private func parseReminderList(_ value: String, fallback: [Int]) -> [Int] {
    let parsed = value
      .split(separator: ",")
      .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
      .filter { $0 > 0 }
    return parsed.isEmpty ? fallback : parsed
  }

  private func parseCSV(_ value: String) -> [String] {
    value
      .split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func normalizedDraftValue(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func wipBinding(for status: StageStatus) -> Binding<Int> {
    Binding(
      get: { configStore.config.wipLimit(for: status) },
      set: { newValue in
        configStore.update { config in
          config.wipLimits[status.key] = newValue
        }
      }
    )
  }
}

private struct SettingsFocusMetricTile: View {
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var focusStore: FocusStore

  var body: some View {
    WorkspaceMetricTile(
      title: "Focus",
      value: configStore.config.focusModeEnabled ? "On" : "Off",
      detail: configStore.config.focusModeEnabled ? focusStore.focusSummary : "guardrails idle",
      tint: .teal
    )
  }
}

private struct SettingsFocusPanel: View {
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var focusStore: FocusStore
  @Binding var urlRuleInput: String

  var body: some View {
    WorkspacePanel(
      title: "Focus mode",
      subtitle: "Pomodoro timing and URL blocking now sit in the same guardrail panel.",
      tint: .pink
    ) {
      VStack(alignment: .leading, spacing: 18) {
        Toggle(
          "Enable focus mode",
          isOn: Binding(
            get: { configStore.config.focusModeEnabled },
            set: { enabled in
              Task { @MainActor in
                focusStore.setEnabled(enabled)
              }
            }
          )
        )
        .toggleStyle(.switch)

        Stepper(
          "Pomodoro work: \(configStore.config.pomodoroWorkMinutes)m",
          value: Binding(
            get: { configStore.config.pomodoroWorkMinutes },
            set: { newValue in
              configStore.update { $0.pomodoroWorkMinutes = newValue }
            }
          ),
          in: 5 ... 120
        )

        Stepper(
          "Pomodoro break: \(configStore.config.pomodoroBreakMinutes)m",
          value: Binding(
            get: { configStore.config.pomodoroBreakMinutes },
            set: { newValue in
              configStore.update { $0.pomodoroBreakMinutes = newValue }
            }
          ),
          in: 1 ... 60
        )

        HStack(spacing: 10) {
          TextField("Add blocked rule (ex: youtube.com)", text: $urlRuleInput)
            .textFieldStyle(.roundedBorder)
            .plainTextInputBehavior()
          Button("Add") {
            addURLRule()
          }
          .buttonStyle(.bordered)
        }

        Text("Rules match every path on a blocked host, for example instagram.com also blocks instagram.com/direct/inbox. This protects links opened from Dashboard and notifications; it does not intercept URLs typed directly in a browser.")
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.62))

        if configStore.config.urlBlockerRules.isEmpty {
          Text("No blocked host configured.")
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.60))
        } else {
          VStack(spacing: 8) {
            ForEach(configStore.config.urlBlockerRules, id: \.self) { rule in
              HStack {
                Text(rule)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.white)
                Spacer()
                Button(role: .destructive) {
                  configStore.update { config in
                    config.urlBlockerRules.removeAll { $0 == rule }
                  }
                } label: {
                  Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .workspaceInteractiveSurface(cornerRadius: 16, tint: .pink, raised: false)
            }
          }
        }

        HStack(spacing: 10) {
          Button("Start focus session") { focusStore.startSession() }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
          Button("Stop") { focusStore.stopSession() }
            .buttonStyle(.bordered)
        }

        Text("Phase: \(focusStore.focusSummary) | Remaining: \(max(0, focusStore.remainingSeconds / 60))m")
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.80))
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .workspaceInteractiveSurface(cornerRadius: 16, tint: .pink, raised: false)
      }
    }
  }

  private func addURLRule() {
    let clean = urlRuleInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    if !configStore.config.urlBlockerRules.contains(clean) {
      configStore.update { $0.urlBlockerRules.append(clean) }
    }
    urlRuleInput = ""
  }
}

struct GoogleCalendarSettingsPanel: View {
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var googleAuthStore: GoogleAuthStore
  @EnvironmentObject private var calendarStore: CalendarStore

  var body: some View {
    WorkspacePanel(
      title: "Google Calendar",
      subtitle: "Connect once, then choose calendars and sync behavior from a single surface.",
      tint: WorkspacePalette.accent
    ) {
      VStack(alignment: .leading, spacing: 18) {
        actionBar
        summaryRow
        calendarList
        statusSection
      }
    }
  }

  private var actionBar: some View {
    HStack(spacing: 10) {
      Button(googleAuthStore.isAuthenticated ? "Reconnect" : "Connect Google") {
        Task {
          let connected = await googleAuthStore.signInInteractive()
          if connected {
            await calendarStore.loadGoogleCalendars(force: true)
            await calendarStore.loadCombinedEvents(icalURL: configStore.config.externalIcalUrl)
          }
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(WorkspacePalette.accent)

      Button("Disconnect") {
        googleAuthStore.signOut()
        Task { await calendarStore.handleGoogleSignOut(icalURL: configStore.config.externalIcalUrl) }
      }
      .buttonStyle(.bordered)
      .disabled(!googleAuthStore.isAuthenticated)

      Button("Refresh calendars") {
        Task {
          await calendarStore.loadGoogleCalendars(force: true)
          await calendarStore.loadCombinedEvents(icalURL: configStore.config.externalIcalUrl)
        }
      }
      .buttonStyle(.bordered)

      Button("Primary only") {
        selectPrimaryCalendar()
      }
      .buttonStyle(.bordered)
      .disabled(calendarStore.googleCalendars.isEmpty)
    }
  }

  private var summaryRow: some View {
    HStack(spacing: 10) {
      WorkspaceBadge(
        text: googleAuthStore.connectionSummary,
        tint: googleAuthStore.isAuthenticated ? WorkspacePalette.success : WorkspacePalette.warning
      )
      WorkspaceBadge(
        text: calendarStore.googleSyncSummary,
        tint: WorkspacePalette.accentSoft
      )
    }
  }

  private var calendarList: some View {
    Group {
      if calendarStore.googleCalendars.isEmpty {
        panelHint(googleAuthStore.isAuthenticated ? "No calendars loaded yet. Refresh to fetch your Google calendars." : "Connect Google to load calendars.")
      } else {
        VStack(alignment: .leading, spacing: 8) {
          panelLabel("Calendars")
          ForEach(calendarStore.googleCalendars) { cal in
            Toggle(isOn: Binding(
              get: { calendarStore.selectedCalendarIDs.contains(cal.id) },
              set: { isSelected in
                Task {
                  await calendarStore.setCalendarSelected(
                    calendarID: cal.id,
                    isSelected: isSelected,
                    icalURL: configStore.config.externalIcalUrl
                  )
                }
              }
            )) {
              HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                  HStack(spacing: 8) {
                    ColorDot(color: cal.backgroundColor)
                      .frame(width: 10, height: 10)
                    Text(cal.name)
                    if cal.isPrimary {
                      Text("Primary")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WorkspacePalette.innerCard)
                        .clipShape(Capsule())
                    }
                  }
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.white)
                  Text("\(cal.id) • \(calendarStore.eventCount(for: cal.id)) events")
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color.white.opacity(0.58))
                }
                Spacer()
              }
            }
            .toggleStyle(.switch)
          }
        }
      }
    }
  }

  private var statusSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      panelMessage(googleAuthStore.statusMessage)
      if !calendarStore.statusMessage.isEmpty {
        panelMessage(calendarStore.statusMessage)
      }
    }
  }

  private func selectPrimaryCalendar() {
    let primary = calendarStore.googleCalendars.first(where: \.isPrimary)?.id
    configStore.update { config in
      config.googleSelectedCalendarIDs = primary.map { [$0] } ?? []
      config.googleDefaultCalendarID = primary ?? ""
    }
    calendarStore.selectedCalendarIDs = primary.map { Set([$0]) } ?? []
  }

  private func settingsTextField(
    _ title: String,
    text: Binding<String>,
    prompt: String,
    monospaced: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      panelLabel(title)
      TextField(prompt, text: text)
        .textFieldStyle(.roundedBorder)
        .plainTextInputBehavior()
        .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
    }
  }

  private func panelLabel(_ text: String) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(Color.white.opacity(0.68))
  }

  private func panelHint(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(Color.white.opacity(0.60))
      .fixedSize(horizontal: false, vertical: true)
  }

  private func panelMessage(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(Color.white.opacity(0.80))
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .workspaceInteractiveSurface(cornerRadius: 16, tint: .white, raised: false)
  }
}

private struct ColorDot: View {
  let color: String?

  var body: some View {
    Circle()
      .fill(WorkspaceColor.hex(color) ?? WorkspacePalette.accent)
  }
}

private extension String {
  func ifEmpty(_ fallback: String) -> String {
    isEmpty ? fallback : self
  }
}
