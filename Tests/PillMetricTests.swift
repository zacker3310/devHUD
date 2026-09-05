import XCTest
@testable import devHUD

final class PillMetricTests: XCTestCase {
    let slots = [
        ProviderSlot(id: "claude:a", kind: .claude, title: "Claude Max"),
        ProviderSlot(id: "copilot", kind: .copilot, title: "Copilot"),
        ProviderSlot(id: "codex", kind: .codex, title: "Codex"),
    ]

    func testRingCentersAreEvenlySpacedFromTheTop() {
        let rows = PillMetric.rows(for: slots)
        let first = PillMetric.ringCenterY(index: 0)
        XCTAssertEqual(first, PillMetric.ear + PillMetric.topPad + PillMetric.ringSize / 2)
        XCTAssertEqual(PillMetric.ringCenterY(index: 1) - first, PillMetric.itemHeight + PillMetric.itemSpacing)
        XCTAssertLessThan(PillMetric.ringCenterY(index: rows.count - 1), PillMetric.windowHeight(rows: rows.count))
    }

    func testRowsFollowKindOrderThenServers() {
        let shuffled = [slots[2], slots[1], slots[0]]
        let rows = PillMetric.rows(for: shuffled)
        XCTAssertEqual(rows.map { $0.slot?.kind }, [.claude, .copilot, .codex, nil])
        XCTAssertEqual(rows.last, .servers)
    }

    func testTwoClaudeSlotsKeepDiscoveryOrder() {
        let work = ProviderSlot(id: "claude:b", kind: .claude, title: "Claude Enterprise")
        let rows = PillMetric.rows(for: slots + [work])
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].slot?.title, "Claude Max")
        XCTAssertEqual(rows[1].slot?.title, "Claude Enterprise")
        XCTAssertGreaterThan(PillMetric.windowHeight(rows: 5), PillMetric.windowHeight(rows: 4))
    }

    func testCardPlacementPointsAtTheRing() {
        let p = PillMetric.cardPlacement(ringCenterScreenY: 500, cardHeight: 200, screenMinY: 0, screenMaxY: 1080)
        XCTAssertEqual(p.top, 500 + PillMetric.cardPointerInset)
        XCTAssertEqual(p.pointerY, PillMetric.cardPointerInset)
    }

    func testCardPlacementClampsToScreenBottom() {
        let p = PillMetric.cardPlacement(ringCenterScreenY: 50, cardHeight: 400, screenMinY: 0, screenMaxY: 1080)
        XCTAssertEqual(p.top, 408)
        XCTAssertGreaterThanOrEqual(p.top - 400, 8)
        XCTAssertEqual(p.pointerY, 358)
        XCTAssertLessThanOrEqual(p.pointerY, 400 - PillMetric.cardPointerHeight)
    }

    func testCardPlacementClampsToScreenTop() {
        let p = PillMetric.cardPlacement(ringCenterScreenY: 1070, cardHeight: 200, screenMinY: 0, screenMaxY: 1080)
        XCTAssertEqual(p.top, 1072)
        XCTAssertEqual(p.pointerY, PillMetric.cardPointerHeight)
    }

    func testTallCardStillStartsOnScreen() {
        let p = PillMetric.cardPlacement(ringCenterScreenY: 500, cardHeight: 1200, screenMinY: 0, screenMaxY: 1080)
        XCTAssertLessThanOrEqual(p.top, 1072)
    }
}
