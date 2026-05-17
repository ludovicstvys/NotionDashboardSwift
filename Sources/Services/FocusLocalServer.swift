import Foundation
import Network

// Localhost-only HTTP control surface for the Focus/Pomodoro browser extension companion.
// Threat model: binds 127.0.0.1 only (no LAN exposure), no auth — relies on loopback isolation.
// CORS headers are permissive because only same-host clients (browser extension) can reach it.
// Do NOT bind to 0.0.0.0 or add LAN discovery without introducing token auth.
@MainActor
final class FocusLocalServer {
  static let port: UInt16 = 49172

  private let focusStore: FocusStore
  private let configStore: ConfigStore
  private weak var diagnostics: DiagnosticsStore?
  private var listener: NWListener?

  init(focusStore: FocusStore, configStore: ConfigStore, diagnostics: DiagnosticsStore?) {
    self.focusStore = focusStore
    self.configStore = configStore
    self.diagnostics = diagnostics
    start()
  }

  deinit {
    listener?.cancel()
  }

  private func start() {
    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true

    do {
      let port = NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(Self.port))
      let listener = try NWListener(using: params, on: port)
      listener.newConnectionHandler = { [weak self] connection in
        guard FocusLocalServer.isLoopback(endpoint: connection.currentPath?.remoteEndpoint) else {
          connection.cancel()
          return
        }
        Task { @MainActor [weak self] in
          self?.handle(connection: connection)
        }
      }
      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor [weak self] in
          self?.handle(listenerState: state)
        }
      }
      listener.start(queue: .main)
      self.listener = listener
    } catch {
      diagnostics?.log(
        severity: .warning,
        category: "focus",
        message: "Focus local server failed to start.",
        metadata: ["error": error.localizedDescription]
      )
    }
  }

  nonisolated private static func isLoopback(endpoint: NWEndpoint?) -> Bool {
    guard let endpoint else { return true }
    if case let .hostPort(host, _) = endpoint {
      switch host {
      case .ipv4(let addr):
        return addr.isLoopback
      case .ipv6(let addr):
        return addr.isLoopback
      case .name(let name, _):
        return name == "localhost" || name == "127.0.0.1" || name == "::1"
      @unknown default:
        return false
      }
    }
    return false
  }

  private func handle(listenerState state: NWListener.State) {
    switch state {
    case .ready:
      diagnostics?.log(
        category: "focus",
        message: "Focus local server started.",
        metadata: ["url": "http://127.0.0.1:\(Self.port)/focus/state"]
      )
    case .failed(let error):
      diagnostics?.log(
        severity: .warning,
        category: "focus",
        message: "Focus local server failed.",
        metadata: ["error": error.localizedDescription]
      )
    default:
      break
    }
  }

  private func handle(connection: NWConnection) {
    connection.start(queue: .main)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
      Task { @MainActor [weak self] in
        guard let self else {
          connection.cancel()
          return
        }
        if let error {
          self.respond(
            connection: connection,
            status: 500,
            contentType: "application/json",
            body: self.jsonError("Connection error: \(error.localizedDescription)")
          )
          return
        }

        let request = HTTPFocusRequest(data: data ?? Data())
        let response = self.route(request)
        self.respond(
          connection: connection,
          status: response.status,
          contentType: response.contentType,
          body: response.body,
          extraHeaders: response.extraHeaders
        )
      }
    }
  }

  private func route(_ request: HTTPFocusRequest) -> HTTPFocusResponse {
    if request.method == "OPTIONS" {
      return .empty(status: 204)
    }

    switch (request.method, request.path) {
    case ("GET", "/health"):
      return .json(#"{"ok":true,"service":"NotionDashboard Focus"}"#)
    case ("GET", "/focus/state"):
      return .json(focusStateJSON())
    case ("POST", "/focus/start"):
      focusStore.startSession()
      return .json(focusStateJSON())
    case ("POST", "/focus/pause"):
      focusStore.pauseSession()
      return .json(focusStateJSON())
    case ("POST", "/focus/resume"):
      focusStore.resumeSession()
      return .json(focusStateJSON())
    case ("POST", "/focus/toggle-pause"):
      focusStore.togglePause()
      return .json(focusStateJSON())
    case ("POST", "/focus/stop"):
      focusStore.stopSession()
      return .json(focusStateJSON())
    default:
      return .json(jsonError("Unknown endpoint."), status: 404)
    }
  }

  private func focusStateJSON() -> String {
    let totalSeconds = currentTotalSeconds
    let elapsedSeconds = max(0, totalSeconds - focusStore.remainingSeconds)
    let progress = totalSeconds > 0 ? min(1, Double(elapsedSeconds) / Double(totalSeconds)) : 0
    let payload = FocusLocalStatePayload(
      isEnabled: focusStore.isEnabled,
      isPaused: focusStore.isPaused,
      phase: focusStore.phase.rawValue,
      summary: focusStore.focusSummary,
      remainingSeconds: max(0, focusStore.remainingSeconds),
      totalSeconds: totalSeconds,
      progress: progress,
      blockedRules: configStore.config.urlBlockerRules,
      serverPort: Self.port
    )

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(payload)
      return String(data: data, encoding: .utf8) ?? jsonError("Unable to encode focus state.")
    } catch {
      return jsonError(error.localizedDescription)
    }
  }

  private var currentTotalSeconds: Int {
    switch focusStore.phase {
    case .shortBreak:
      return max(1, configStore.config.pomodoroBreakMinutes) * 60
    case .idle, .work:
      return max(1, configStore.config.pomodoroWorkMinutes) * 60
    }
  }

  private func respond(
    connection: NWConnection,
    status: Int,
    contentType: String,
    body: String,
    extraHeaders: [String: String] = [:]
  ) {
    let statusText = HTTPFocusResponse.statusText(for: status)
    let baseHeaders: [String: String] = [
      "Content-Type": contentType,
      "Content-Length": "\(body.utf8.count)",
      "Connection": "close",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    ]
    let headers = baseHeaders.merging(extraHeaders) { _, new in new }
    let headerLines = headers.map { "\($0.key): \($0.value)" }.sorted()
    let response = (["HTTP/1.1 \(status) \(statusText)"] + headerLines + ["", body])
      .joined(separator: "\r\n")
    let data = response.data(using: .utf8) ?? Data()
    connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in
      connection.cancel()
    })
  }

  private func jsonError(_ message: String) -> String {
    let escaped = message
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return #"{"error":"\#(escaped)"}"#
  }
}

