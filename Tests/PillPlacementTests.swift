import XCTest
@testable import devHUD

final class PillPlacementTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let rows = 4

    func testRightEdgeFrames() {
        let p = PillPlacement(edge: .right, anchor: 0.5, screenName: nil)
        let revealed = PillMetric.pillFrame(placement: p, screen: screen, revealed: true, rows: rows)
        let concealed = PillMetric.pillFrame(placement: p, screen: screen, revealed: false, rows: rows)
        XCTAssertEqual(revealed.maxX, 1920)
        XCTAssertEqual(revealed.width, PillMetric.pillWidth)
        XCTAssertEqual(concealed.maxX, 1920)
        XCTAssertEqual(concealed.width, PillMetric.peek)
        XCTAssertEqual(revealed.midY, 540, accuracy: 0.5)
        XCTAssertEqual(revealed.width, PillMetric.pillWidth)
    }

    func testLeftEdgeFrames() {
        let p = PillPlacement(edge: .left, anchor: 0.5, screenName: nil)
        let revealed = PillMetric.pillFrame(placement: p, screen: screen, revealed: true, rows: rows)
        let concealed = PillMetric.pillFrame(placement: p, screen: screen, revealed: false, rows: rows)
        XCTAssertEqual(revealed.minX, 0)
        XCTAssertEqual(concealed.minX, 0)
        XCTAssertEqual(concealed.width, PillMetric.peek)
    }

    func testAnchorIsClampedToTheScreen() {
        let low = PillMetric.pillFrame(placement: PillPlacement(edge: .right, anchor: 0, screenName: nil), screen: screen, revealed: true, rows: rows)
        let high = PillMetric.pillFrame(placement: PillPlacement(edge: .right, anchor: 1, screenName: nil), screen: screen, revealed: true, rows: rows)
        XCTAssertEqual(low.minY, PillMetric.gearReserve)
        XCTAssertEqual(high.maxY, 1080)
        XCTAssertEqual(PillMetric.gearFrame(belowPill: low).minY, 0)
    }

    func testSnapPicksTheNearerEdgeAndCursorHeight() {
        let left = PillPlacement.snapped(cursor: CGPoint(x: 300, y: 216), screen: screen, screenName: "Main")
        XCTAssertEqual(left.edge, .left)
        XCTAssertEqual(left.anchor, 0.2, accuracy: 0.001)
        XCTAssertEqual(left.screenName, "Main")
        let right = PillPlacement.snapped(cursor: CGPoint(x: 1500, y: 2000), screen: screen, screenName: nil)
        XCTAssertEqual(right.edge, .right)
        XCTAssertEqual(right.anchor, 1)
    }

    func testCardXForBothEdges() {
        let rightPill = CGRect(x: 1856, y: 400, width: 64, height: 300)
        XCTAssertEqual(PillMetric.cardX(edge: .right, pill: rightPill, cardWidth: 342, screen: screen), 1856 - 342 + 2)
        let leftPill = CGRect(x: 0, y: 400, width: 64, height: 300)
        XCTAssertEqual(PillMetric.cardX(edge: .left, pill: leftPill, cardWidth: 342, screen: screen), 62)
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 1080)
        XCTAssertEqual(PillMetric.cardX(edge: .left, pill: leftPill, cardWidth: 342, screen: narrow), -42)
    }

    func testGearCircleSitsCenteredBelowThePill() {
        let pill = CGRect(x: 1856, y: 400, width: 64, height: 300)
        let gear = PillMetric.gearFrame(belowPill: pill)
        XCTAssertEqual(gear.midX, pill.midX)
        XCTAssertEqual(gear.maxY, pill.minY + PillMetric.ear - PillMetric.gearGap)
        XCTAssertEqual(gear.width, PillMetric.gearDiameter)
    }

    func testRoundTripThroughDefaults() {
        let store = UserDefaults(suiteName: "devHUD.tests.placement")!
        store.removePersistentDomain(forName: "devHUD.tests.placement")
        XCTAssertEqual(PillPlacement.load(from: store), PillPlacement.defaults)
        let p = PillPlacement(edge: .left, anchor: 0.25, screenName: "Studio Display")
        p.save(to: store)
        XCTAssertEqual(PillPlacement.load(from: store), p)
    }
}
