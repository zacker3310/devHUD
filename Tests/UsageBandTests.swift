import XCTest
@testable import devHUD

final class UsageBandTests: XCTestCase {
    func testBandsAtTheBoundaries() {
        XCTAssertEqual(UsageBand(percentUsed: 0), .ample)
        XCTAssertEqual(UsageBand(percentUsed: 49.9), .ample)
        XCTAssertEqual(UsageBand(percentUsed: 50), .watch)
        XCTAssertEqual(UsageBand(percentUsed: 69.9), .watch)
        XCTAssertEqual(UsageBand(percentUsed: 70), .critical)
        XCTAssertEqual(UsageBand(percentUsed: 99.9), .critical)
        XCTAssertEqual(UsageBand(percentUsed: 100), .exhausted)
        XCTAssertEqual(UsageBand(percentUsed: 140), .exhausted)
    }

    func testStaleness() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = ProviderState()
        XCTAssertFalse(state.isStale(now: now))
        state.lastGood = UsageSnapshot(primary: UsageWindow(label: "5h", percentUsed: 1, resetsAt: nil), secondary: [], fetchedAt: now.addingTimeInterval(-600), planLabel: nil)
        XCTAssertFalse(state.isStale(now: now))
        state.lastGood = UsageSnapshot(primary: UsageWindow(label: "5h", percentUsed: 1, resetsAt: nil), secondary: [], fetchedAt: now.addingTimeInterval(-7200), planLabel: nil)
        XCTAssertTrue(state.isStale(now: now))
        state.lastGood = UsageSnapshot(primary: UsageWindow(label: "5h", percentUsed: 1, resetsAt: nil), secondary: [], fetchedAt: now, planLabel: nil)
        state.nextAttempt = now.addingTimeInterval(600)
        XCTAssertTrue(state.isStale(now: now), "rate limited reads as stale")
    }
}
