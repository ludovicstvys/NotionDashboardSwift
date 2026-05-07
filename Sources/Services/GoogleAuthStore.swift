import Foundation
import SwiftUI
import CryptoKit
import Network

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum GoogleAuthError: LocalizedError {
  case missingConfiguration
  case unableToBuildURL
  case callbackMissing
  case callbackMissingCode
  case listenerFailed(String)
  case listenerTimedOut
  case stateMismatch
  case tokenExchangeFailed(String)
  case refreshTokenMissing

  var errorDescription: String? {
    switch self {
    case .missingConfiguration:
      return "Google OAuth client ID or client secret is missing."
    case .unableToBuildURL:
      return "Unable to build Google OAuth URL."
    case .callbackMissing:
      return "Google OAuth callback URL missing."
    case .callbackMissingCode:
      return "Google OAuth callback does not contain code."
    case let .listenerFailed(message):
      return "Google OAuth listener failed: \(message)"
    case .listenerTimedOut:
      return "Google OAuth listener timed out."
    case .stateMismatch:
      return "Google OAuth callback state did not match the request."
    case let .tokenExchangeFailed(message):
      return "Google token exchange failed: \(message)"
    case .refreshTokenMissing:
      return "Google refresh token is missing."
    }
  }
}

enum GoogleConnectionState: Equatable {
  case notConfigured
  case disconnected
  case connecting
  case connected(tokenExpiresAt: Date?)
  case error(String)

  var isConnected: Bool {
    if case .connected = self { return true }
    return false
  }

  var label: String {
    switch self {
    case .notConfigured:
      return "Not configured"
    case .disconnected:
      return "Not connected"
    case .connecting:
      return "Connecting..."
    case let .connected(tokenExpiresAt):
      guard let tokenExpiresAt else { return "Google connected" }
      return "Google connected until \(tokenExpiresAt.shortDateTime)"
    case let .error(message):
      return message
    }
  }
}

struct GoogleTokenResponse: Codable {
  var accessToken: String
  var expiresIn: Int
  var refreshToken: String?
  var scope: String?
  var tokenType: String?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
    case scope
    case tokenType = "token_type"
  }
}

@MainActor
final class GoogleAuthStore: NSObject, ObservableObject {
  @Published private(set) var isAuthenticated: Bool = false
  @Published private(set) var statusMessage: String = "Not connected"
  @Published private(set) var activeScopes: [String] = []
  @Published private(set) var connectionState: GoogleConnectionState = .disconnected

  private weak var configStore: ConfigStore?
  private weak var diagnostics: DiagnosticsStore?

  init(configStore: ConfigStore, diagnostics: DiagnosticsStore?) {
    self.configStore = configStore
    self.diagnostics = diagnostics
    super.init()
    refreshAuthState()
  }

  func refreshAuthState() {
    guard let configStore else { return }
    let clientID = configStore.config.googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientID.isEmpty else {
      isAuthenticated = false
      connectionState = .notConfigured
      statusMessage = connectionState.label
      activeScopes = configStore.config.googleOAuthScopes
      return
    }

    let token = configStore.config.googleAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let refreshToken = configStore.config.googleRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let expiry = configStore.config.googleTokenExpiration ?? .distantPast
    isAuthenticated = (!token.isEmpty && expiry > Date().addingTimeInterval(30)) || !refreshToken.isEmpty
    if isAuthenticated {
      let visibleExpiry = expiry > Date().addingTimeInterval(30) ? expiry : nil
      connectionState = .connected(tokenExpiresAt: visibleExpiry)
    } else {
      connectionState = .disconnected
    }
    statusMessage = connectionState.label
    activeScopes = configStore.config.googleOAuthScopes
  }

  func signOut() {
    guard let configStore else { return }
    configStore.update { config in
      config.googleAccessToken = ""
      config.googleRefreshToken = ""
      config.googleTokenExpiration = nil
    }
    refreshAuthState()
    diagnostics?.log(category: "google-auth", message: "Google signed out.")
  }

  func signInInteractive() async -> Bool {
    connectionState = .connecting
    statusMessage = connectionState.label
    do {
      try await startOAuthFlow()
      refreshAuthState()
      diagnostics?.log(category: "google-auth", message: "Google OAuth completed.")
      return true
    } catch {
      connectionState = .error(error.localizedDescription)
      statusMessage = error.localizedDescription
      diagnostics?.log(
        severity: .error,
        category: "google-auth",
        message: "Google OAuth failed.",
        metadata: ["error": error.localizedDescription]
      )
      return false
    }
  }

