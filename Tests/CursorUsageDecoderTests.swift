import XCTest
@testable import devHUD

final class CursorUsageDecoderTests: XCTestCase {
    let body = #"{"billingCycleEnd":"2026-10-01T00:00:00.000Z","membershipType":"pro","isUnlimited":false,"individualUsage":{"plan":{"totalPercentUsed":34,"apiPercentUsed":0},"onDemand":{"enabled":true,"limit":20,"used":5}}}"#

    func testIncludedIsPrimaryAndOnDemandFollows() throws {
        let snap = try CursorUsageDecoder.decode(Data(body.utf8))
        XCTAssertEqual(snap.primary.label, "Included")
        XCTAssertEqual(snap.primary.percentUsed, 34)
        XCTAssertEqual(snap.primary.resetsAt, ISO8601.parse("2026-10-01T00:00:00Z"))
        XCTAssertEqual(snap.secondary.map(\.label), ["On demand"])
        XCTAssertEqual(snap.secondary[0].percentUsed, 25)
        XCTAssertEqual(snap.planLabel, "pro")
    }

    func testAPIWindowOnlyWhenUsed() throws {
        let withAPI = body.replacingOccurrences(of: "\"apiPercentUsed\":0", with: "\"apiPercentUsed\":12")
        XCTAssertEqual(try CursorUsageDecoder.decode(Data(withAPI.utf8)).secondary.map(\.label), ["API", "On demand"])
    }

    func testUnlimitedAndEmptyThrow() {
        XCTAssertThrowsError(try CursorUsageDecoder.decode(Data(#"{"isUnlimited":true,"individualUsage":{}}"#.utf8)))
        XCTAssertThrowsError(try CursorUsageDecoder.decode(Data("{}".utf8)))
    }

    func testMissingStoreYieldsNoSlot() {
        let provider = CursorUsageProvider(storeURL: URL(fileURLWithPath: "/nonexistent/state.vscdb"))
        XCTAssertThrowsError(try provider.sessionCookie())
    }
}
