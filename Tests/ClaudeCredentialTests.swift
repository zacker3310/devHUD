import XCTest
@testable import devHUD

final class ClaudeCredentialTests: XCTestCase {
    func testTokenFromCredentialsJSON() throws {
        let future = Int((Date().timeIntervalSince1970 + 3600) * 1000)
        let json = #"{"claudeAiOauth":{"accessToken":"fixture-token","expiresAt":\#(future),"subscriptionType":"max"}}"#
        XCTAssertEqual(try ClaudeUsageProvider.token(fromCredentialsJSON: Data(json.utf8)), "fixture-token")
    }

    func testExpiredTokenIsRefused() {
        let past = Int((Date().timeIntervalSince1970 - 60) * 1000)
        let json = #"{"claudeAiOauth":{"accessToken":"fixture-token","expiresAt":\#(past)}}"#
        XCTAssertThrowsError(try ClaudeUsageProvider.token(fromCredentialsJSON: Data(json.utf8)))
    }

    func testMissingTokenIsRefused() {
        XCTAssertThrowsError(try ClaudeUsageProvider.token(fromCredentialsJSON: Data("{}".utf8)))
        XCTAssertThrowsError(try ClaudeUsageProvider.token(fromCredentialsJSON: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)))
    }
}
