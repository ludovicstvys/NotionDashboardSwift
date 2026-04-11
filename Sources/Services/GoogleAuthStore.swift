import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum GoogleAuthError: LocalizedError {
  case missingConfiguration
  case unableToBuildURL
  case sessionStartFailed
  case callbackMissing
  case callbackMissingCode
  case tokenExchangeFailed(String)
  case refreshTokenMissing

  var errorDescription: String? {
    switch self {
    case .missingConfiguration:
      return "Google OAuth client ID/redirect URI is missing."
    case .unableToBuildURL:
      return "Unable to build Google OAuth URL."
    case .sessionStartFailed:
      return "Unable to start Google OAuth session."
    case .callbackMissing:
      return "Google OAuth callback URL missing."
    case .callbackMissingCode:
      return "Google OAuth callback does not contain code."
    case let .tokenExchangeFailed(message):
      return "Google token exchange failed: \(message)"
    case .refreshTokenMissing:
      return "Google refresh token is missing."
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

  private weak var configStore: ConfigStore?
  private weak var diagnostics: DiagnosticsStore?
  private var authSession: ASWebAuthenticationSession?

  init(configStore: ConfigStore, diagnostics: DiagnosticsStore?) {
    self.configStore = configStore
    self.diagnostics = diagnostics
    super.init()
    refreshAuthState()
  }

  func refreshAuthState() {
    guard let configStore else { return }
    let token = configStore.config.googleAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let expiry = configStore.config.googleTokenExpiration ?? .distantPast
    isAuthenticated = !token.isEmpty && expiry > Date().addingTimeInterval(30)
    if isAuthenticated {
      statusMessage = "Google connected."
    } else {
      statusMessage = "Not connected"
    }
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

  func signInInteractive() async {
    do {
      try await startOAuthFlow()
      refreshAuthState()
      diagnostics?.log(category: "google-auth", message: "Google OAuth completed.")
    } catch {
      statusMessage = error.localizedDescription
      diagnostics?.log(
        severity: .error,
        category: "google-auth",
        message: "Google OAuth failed.",
        metadata: ["error": error.localizedDescription]
      )
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

  private func startOAuthFlow() async throws {
    guard let configStore else { throw GoogleAuthError.missingConfiguration }
    let clientID = configStore.config.googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    let redirectURI = configStore.config.googleOAuthRedirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientID.isEmpty, !redirectURI.isEmpty else {
      throw GoogleAuthError.missingConfiguration
    }

    let scopes = configStore.config.googleOAuthScopes
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let scopeParam = scopes.isEmpty
      ? "https://www.googleapis.com/auth/calendar.readonly"
      : scopes.joined(separator: " ")

    let codeVerifier = randomCodeVerifier()
    let codeChallenge = codeVerifier.codeChallengeS256
    guard let callbackScheme = URL(string: redirectURI)?.scheme else {
      throw GoogleAuthError.missingConfiguration
    }

    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
    components?.queryItems = [
      .init(name: "response_type", value: "code"),
      .init(name: "client_id", value: clientID),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "scope", value: scopeParam),
      .init(name: "access_type", value: "offline"),
      .init(name: "prompt", value: "consent"),
      .init(name: "code_challenge", value: codeChallenge),
      .init(name: "code_challenge_method", value: "S256"),
    ]
    guard let authURL = components?.url else {
      throw GoogleAuthError.unableToBuildURL
    }

    let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: authURL,
        callbackURLScheme: callbackScheme
      ) { callbackURL, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let callbackURL else {
          continuation.resume(throwing: GoogleAuthError.callbackMissing)
          return
        }
        continuation.resume(returning: callbackURL)
      }
      session.prefersEphemeralWebBrowserSession = true
      session.presentationContextProvider = self
      self.authSession = session
      guard session.start() else {
        continuation.resume(throwing: GoogleAuthError.sessionStartFailed)
        return
      }
    }

    guard
      let parts = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
      let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
      !code.isEmpty
    else {
      throw GoogleAuthError.callbackMissingCode
    }

    let token = try await exchangeCodeForToken(
      clientID: clientID,
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

  private func refreshToken(clientID: String, refreshToken: String) async throws -> GoogleTokenResponse {
    let cleanClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanClientID.isEmpty else { throw GoogleAuthError.missingConfiguration }
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let params = [
      "client_id": cleanClientID,
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
}

extension GoogleAuthStore: ASWebAuthenticationPresentationContextProviding {
  nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
#if os(iOS)
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let keyWindow = scenes.flatMap(\.windows).first { $0.isKeyWindow }
      return keyWindow ?? ASPresentationAnchor(frame: .zero)
#elseif os(macOS)
      return NSApplication.shared.windows.first { $0.isKeyWindow } ??
        ASPresentationAnchor(
          contentRect: .init(x: 0, y: 0, width: 1, height: 1),
          styleMask: [.titled],
          backing: .buffered,
          defer: false
        )
#endif
    }
  }
}

private extension String {
  var urlQueryEncoded: String {
    addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
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
