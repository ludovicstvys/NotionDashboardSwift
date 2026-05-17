import XCTest
@testable import Dashboard

final class SecureKeychainTests: XCTestCase {
  override func tearDown() {
    for account in SecureKeychain.Account.allCases {
      _ = SecureKeychain.delete(account)
    }
    super.tearDown()
  }

  func testWriteThenRead() {
    XCTAssertTrue(SecureKeychain.write(.notionToken, value: "token-abc"))
    XCTAssertEqual(SecureKeychain.read(.notionToken), "token-abc")
  }

  func testOverwriteUpdates() {
    SecureKeychain.write(.googleAccessToken, value: "first")
    SecureKeychain.write(.googleAccessToken, value: "second")
    XCTAssertEqual(SecureKeychain.read(.googleAccessToken), "second")
  }

  func testDeleteRemovesEntry() {
    SecureKeychain.write(.googleRefreshToken, value: "refresh")
    XCTAssertTrue(SecureKeychain.delete(.googleRefreshToken))
    XCTAssertNil(SecureKeychain.read(.googleRefreshToken))
  }

  func testReadMissingReturnsNil() {
    XCTAssertNil(SecureKeychain.read(.googleOAuthClientSecret))
  }
}