private struct FocusLocalStatePayload: Encodable {
  let isEnabled: Bool
  let isPaused: Bool
  let phase: String
  let summary: String
  let remainingSeconds: Int
  let totalSeconds: Int
  let progress: Double
  let blockedRules: [String]
  let serverPort: UInt16
}

private struct HTTPFocusRequest {
  let method: String
  let path: String

  init(data: Data) {
    let text = String(data: data, encoding: .utf8) ?? ""
    let firstLine = text.components(separatedBy: "\r\n").first ?? ""
    let parts = firstLine.split(separator: " ")
    method = parts.first.map { String($0).uppercased() } ?? ""
    let rawPath = parts.dropFirst().first.map(String.init) ?? "/"
    path = URLComponents(string: rawPath)?.path ?? rawPath
  }
}

private struct HTTPFocusResponse {
  let status: Int
  let contentType: String
  let body: String
  let extraHeaders: [String: String]

  static func json(_ body: String, status: Int = 200) -> HTTPFocusResponse {
    HTTPFocusResponse(status: status, contentType: "application/json; charset=utf-8", body: body, extraHeaders: [:])
  }

  static func empty(status: Int) -> HTTPFocusResponse {
    HTTPFocusResponse(status: status, contentType: "text/plain; charset=utf-8", body: "", extraHeaders: [:])
  }

  static func statusText(for status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 204: return "No Content"
    case 404: return "Not Found"
    case 500: return "Internal Server Error"
    default: return "OK"
    }
  }
}