  func validAccessToken() async throws -> String {
    guard let configStore else { throw GoogleAuthError.missingConfiguration }
    let now = Date()
    let access = configStore.config.googleAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    if !access.isEmpty, (configStore.config.googleTokenExpiration ?? .distantPast) > now.addingTimeInterval(60) {
      return access
    }

    let refresh = configStore.config.googleRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !refresh.isEmpty else { throw GoogleAuthError.refreshTokenMissing }
    let token = try await refreshToken(
      clientID: configStore.config.googleOAuthClientID,
      clientSecret: configStore.config.googleOAuthClientSecret,
      refreshToken: refresh
    )
    configStore.update { config in
      config.googleAccessToken = token.accessToken
      if let nextRefresh = token.refreshToken, !nextRefresh.isEmpty {
        config.googleRefreshToken = nextRefresh
      }
      config.googleTokenExpiration = Date().addingTimeInterval(TimeInterval(token.expiresIn))
    }
    refreshAuthState()
    return token.accessToken
  }

  var connectionSummary: String {
    connectionState.label
  }

  var hasConfiguredOAuth: Bool {
    connectionState != .notConfigured
  }

  private func startOAuthFlow() async throws {
    guard let configStore else { throw GoogleAuthError.missingConfiguration }
    let clientID = configStore.config.googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    let clientSecret = configStore.config.googleOAuthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientID.isEmpty, !clientSecret.isEmpty else {
      throw GoogleAuthError.missingConfiguration
    }

    let scopes = configStore.config.googleOAuthScopes
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let scopeParam = scopes.isEmpty
      ? "https://www.googleapis.com/auth/calendar.readonly"
      : scopes.joined(separator: " ")

    let codeVerifier = randomCodeVerifier()
    let codeChallenge = codeVerifier.codeChallengeS256
    let state = randomCodeVerifier()
    let listener = try makeLoopbackListener()
    let redirectURI = listener.redirectURI.absoluteString

    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
    components?.queryItems = [
      .init(name: "response_type", value: "code"),
      .init(name: "client_id", value: clientID),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "scope", value: scopeParam),
      .init(name: "access_type", value: "offline"),
      .init(name: "prompt", value: "consent"),
      .init(name: "include_granted_scopes", value: "true"),
      .init(name: "code_challenge", value: codeChallenge),
      .init(name: "code_challenge_method", value: "S256"),
      .init(name: "state", value: state),
    ]
    guard let authURL = components?.url else {
      throw GoogleAuthError.unableToBuildURL
    }

    let callbackTask = Task {
      try await listener.waitForCallback(timeout: 180)
    }

    #if os(macOS)
    NSWorkspace.shared.open(authURL)
    #else
    await UIApplication.shared.open(authURL)
    #endif

    let callbackURL = try await callbackTask.value

    guard
      let parts = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
      let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
      !code.isEmpty
    else {
      throw GoogleAuthError.callbackMissingCode
    }
    guard parts.queryItems?.first(where: { $0.name == "state" })?.value == state else {
      throw GoogleAuthError.stateMismatch
    }

    let token = try await exchangeCodeForToken(
      clientID: clientID,
      clientSecret: clientSecret,
      code: code,
      redirectURI: redirectURI,
      codeVerifier: codeVerifier
    )
    configStore.update { config in
      config.googleAccessToken = token.accessToken
      if let refresh = token.refreshToken {
        config.googleRefreshToken = refresh
      }
      config.googleTokenExpiration = Date().addingTimeInterval(TimeInterval(token.expiresIn))
      config.googleOAuthScopes = scopes
    }
    statusMessage = "Google connected."
  }

  private func exchangeCodeForToken(
    clientID: String,
    clientSecret: String,
    code: String,
    redirectURI: String,
    codeVerifier: String
  ) async throws -> GoogleTokenResponse {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let params = [
      "code": code,
      "client_id": clientID,
      "client_secret": clientSecret,
      "redirect_uri": redirectURI,
      "grant_type": "authorization_code",
      "code_verifier": codeVerifier,
    ]
    request.httpBody = params
      .map { key, value in
        "\(key)=\(value.urlQueryEncoded)"
      }
      .joined(separator: "&")
      .data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw GoogleAuthError.tokenExchangeFailed("Invalid HTTP response.")
    }
    if !(200...299).contains(http.statusCode) {
      let payload = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw GoogleAuthError.tokenExchangeFailed(payload)
    }

    let decoder = JSONDecoder()
    do {
      return try decoder.decode(GoogleTokenResponse.self, from: data)
    } catch {
      throw GoogleAuthError.tokenExchangeFailed("Cannot decode token response.")
    }
  }

  private func refreshToken(clientID: String, clientSecret: String, refreshToken: String) async throws -> GoogleTokenResponse {
    let cleanClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanClientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanClientID.isEmpty, !cleanClientSecret.isEmpty else { throw GoogleAuthError.missingConfiguration }
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let params = [
      "client_id": cleanClientID,
      "client_secret": cleanClientSecret,
      "refresh_token": refreshToken,
      "grant_type": "refresh_token",
    ]
    request.httpBody = params
      .map { key, value in
        "\(key)=\(value.urlQueryEncoded)"
      }
      .joined(separator: "&")
      .data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw GoogleAuthError.tokenExchangeFailed("Invalid HTTP response.")
    }
    if !(200...299).contains(http.statusCode) {
      let payload = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw GoogleAuthError.tokenExchangeFailed(payload)
    }
    let decoder = JSONDecoder()
    var token = try decoder.decode(GoogleTokenResponse.self, from: data)
    if token.refreshToken == nil {
      token.refreshToken = refreshToken
    }
    return token
  }

  private func randomCodeVerifier() -> String {
    let data = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
    return data.base64URLEncodedString
  }

  private func makeLoopbackListener() throws -> LoopbackOAuthListener {
    try LoopbackOAuthListener()
  }
}

