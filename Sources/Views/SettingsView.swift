import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @EnvironmentObject private var configStore: ConfigStore
  @EnvironmentObject private var stageStore: StageStore
  @EnvironmentObject private var updateStore: UpdateStore
  @EnvironmentObject private var googleAuthStore: GoogleAuthStore
  @EnvironmentObject private var calendarStore: CalendarStore
  @EnvironmentObject private var notificationScheduler: NotificationScheduler
  @EnvironmentObject private var focusStore: FocusStore
  @EnvironmentObject private var marketNewsStore: MarketNewsStore
  @EnvironmentObject private var diagnosticsStore: DiagnosticsStore

  @State private var exportDocument = ConnectionsTextDocument()
  @State private var showExporter = false
  @State private var showImporter = false
  @State private var manualConnectionsText: String = ""
  @State private var statusMessage: String = ""
  @State private var urlRuleInput: String = ""
  @State private var marketSymbolsText: String = ""

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            heroPanel(width: proxy.size.width)
            controlBar

            settingsRow(width: proxy.size.width) {
              updatesPanel
            } right: {
              notionPanel
            }

            settingsRow(width: proxy.size.width) {
              googlePanel
            } right: {
              calendarPanel
            }

            settingsRow(width: proxy.size.width) {
              focusPanel
            } right: {
              marketPanel
            }

            mappingPanel
            importExportPanel
            diagnosticsPanel
          }
          .padding(.horizontal, horizontalPadding(for: proxy.size.width))
          .padding(.vertical, 28)
          .frame(maxWidth: 1_440)
          .frame(maxWidth: .infinity, alignment: .top)
        }
      }
      .background(WorkspaceBackground())
      .navigationTitle("Settings")
      .animation(.snappy(duration: 0.26), value: stageStore.pendingQueueCount)
      .animation(.snappy(duration: 0.26), value: updateStore.state)
      .animation(.snappy(duration: 0.26), value: googleAuthStore.isAuthenticated)
      .safeAreaInset(edge: .bottom) {
        if !footerMessage.isEmpty {
          Text(footerMessage)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.84))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspacePalette.panelBase.opacity(0.94))
        }
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
      marketSymbolsText = configStore.config.marketSymbols.joined(separator: ",")
      Task { await notificationScheduler.refreshAuthorizationStatus() }
    }
  }

  private var controlBar: some View {
    WorkspaceCommandBar(
      title: "Control",
      subtitle: "Keep update checks, pipeline sync, and transport actions within one pass."
    ) {
      Button("Check updates") {
        Task { await updateStore.checkForUpdates(userInitiated: true) }
      }
      .buttonStyle(.borderedProminent)
      .tint(.teal)

      Button("Sync Notion") {
        Task { await stageStore.syncFromNotion() }
      }
      .buttonStyle(.bordered)

      Button("Export") {
        do {
          let text = try configStore.exportConnectionsText()
          manualConnectionsText = text
          exportDocument = ConnectionsTextDocument(text: text)
          showExporter = true
        } catch {
          statusMessage = "Export preparation failed: \(error.localizedDescription)"
        }
      }
      .buttonStyle(.bordered)

      WorkspaceBadge(text: "\(activeFeedCount) feeds", tint: .blue)
    }
  }

  private func heroPanel(width: CGFloat) -> some View {
    WorkspacePanel(tint: .orange, padding: width >= 900 ? 28 : 22) {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 12) {
            Text("SYSTEM CONTROL")
              .font(.caption2.weight(.bold))
              .tracking(2.4)
              .foregroundStyle(Color.white.opacity(0.70))

            Text("Tune every connection,\nautomation, and guardrail.")
              .font(.system(size: width >= 1_120 ? 44 : 36, weight: .bold, design: .serif))
              .foregroundStyle(.white)
              .fixedSize(horizontal: false, vertical: true)

            Text("Settings now uses the same control-room language as the rest of the app: high-signal metrics first, then grouped panels for credentials, reminders, focus, and diagnostics.")
              .font(.subheadline)
              .foregroundStyle(Color.white.opacity(0.72))
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)

          VStack(alignment: .trailing, spacing: 10) {
            WorkspaceBadge(text: configStore.config.hasNotionCredentials ? "Notion ready" : "Notion missing", tint: configStore.config.hasNotionCredentials ? .green : .orange)
            WorkspaceBadge(text: googleAuthStore.isAuthenticated ? "Google live" : "Google idle", tint: googleAuthStore.isAuthenticated ? .teal : .orange)
          }
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
          settingsMetric(title: "Queue", value: "\(stageStore.pendingQueueCount)", detail: stageStore.pendingQueueCount == 0 ? "nothing pending" : "waiting sync ops", tint: .orange)
          settingsMetric(title: "Alerts", value: notificationMetricValue, detail: notificationMetricDetail, tint: .pink)
          settingsMetric(title: "Focus", value: focusStore.isEnabled ? "On" : "Off", detail: focusStore.isEnabled ? focusPhaseLabel : "guardrails idle", tint: .teal)
          settingsMetric(title: "Feeds", value: "\(activeFeedCount)", detail: activeFeedCount == 0 ? "no source active" : "calendar and market inputs", tint: .blue)
        }
      }
    }
  }

  private var updatesPanel: some View {
    WorkspacePanel(
      title: "Updates",
      subtitle: "Sparkle now checks the signed appcast on GitHub Pages and can install newer macOS builds in place.",
      tint: .teal
    ) {
      VStack(alignment: .leading, spacing: 18) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
          settingsMetric(title: "Installed", value: updateStore.currentVersion, detail: "marketing version", tint: .teal)
          settingsMetric(title: "Build", value: "\(updateStore.currentBuild)", detail: "local bundle build", tint: .orange)
          settingsMetric(title: "Channel", value: updateStore.channel.uppercased(), detail: "release stream", tint: .pink)
          settingsMetric(title: "Last check", value: updateStore.lastCheckLabel, detail: "latest Sparkle run", tint: .blue)
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
          .tint(.teal)
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
    }
  }

  private var notionPanel: some View {
    WorkspacePanel(
      title: "Notion and pipeline",
      subtitle: "Credentials, sync controls, offline queue, and external API keys live together.",
      tint: .blue
    ) {
      VStack(alignment: .leading, spacing: 18) {
        settingsTextField("Notion token", text: binding(for: \.notionToken), prompt: "Paste your integration token", monospaced: true)
        settingsTextField("Stages database", text: binding(for: \.notionDbId), prompt: "Database ID or URL", monospaced: true)
        settingsTextField("Todo database", text: binding(for: \.notionTodoDbId), prompt: "Database ID or URL", monospaced: true)

        HStack(spacing: 10) {
          Button("Test connection") {
            Task {
              statusMessage = await stageStore.testNotionConnection()
            }
          }
          .buttonStyle(.bordered)

          Button("Sync from Notion") {
            Task { await stageStore.syncFromNotion() }
          }
          .buttonStyle(.borderedProminent)
          .tint(.teal)

          Button("Push local to Notion") {
            Task { await stageStore.pushAllToNotion() }
          }
          .buttonStyle(.bordered)

          Button("Flush queue (\(stageStore.pendingQueueCount))") {
            Task { await stageStore.flushPendingOperations() }
          }
          .buttonStyle(.bordered)
        }

        settingsDivider

        settingsTextField("Banque de France API key", text: binding(for: \.bdfApiKey), prompt: "Optional market data key", monospaced: true)
        settingsTextField("Google Places API key", text: binding(for: \.googlePlacesApiKey), prompt: "Optional calendar enrichment key", monospaced: true)
        Toggle("Pipeline auto-import enabled", isOn: binding(for: \.pipelineAutoImportEnabled))
          .toggleStyle(.switch)

        if !stageStore.syncMessage.isEmpty {
          panelMessage(stageStore.syncMessage)
        }
      }
    }
  }

  private var googlePanel: some View {
    WorkspacePanel(
      title: "Google OAuth",
      subtitle: "Calendar auth, scope configuration, and default routing stay in a single auth surface.",
      tint: .teal
    ) {
      VStack(alignment: .leading, spacing: 18) {
        settingsTextField(
          "Client ID",
          text: binding(
            get: { configStore.config.googleOAuthClientID },
            set: { newValue in
              let previousClientID = configStore.config.googleOAuthClientID
              let previousRedirectURI = configStore.config.googleOAuthRedirectURI
              configStore.update { config in
                config.googleOAuthClientID = newValue
                if AppConfig.usesManagedGoogleOAuthRedirectURI(previousRedirectURI, clientID: previousClientID) {
                  config.googleOAuthRedirectURI = AppConfig.recommendedGoogleOAuthRedirectURI(for: newValue)
                }
              }
            }
          ),
          prompt: "OAuth client ID",
          monospaced: true
        )
        settingsTextField("Redirect URI", text: binding(for: \.googleOAuthRedirectURI), prompt: "Custom redirect URI", monospaced: true)
        panelHint(recommendedRedirectURIHint)
        settingsTextField(
          "Scopes",
          text: binding(
            get: { configStore.config.googleOAuthScopes.joined(separator: ",") },
            set: { value in
              let scopes = value
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
              configStore.update { $0.googleOAuthScopes = scopes }
            }
          ),
          prompt: "Comma-separated OAuth scopes",
          monospaced: true
        )

        HStack(spacing: 10) {
          Button(googleAuthStore.isAuthenticated ? "Reconnect Google" : "Connect Google") {
            Task { await googleAuthStore.signInInteractive() }
          }
          .buttonStyle(.borderedProminent)
          .tint(.teal)

          Button("Disconnect") {
            googleAuthStore.signOut()
          }
          .buttonStyle(.bordered)
          .disabled(!googleAuthStore.isAuthenticated)

          Button("Load calendars") {
            Task { await calendarStore.loadGoogleCalendars(force: true) }
          }
          .buttonStyle(.bordered)
        }

        if !calendarStore.googleCalendars.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            panelLabel("Default calendar")
            Picker("Default calendar", selection: binding(for: \.googleDefaultCalendarID)) {
              Text("Primary").tag("")
              ForEach(calendarStore.googleCalendars) { cal in
                Text(cal.name).tag(cal.id)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
          }
        }

        if !googleAuthStore.statusMessage.isEmpty {
          panelMessage(googleAuthStore.statusMessage)
        }
      }
    }
  }

  private var calendarPanel: some View {
    WorkspacePanel(
      title: "Calendar and reminders",
      subtitle: "iCal source, notification authorization, and offsets are grouped by event flow.",
      tint: .orange
    ) {
      VStack(alignment: .leading, spacing: 18) {
        settingsTextField("External iCal URL", text: binding(for: \.externalIcalUrl), prompt: "https://.../agenda/ical/...", monospaced: true)
        panelHint("The Calendar screen uses this feed when loading external events.")

        HStack(spacing: 10) {
          Button("Request notification permission") {
            Task { await notificationScheduler.requestAuthorization() }
          }
          .buttonStyle(.borderedProminent)
          .tint(.orange)

          Button("Reschedule reminders now") {
            Task {
              await notificationScheduler.scheduleEventReminders(
                events: calendarStore.events,
                prefs: configStore.config.reminderPrefs
              )
            }
          }
          .buttonStyle(.bordered)
        }

        settingsDivider

        settingsTextField("Default reminders", text: reminderBinding(\.defaultMinutes), prompt: "Ex: 30,10", monospaced: true)
        settingsTextField("Meeting reminders", text: reminderBinding(\.meetingMinutes), prompt: "Ex: 60,15", monospaced: true)
        settingsTextField("Interview reminders", text: reminderBinding(\.interviewMinutes), prompt: "Ex: 1440,120,30", monospaced: true)
        settingsTextField("Deadline reminders", text: reminderBinding(\.deadlineMinutes), prompt: "Ex: 2880,1440,120", monospaced: true)

        if !notificationScheduler.lastStatusMessage.isEmpty {
          panelMessage(notificationScheduler.lastStatusMessage)
        }
      }
    }
  }

  private var focusPanel: some View {
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
              configStore.update { $0.focusModeEnabled = enabled }
              focusStore.setEnabled(enabled)
            }
          )
        )
        .toggleStyle(.switch)

        Stepper(
          "Pomodoro work: \(configStore.config.pomodoroWorkMinutes)m",
          value: binding(for: \.pomodoroWorkMinutes),
          in: 5 ... 120
        )
        Stepper(
          "Pomodoro break: \(configStore.config.pomodoroBreakMinutes)m",
          value: binding(for: \.pomodoroBreakMinutes),
          in: 1 ... 60
        )

        HStack(spacing: 10) {
          TextField("Add blocked rule (ex: youtube.com)", text: $urlRuleInput)
            .textFieldStyle(.roundedBorder)
            .plainTextInputBehavior()
          Button("Add") {
            let clean = urlRuleInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            if !configStore.config.urlBlockerRules.contains(clean) {
              configStore.update { $0.urlBlockerRules.append(clean) }
            }
            urlRuleInput = ""
          }
          .buttonStyle(.bordered)
        }

        if configStore.config.urlBlockerRules.isEmpty {
          panelHint("No blocked host configured.")
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

        panelMessage("Phase: \(focusStore.phase.rawValue) | Remaining: \(max(0, focusStore.remainingSeconds / 60))m")
      }
    }
  }

  private var marketPanel: some View {
    WorkspacePanel(
      title: "Markets and news",
      subtitle: "Signal toggles and ticker universe stay in one panel instead of being buried in a long form.",
      tint: .blue
    ) {
      VStack(alignment: .leading, spacing: 18) {
        Toggle("Enable news", isOn: binding(for: \.newsEnabled))
          .toggleStyle(.switch)
        Toggle("Enable markets", isOn: binding(for: \.marketsEnabled))
          .toggleStyle(.switch)

        settingsTextField("Market symbols", text: $marketSymbolsText, prompt: "^GSPC, EURUSD=X, BTC-USD", monospaced: true)
          .onChange(of: marketSymbolsText) { value in
            let symbols = value
              .split(separator: ",")
              .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty }
            configStore.update { $0.marketSymbols = symbols }
          }

        Button("Refresh news + markets") {
          Task { await marketNewsStore.refreshAll() }
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
      }
    }
  }

  private var mappingPanel: some View {
    WorkspacePanel(
      title: "Mapping and limits",
      subtitle: "Notion field names, status values, and WIP limits are grouped as one schema panel.",
      tint: .teal
    ) {
      VStack(alignment: .leading, spacing: 18) {
        settingsTextField("Job title field", text: mapBinding(\.jobTitle, fallback: "Job Title"), prompt: "Job Title")
        settingsTextField("Company field", text: mapBinding(\.company, fallback: "Entreprise"), prompt: "Entreprise")
        settingsTextField("Location field", text: mapBinding(\.location, fallback: "Lieu"), prompt: "Lieu")
        settingsTextField("URL field", text: mapBinding(\.url, fallback: "lien offre"), prompt: "lien offre")
        settingsTextField("Status field", text: mapBinding(\.status, fallback: "Status"), prompt: "Status")
        settingsTextField("Notes field", text: mapBinding(\.notes, fallback: "Notes"), prompt: "Notes")
        settingsTextField("Close date field", text: mapBinding(\.closeDate, fallback: "Date de fermeture"), prompt: "Date de fermeture")

        settingsDivider

        settingsTextField("Open status", text: statusMapBinding(\.open, fallback: "Ouvert"), prompt: "Ouvert")
        settingsTextField("Applied status", text: statusMapBinding(\.applied, fallback: "Candidature"), prompt: "Candidature")
        settingsTextField("Interview status", text: statusMapBinding(\.interview, fallback: "Entretien"), prompt: "Entretien")
        settingsTextField("Rejected status", text: statusMapBinding(\.rejected, fallback: "Refuse"), prompt: "Refuse")

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
      tint: .orange
    ) {
      VStack(alignment: .leading, spacing: 18) {
        Text("This export contains sensitive data, including tokens and API keys.")
          .font(.caption)
          .foregroundStyle(Color.orange.opacity(0.95))

        HStack(spacing: 10) {
          Button("Export .txt") {
            do {
              let text = try configStore.exportConnectionsText()
              manualConnectionsText = text
              exportDocument = ConnectionsTextDocument(text: text)
              showExporter = true
            } catch {
              statusMessage = "Export preparation failed: \(error.localizedDescription)"
            }
          }
          .buttonStyle(.borderedProminent)
          .tint(.teal)

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
              marketSymbolsText = configStore.config.marketSymbols.joined(separator: ",")
              googleAuthStore.refreshAuthState()
              calendarStore.selectedCalendarIDs = Set(configStore.config.googleSelectedCalendarIDs)
              statusMessage = "Connections imported from text."
            } catch {
              statusMessage = "Import text failed: \(error.localizedDescription)"
            }
          }
          .buttonStyle(.bordered)

          Button("Refresh text from current config") {
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
      tint: .pink
    ) {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Text("Queue offline: \(stageStore.pendingQueueCount)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
          Spacer()
          Button("Clear logs") { diagnosticsStore.clear() }
            .buttonStyle(.bordered)
        }

        if stageStore.pendingQueueCount > 0 {
          VStack(alignment: .leading, spacing: 8) {
            panelLabel("Pending operations")
            ForEach(stageStore.pendingOperations.prefix(20)) { op in
              HStack {
                Text(op.kind.rawValue)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.white)
                Spacer()
                Text("retry: \(op.retryCount)")
                  .font(.caption2)
                  .foregroundStyle(Color.white.opacity(0.62))
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 10)
              .workspaceInteractiveSurface(cornerRadius: 16, tint: .orange, raised: false)
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
              .workspaceInteractiveSurface(cornerRadius: 18, tint: .pink, raised: false)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func settingsRow<Left: View, Right: View>(
    width: CGFloat,
    @ViewBuilder left: () -> Left,
    @ViewBuilder right: () -> Right
  ) -> some View {
    if width >= 1_120 {
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
      .workspaceInteractiveSurface(cornerRadius: 16, tint: .teal, raised: false)
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

  private var recommendedRedirectURIHint: String {
    let recommended = AppConfig.recommendedGoogleOAuthRedirectURI(for: configStore.config.googleOAuthClientID)
    if recommended.isEmpty {
      return "Enter a valid Google OAuth client ID to derive the recommended callback."
    }
    return "Recommended for this client ID: \(recommended)"
  }

  private var focusPhaseLabel: String {
    switch focusStore.phase {
    case .idle:
      return "idle"
    case .work:
      return "work sprint"
    case .shortBreak:
      return "short break"
    }
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

  private func horizontalPadding(for width: CGFloat) -> CGFloat {
    width >= 900 ? 28 : 18
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
      marketSymbolsText = configStore.config.marketSymbols.joined(separator: ",")
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

  private func binding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<String> {
    Binding(
      get: get,
      set: set
    )
  }

  private func mapBinding(_ keyPath: WritableKeyPath<NotionFieldMap, String>, fallback: String) -> Binding<String> {
    binding(
      get: { configStore.config.notionFieldMap[keyPath: keyPath] },
      set: { newValue in
        configStore.update { config in
          let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
          config.notionFieldMap[keyPath: keyPath] = clean.isEmpty ? fallback : clean
        }
      }
    )
  }

  private func reminderBinding(_ keyPath: WritableKeyPath<ReminderPrefs, [Int]>) -> Binding<String> {
    binding(
      get: {
        configStore.config.reminderPrefs[keyPath: keyPath]
          .map(String.init)
          .joined(separator: ",")
      },
      set: { newValue in
        let list = newValue
          .split(separator: ",")
          .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
          .filter { $0 > 0 }
        configStore.update { config in
          config.reminderPrefs[keyPath: keyPath] = list.isEmpty ? ReminderPrefs.defaults[keyPath: keyPath] : list
        }
      }
    )
  }

  private func statusMapBinding(_ keyPath: WritableKeyPath<NotionStatusMap, String>, fallback: String) -> Binding<String> {
    binding(
      get: { configStore.config.notionStatusMap[keyPath: keyPath] },
      set: { newValue in
        configStore.update { config in
          let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
          config.notionStatusMap[keyPath: keyPath] = clean.isEmpty ? fallback : clean
        }
      }
    )
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
