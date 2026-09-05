import XCTest
@testable import devHUD

final class ClaudeLimitsDecoderTests: XCTestCase {
    let body = """
    {"five_hour":{"utilization":15,"resets_at":"2026-09-05T04:00:00Z"},
     "seven_day":{"utilization":3,"resets_at":"2026-09-10T09:00:00Z"},
     "nimbus_quill":{"utilization":0},
     "limits":[
       {"group":"session","kind":"session","percent":15,"resets_at":"2026-09-05T04:00:00Z","scope":null,"severity":"normal"},
       {"group":"weekly","kind":"weekly_all","percent":3,"resets_at":"2026-09-10T09:00:00Z","scope":null},
       {"group":"weekly","kind":"weekly_scoped","percent":5,"resets_at":"2026-09-10T09:00:00Z","scope":{"model":{"display_name":"Fable","id":null},"surface":null}}
     ]}
    """

    func testLimitsArrayWins() throws {
        let snap = try ClaudeUsageDecoder.decode(Data(body.utf8))
        XCTAssertEqual(snap.primary.label, "5h")
        XCTAssertEqual(snap.primary.percentUsed, 15)
        XCTAssertEqual(snap.secondary.map(\.label), ["7d", "7d Fable"])
        XCTAssertEqual(snap.secondary[1].percentUsed, 5)
        XCTAssertEqual(snap.secondary[1].resetsAt, ISO8601.parse("2026-09-10T09:00:00Z"))
    }

    func testScopedWithoutModelFallsBackToSurface() {
        let entry: [String: Any] = ["kind": "weekly_scoped", "percent": 9.0, "scope": ["model": NSNull(), "surface": "Code"]]
        XCTAssertEqual(ClaudeUsageDecoder.limitWindow(entry)?.label, "7d Code")
    }

    func testEntryWithoutPercentIsSkipped() {
        XCTAssertNil(ClaudeUsageDecoder.limitWindow(["kind": "session", "resets_at": "2026-09-05T04:00:00Z"]))
    }

    func testEmptyLimitsFallsBackToFlatKeys() throws {
        let flat = #"{"limits":[],"five_hour":{"utilization":40,"resets_at":null}}"#
        let snap = try ClaudeUsageDecoder.decode(Data(flat.utf8))
        XCTAssertEqual(snap.primary.label, "5h")
        XCTAssertEqual(snap.primary.percentUsed, 40)
    }
}
