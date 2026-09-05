import XCTest
@testable import devHUD

final class CopilotUsageDecoderTests: XCTestCase {
    func body(premiumHasQuota: Bool, premiumRemaining: Double) -> Data {
        let json = """
        {"copilot_plan":"individual","quota_reset_date":"2026-10-01","quota_snapshots":{
          "chat":{"percent_remaining":75.0,"has_quota":true,"unlimited":false,"entitlement":200},
          "completions":{"percent_remaining":100.0,"has_quota":true,"unlimited":false,"entitlement":2000},
          "premium_interactions":{"percent_remaining":\(premiumRemaining),"has_quota":\(premiumHasQuota),"unlimited":false,"entitlement":300}}}
        """
        return Data(json.utf8)
    }

    func testPremiumIsPrimaryWhenItHasQuota() throws {
        let snap = try CopilotUsageDecoder.decode(body(premiumHasQuota: true, premiumRemaining: 40))
        XCTAssertEqual(snap.primary.label, "Premium")
        XCTAssertEqual(snap.primary.percentUsed, 60)
        XCTAssertEqual(snap.secondary.map(\.label), ["Chat", "Completions"])
        XCTAssertEqual(snap.planLabel, "individual")
    }

    func testChatIsPrimaryWithoutPremiumQuota() throws {
        let snap = try CopilotUsageDecoder.decode(body(premiumHasQuota: false, premiumRemaining: 0))
        XCTAssertEqual(snap.primary.label, "Chat")
        XCTAssertEqual(snap.primary.percentUsed, 25)
        XCTAssertEqual(snap.secondary.map(\.label), ["Completions"])
    }

    func testResetDateIsLocalMidnight() throws {
        let snap = try CopilotUsageDecoder.decode(body(premiumHasQuota: true, premiumRemaining: 40))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: try XCTUnwrap(snap.primary.resetsAt))
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 10)
        XCTAssertEqual(parts.day, 1)
        XCTAssertEqual(parts.hour, 0)
    }

    func testUnlimitedIsSkippedAndEmptyThrows() {
        let all = Data(#"{"quota_snapshots":{"chat":{"percent_remaining":1,"unlimited":true}}}"#.utf8)
        XCTAssertThrowsError(try CopilotUsageDecoder.decode(all))
        XCTAssertThrowsError(try CopilotUsageDecoder.decode(Data("{}".utf8)))
    }
}
