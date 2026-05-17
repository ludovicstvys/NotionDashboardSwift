import Foundation

enum APIClientError: LocalizedError {
  case invalidURL
  case invalidResponse
  case httpStatus(code: Int, body: String)
  case decoding(Error)
  case rateLimited(retryAfter: TimeInterval, body: String)
  case network(Error)
  case retryExhausted(lastError: String)
  case unauthorized(body: String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid URL."
    case .invalidResponse:
      return "Invalid HTTP response."
    case let .httpStatus(code, body):
      return "HTTP \(code): \(body)"
    case let .decoding(error):
      return "Decoding failed: \(error.localizedDescription)"
    case let .rateLimited(retryAfter, _):
      return "Rate limited (retry after \(retryAfter)s)."
    case let .network(error):
      return error.localizedDescription
    case let .retryExhausted(lastError):
      return "Retries exhausted: \(lastError)"
    case let .unauthorized(body):
      return "Unauthorized: \(body)"
    }
  }

  var isRetryable: Bool {
    switch self {
    case .invalidURL, .decoding, .unauthorized:
      return false
    case .invalidResponse:
      return true
    case let .httpStatus(code, _):
      return code >= 500 || code == 408 || code == 429
    case .rateLimited:
      return true
    case let .network(error):
      let nsError = error as NSError
      return nsError.domain == NSURLErrorDomain &&
        [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed].contains(nsError.code)
    case .retryExhausted:
      return false
    }
  }
}

struct APIRequest {
  var method: String = "GET"
  var url: URL
  var headers: [String: String] = [:]
  var body: Data?
  var timeout: TimeInterval?

  func urlRequest() -> URLRequest {
    var req = URLRequest(url: url)
    req.httpMethod = method
    for (k, v) in headers {
      req.addValue(v, forHTTPHeaderField: k)
    }
    if let body {
      req.httpBody = body
    }
    if let timeout {
      req.timeoutInterval = timeout
    }
    return req
  }
}

// Interceptor lets services hook auth, logging, header injection.
protocol APIInterceptor: Sendable {
  func adapt(_ request: APIRequest) async throws -> APIRequest
  // Returns true if request should be retried after handling (e.g. token refresh).
  func handleResponse(statusCode: Int, body: Data, originalRequest: APIRequest) async -> Bool
}

extension APIInterceptor {
  func adapt(_ request: APIRequest) async throws -> APIRequest { request }
  func handleResponse(statusCode: Int, body: Data, originalRequest: APIRequest) async -> Bool { false }
}

struct APIClient {
  let session: URLSession
  let maxRetries: Int
  let baseDelay: TimeInterval
  let backoffMultiplier: Double
  let interceptors: [APIInterceptor]

  init(
    session: URLSession = .app,
    maxRetries: Int = 4,
    baseDelay: TimeInterval = 0.6,
    backoffMultiplier: Double = 1.8,
    interceptors: [APIInterceptor] = []
  ) {
    self.session = session
    self.maxRetries = max(0, maxRetries)
    self.baseDelay = baseDelay
    self.backoffMultiplier = backoffMultiplier
    self.interceptors = interceptors
  }

  func send(_ request: APIRequest) async throws -> (Data, HTTPURLResponse) {
    var attempt = 0
    var delay = baseDelay
    var lastError: Error?

    while attempt <= maxRetries {
      do {
        var prepared = request
        for interceptor in interceptors {
          prepared = try await interceptor.adapt(prepared)
        }
        let (data, response) = try await session.data(for: prepared.urlRequest())
        guard let http = response as? HTTPURLResponse else {
          throw APIClientError.invalidResponse
        }

        var shouldInterceptorRetry = false
        for interceptor in interceptors {
          if await interceptor.handleResponse(statusCode: http.statusCode, body: data, originalRequest: prepared) {
            shouldInterceptorRetry = true
          }
        }

        if (200...299).contains(http.statusCode) {
          return (data, http)
        }

        let bodyString = String(data: data, encoding: .utf8) ?? ""
        if http.statusCode == 401 {
          if shouldInterceptorRetry, attempt < maxRetries {
            attempt += 1
            continue
          }
          throw APIClientError.unauthorized(body: bodyString)
        }
        if http.statusCode == 429 {
          let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2.0
          let err = APIClientError.rateLimited(retryAfter: retryAfter, body: bodyString)
          if attempt < maxRetries {
            try await sleep(seconds: retryAfter)
            attempt += 1
            continue
          }
          throw err
        }

        let err = APIClientError.httpStatus(code: http.statusCode, body: bodyString)
        if err.isRetryable, attempt < maxRetries {
          try await sleep(seconds: delay)
          attempt += 1
          delay *= backoffMultiplier * (1.0 + Double.random(in: 0..<0.2))
          continue
        }
        throw err
      } catch let apiError as APIClientError {
        lastError = apiError
        if apiError.isRetryable, attempt < maxRetries {
          try await sleep(seconds: delay)
          attempt += 1
          delay *= backoffMultiplier * (1.0 + Double.random(in: 0..<0.2))
          continue
        }
        throw apiError
      } catch {
        lastError = error
        let wrapped = APIClientError.network(error)
        if wrapped.isRetryable, attempt < maxRetries {
          try await sleep(seconds: delay)
          attempt += 1
          delay *= backoffMultiplier * (1.0 + Double.random(in: 0..<0.2))
          continue
        }
        throw wrapped
      }
    }

    throw APIClientError.retryExhausted(lastError: lastError?.localizedDescription ?? "Unknown")
  }

  func sendJSON<T: Decodable>(_ request: APIRequest, decoder: JSONDecoder = APIClient.defaultDecoder) async throws -> T {
    let (data, _) = try await send(request)
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw APIClientError.decoding(error)
    }
  }

  func sendVoid(_ request: APIRequest) async throws {
    _ = try await send(request)
  }

  private func sleep(seconds: TimeInterval) async throws {
    let clamped = max(0.05, seconds)
    try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
  }

  static let defaultDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  static let defaultEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}