private extension String {
  var urlQueryEncoded: String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
  }

  var codeChallengeS256: String {
    let digest = SHA256.hash(data: Data(utf8))
    return Data(digest).base64URLEncodedString
  }
}

private extension Data {
  var base64URLEncodedString: String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

private final class LoopbackOAuthListener {
  let redirectURI: URL
  private let listener: NWListener
  private var callbackContinuation: CheckedContinuation<URL, Error>?
  private var pendingCallbackResult: Result<URL, Error>?
  private var didFinish = false

  init() throws {
    let port = Self.pickPort()
    guard let redirectURI = URL(string: "http://127.0.0.1:\(port)/oauth2redirect") else {
      throw GoogleAuthError.missingConfiguration
    }
    self.redirectURI = redirectURI

    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true
    do {
      listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port)))
    } catch {
      throw GoogleAuthError.listenerFailed(error.localizedDescription)
    }

    listener.newConnectionHandler = { [weak self] connection in
      self?.handle(connection: connection)
    }
    listener.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed(let error):
        self?.finish(throwing: GoogleAuthError.listenerFailed(error.localizedDescription))
      default:
        break
      }
    }
    listener.start(queue: .main)
  }

  func waitForCallback(timeout: TimeInterval) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async { [weak self] in
        guard let self else {
          continuation.resume(throwing: GoogleAuthError.listenerFailed("Listener deallocated."))
          return
        }

        if let result = self.pendingCallbackResult {
          self.pendingCallbackResult = nil
          continuation.resume(with: result)
          return
        }

        if self.didFinish {
          continuation.resume(throwing: GoogleAuthError.listenerFailed("Callback already completed."))
          return
        }

        self.callbackContinuation = continuation
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
          self?.finish(throwing: GoogleAuthError.listenerTimedOut)
        }
      }
    }
  }

  private func handle(connection: NWConnection) {
    connection.start(queue: .main)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
      guard let self else { return }
      if let error {
        self.finish(throwing: GoogleAuthError.listenerFailed(error.localizedDescription))
        connection.cancel()
        return
      }

      let requestText = String(data: data ?? Data(), encoding: .utf8) ?? ""
      guard let firstLine = requestText.split(separator: "\r\n").first else {
        self.finish(throwing: GoogleAuthError.callbackMissing)
        connection.cancel()
        return
      }

      let parts = firstLine.split(separator: " ")
      guard parts.count >= 2 else {
        self.finish(throwing: GoogleAuthError.callbackMissing)
        connection.cancel()
        return
      }

      let path = String(parts[1])
      let callbackURL = URL(string: path, relativeTo: self.redirectURI)?.absoluteURL ?? self.redirectURI
      self.respond(connection: connection, body: self.htmlResponse) { [weak self] sendError in
        guard let self else {
          connection.cancel()
          return
        }
        if let sendError {
          self.finish(throwing: GoogleAuthError.listenerFailed(sendError.localizedDescription))
        } else {
          self.finish(returning: callbackURL)
        }
        connection.cancel()
      }

      if isComplete {
        return
      }
    }
  }

  private func respond(connection: NWConnection, body: String, completion: @escaping (NWError?) -> Void) {
    let response = [
      "HTTP/1.1 200 OK",
      "Content-Type: text/html; charset=utf-8",
      "Content-Length: \(body.utf8.count)",
      "Connection: close",
      "",
      body,
    ].joined(separator: "\r\n")
    let data = response.data(using: .utf8) ?? Data()
    connection.send(content: data, isComplete: true, completion: .contentProcessed(completion))
  }

  private func finish(returning url: URL) {
    finish(with: .success(url))
  }

  private func finish(throwing error: Error) {
    finish(with: .failure(error))
  }

  private func finish(with result: Result<URL, Error>) {
    guard !didFinish else { return }
    didFinish = true
    listener.cancel()

    guard let continuation = callbackContinuation else {
      pendingCallbackResult = result
      return
    }

    callbackContinuation = nil
    continuation.resume(with: result)
  }

  private var htmlResponse: String {
    """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>Dashboard sign-in</title></head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 32px;">
    <h2>Google sign-in complete</h2>
    <p>You can close this tab and return to the app.</p>
    </body></html>
    """
  }

  private static func pickPort() -> Int {
    Int.random(in: 49152...65535)
  }
}
