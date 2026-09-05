import XCTest
@testable import devHUD

final class HoverResolverTests: XCTestCase {
    let rows = PillMetric.rows(for: [
        ProviderSlot(id: "claude:a", kind: .claude, title: "Claude Max"),
        ProviderSlot(id: "copilot", kind: .copilot, title: "Copilot"),
        ProviderSlot(id: "codex", kind: .codex, title: "Codex"),
    ])
    // Pill docked at the right edge of a 1920x1080 screen, revealed.
    var pill: CGRect { CGRect(x: 1920 - PillMetric.pillWidth, y: 400, width: PillMetric.pillWidth, height: PillMetric.windowHeight(rows: rows.count)) }
    let card = CGRect(x: 1500, y: 450, width: 300, height: 200)

    func testOutsideEverythingIsNone() {
        XCTAssertEqual(HoverResolver.resolve(location: CGPoint(x: 100, y: 100), pillFrame: pill, cardFrame: card, rows: rows), .none)
        XCTAssertEqual(HoverResolver.resolve(location: CGPoint(x: 100, y: 100), pillFrame: pill, cardFrame: nil, rows: rows), .none)
    }

    func testRingCentersResolveToTheirRows() {
        for (index, row) in rows.enumerated() {
            let y = pill.maxY - PillMetric.ringCenterY(index: index)
            let target = HoverResolver.resolve(location: CGPoint(x: 1900, y: y), pillFrame: pill, cardFrame: nil, rows: rows)
            XCTAssertEqual(target, .pill(row), "row \(index)")
        }
    }

    func testGapBelowARowStillBelongsToIt() {
        let y = pill.maxY - (PillMetric.itemTop(index: 1) - 3)
        XCTAssertEqual(HoverResolver.resolve(location: CGPoint(x: 1900, y: y), pillFrame: pill, cardFrame: nil, rows: rows), .pill(rows[0]))
    }

    func testPaddingIsThePillWithNoItem() {
        let top = pill.maxY - 2
        XCTAssertEqual(HoverResolver.resolve(location: CGPoint(x: 1900, y: top), pillFrame: pill, cardFrame: nil, rows: rows), .pill(nil))
    }

    func testGearCircleResolvesToGear() {
        let gear = PillMetric.gearFrame(belowPill: pill)
        let inside = CGPoint(x: gear.midX, y: gear.midY)
        XCTAssertEqual(HoverResolver.resolve(location: inside, pillFrame: pill, cardFrame: nil, gearFrame: gear, rows: rows), .gear)
        // Without a shown gear the same point is the pill's transparent ear zone.
        XCTAssertEqual(HoverResolver.resolve(location: inside, pillFrame: pill, cardFrame: nil, gearFrame: nil, rows: rows), .pill(nil))
    }

    func testCardWinsOnlyWhenOutsideThePill() {
        XCTAssertEqual(HoverResolver.resolve(location: CGPoint(x: 1600, y: 500), pillFrame: pill, cardFrame: card, rows: rows), .card)
        XCTAssertEqual(HoverResolver.resolve(location: CGPoint(x: 1600, y: 500), pillFrame: pill, cardFrame: nil, rows: rows), .none)
    }

    func testConcealedSliverStillHitsTheRow() {
        let sliver = CGRect(x: 1920 - PillMetric.peek, y: 400, width: PillMetric.peek, height: PillMetric.windowHeight(rows: rows.count))
        let y = sliver.maxY - PillMetric.ringCenterY(index: 2)
        XCTAssertEqual(HoverResolver.resolve(location: CGPoint(x: 1918, y: y), pillFrame: sliver, cardFrame: nil, rows: rows), .pill(rows[2]))
        XCTAssertEqual(HoverResolver.resolve(location: CGPoint(x: 1910, y: y), pillFrame: sliver, cardFrame: nil, rows: rows), .none)
    }

    func testBelowTheLastRowIsThePillWithNoItem() {
        let y = pill.maxY - (PillMetric.itemTop(index: rows.count - 1) + PillMetric.itemHeight + 2)
        XCTAssertEqual(HoverResolver.resolve(location: CGPoint(x: 1900, y: y), pillFrame: pill, cardFrame: nil, rows: rows), .pill(nil))
    }
}
