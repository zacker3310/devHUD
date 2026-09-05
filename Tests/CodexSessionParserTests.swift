import XCTest
@testable import devHUD

final class CodexSessionParserTests: XCTestCase {
    let rateLine = #"{"timestamp":"2026-08-16T04:10:40.914Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":5.0,"window_minutes":10080,"resets_at":1787367553},"secondary":{"used_percent":12.5,"window_minutes":300,"resets_in_seconds":3600},"plan_type":"plus"}}}"#
    let olderLine = #"{"timestamp":"2026-08-16T04:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":1.0,"window_minutes":10080,"resets_at":1787367553},"secondary":null}}}"#

    func testNewestRateLimitsLineWins() throws {
        let snap = try XCTUnwrap(CodexSessionParser.snapshot(fromLines: [olderLine, #"{"type":"other"}"#, rateLine]))
        XCTAssertEqual(snap.primary.percentUsed, 5.0)
        XCTAssertEqual(snap.primary.label, "weekly")
        XCTAssertEqual(snap.primary.resetsAt, Date(timeIntervalSince1970: 1787367553))
        XCTAssertEqual(snap.planLabel, "plus")
        XCTAssertEqual(snap.fetchedAt, ISO8601.parse("2026-08-16T04:10:40.914Z"))
    }

    func testSecondaryWithRelativeReset() throws {
        let snap = try XCTUnwrap(CodexSessionParser.snapshot(fromLines: [rateLine]))
        XCTAssertEqual(snap.secondary.count, 1)
        XCTAssertEqual(snap.secondary[0].label, "5h")
        XCTAssertEqual(snap.secondary[0].percentUsed, 12.5)
        XCTAssertEqual(snap.secondary[0].resetsAt, snap.fetchedAt.addingTimeInterval(3600))
    }

    func testNullSecondaryIsDropped() throws {
        let snap = try XCTUnwrap(CodexSessionParser.snapshot(fromLines: [olderLine]))
        XCTAssertEqual(snap.secondary, [])
        XCTAssertNil(snap.planLabel)
    }

    func testNoRateLimitsReturnsNil() {
        XCTAssertNil(CodexSessionParser.snapshot(fromLines: [#"{"type":"session_meta"}"#, "not json"]))
        XCTAssertNil(CodexSessionParser.snapshot(fromLines: []))
    }

    func testWindowLabels() {
        XCTAssertEqual(CodexSessionParser.windowLabel(minutes: 300), "5h")
        XCTAssertEqual(CodexSessionParser.windowLabel(minutes: 10080), "weekly")
        XCTAssertEqual(CodexSessionParser.windowLabel(minutes: 2880), "2d")
        XCTAssertEqual(CodexSessionParser.windowLabel(minutes: 180), "3h")
        XCTAssertEqual(CodexSessionParser.windowLabel(minutes: 90), "90m")
    }
}
