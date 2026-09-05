import XCTest
@testable import devHUD

final class CPUDeltaTests: XCTestCase {
    func testNormalDelta() {
        XCTAssertEqual(CPUDelta.percent(previousSeconds: 10, currentSeconds: 12, wall: 4), 50)
    }

    func testNegativeDeltaFromPidReuseIsNil() {
        XCTAssertNil(CPUDelta.percent(previousSeconds: 10, currentSeconds: 3, wall: 4))
    }

    func testTooShortWallIsNil() {
        XCTAssertNil(CPUDelta.percent(previousSeconds: 10, currentSeconds: 11, wall: 0))
        XCTAssertNil(CPUDelta.percent(previousSeconds: 10, currentSeconds: 11, wall: 0.2))
    }

    func testIdleProcessReadsZero() {
        XCTAssertEqual(CPUDelta.percent(previousSeconds: 10, currentSeconds: 10, wall: 4), 0)
    }
}
