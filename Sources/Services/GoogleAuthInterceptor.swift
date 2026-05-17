import Foundation

// Injects bearer token on outgoing requests; on 401 forces a token refresh and
// signals APIClient to retry the request once.
final class GoogleAuthInterceptor: APIInterceptor, @unchecked Sendable {
  private let authStore: GoogleAuthStore
  private let lock = NSLock()
  private var inFlightRefresh: Task<String, Error>?

  init(authStore: GoogleAuthStore) {
    self.authStore = authStore
  }

  func adapt(_ request: APIRequest) async throws -> APIRequest {
    let token = try await currentAccessToken(forceRefresh: false)
    var next = request
    next.headers["Authorization"] = "Bearer \(token)"
    return next
  }

  func handleResponse(statusCode: Int, body: Data, originalRequest: APIRequest) async -> Bool {
    guard statusCode == 401 else { return false }
    do {
      _ = try await currentAccessToken(forceRefresh: true)
      return true
    } catch {
      return false
    }
  }

  private func currentAccessToken(forceRefresh: Bool) async throws -> String {
    if forceRefresh {
      lock.lock()
      let existing = inFlightRefresh
      lock.unlock()
      if let existing {
        return try await existing.value
      }
      let task = Task<String, Error> {
        defer {
          lock.lock()
          inFlightRefresh = nil
          lock.unlock()
        }
        return try await authStore.validAccessToken()
      }
      lock.lock()
      inFlightRefresh = task
      lock.unlock()
      return try await task.value
    }
    return try await authStore.validAccessToken()
  }
}
