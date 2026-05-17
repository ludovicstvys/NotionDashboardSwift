import XCTest
@testable import Dashboard

final class APIClientTests: XCTestCase {
  override func setUp() {
    super.setUp()
    MockURLProtocol.handler = nil
    MockURLProtocol.requestLog.removeAll()
  }

  func testSuccessfulRequestReturnsBody() async throws {
    let payload = #"{"ok":true}"#.data(using: .utf8)!
    MockURLProtocol.handler = { _ in (httpResponse(200), payload) }

    let client = makeClient()
    let url = URL(string: "https://example.test/path")!
    let (data, response) = try await client.send(APIRequest(url: url))

    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(data, payload)
    XCTAssertEqual(MockURLProtocol.requestLog.count, 1)
  }

  func testRetryOnTransient500() async throws {
    var hits = 0
    MockURLProtocol.handler = { _ in
      hits += 1
      if hits < 3 {
        return (httpResponse(500), Data("oops".utf8))
      }
      return (httpResponse(200), Data(#"{"ok":true}"#.utf8))
    }

    let client = makeClient(maxRetries: 4, baseDelay: 0.01)
    let (_, response) = try await client.send(APIRequest(url: URL(string: "https://example.test/retry")!))
    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(hits, 3)
  }

  func testNon2xxNonRetryableThrowsHTTPStatus() async {
    MockURLProtocol.handler = { _ in (httpResponse(400), Data("bad".utf8)) }

    let client = makeClient(maxRetries: 2, baseDelay: 0.01)
    do {
      _ = try await client.send(APIRequest(url: URL(string: "https://example.test/bad")!))
      XCTFail("Expected throw")
    } catch let error as APIClientError {
      if case let .httpStatus(code, body) = error {
        XCTAssertEqual(code, 400)
        XCTAssertEqual(body, "bad")
      } else {
        XCTFail("Wrong error case: \(error)")
      }
    } catch {
      XCTFail("Wrong error type: \(error)")
    }
  }

  func testRateLimitedRespectsRetryAfter() async throws {
    var hits = 0
    MockURLProtocol.handler = { _ in
      hits += 1
      if hits == 1 {
        let response = HTTPURLResponse(
          url: URL(string: "https://example.test/limited")!,
          statusCode: 429,
          httpVersion: nil,
          headerFields: ["Retry-After": "0"]
        )!
        return (response, Data())
      }
      return (httpResponse(200), Data())
    }

    let client = makeClient(maxRetries: 2, baseDelay: 0.01)
    let (_, response) = try await client.send(APIRequest(url: URL(string: "https://example.test/limited")!))
    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(hits, 2)
  }

  // MARK: - Helpers

  private func makeClient(maxRetries: Int = 1, baseDelay: TimeInterval = 0.01) -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return APIClient(session: session, maxRetries: maxRetries, baseDelay: baseDelay)
  }
}

private func httpResponse(_ status: Int) -> HTTPURLResponse {
  HTTPURLResponse(
    url: URL(string: "https://example.test")!,
    statusCode: status,
    httpVersion: nil,
    headerFields: nil
  )!
}

final class MockURLProtocol: URLProtocol {
  static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
  static var requestLog: [URLRequest] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requestLog.append(request)
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    let (response, data) = handler(request)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
