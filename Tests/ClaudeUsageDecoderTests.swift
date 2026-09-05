import XCTest
@testable import devHUD

final class ClaudeUsageDecoderTests: XCTestCase {
    let body = #"{"five_hour":{"utilization":34.5,"resets_at":"2026-09-05T02:00:00.123456+00:00"},"seven_day":{"utilization":12,"resets_at":"2026-09-08T00:00:00Z"},"seven_day_opus":null,"seven_day_sonnet":{"utilization":3.25,"resets_at":null},"extra":"ignored"}"#

    func testPrimaryIsFiveHour() throws {
        let now = Date()
        let snap = try ClaudeUsageDecoder.decode(Data(body.utf8), now: now)
        XCTAssertEqual(snap.primary.label, "5h")
        XCTAssertEqual(snap.primary.percentUsed, 34.5)
        XCTAssertEqual(snap.primary.resetsAt, ISO8601.parse("2026-09-05T02:00:00.123Z"))
        XCTAssertEqual(snap.fetchedAt, now)
    }

    func testSecondaryOrderAndNullsDropped() throws {
        let snap = try ClaudeUsageDecoder.decode(Data(body.utf8))
        XCTAssertEqual(snap.secondary.map(\.label), ["7d", "7d Sonnet"])
        XCTAssertEqual(snap.secondary[0].resetsAt, ISO8601.parse("2026-09-08T00:00:00Z"))
        XCTAssertNil(snap.secondary[1].resetsAt)
    }

    func testUnknownWindowKeySurvives() throws {
        let snap = try ClaudeUsageDecoder.decode(Data(#"{"monthly":{"utilization":50}}"#.utf8))
        XCTAssertEqual(snap.primary.label, "monthly")
        XCTAssertEqual(snap.primary.percentUsed, 50)
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try ClaudeUsageDecoder.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try ClaudeUsageDecoder.decode(Data("[]".utf8)))
    }
}
