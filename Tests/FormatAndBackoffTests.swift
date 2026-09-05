import XCTest
@testable import devHUD

final class FormatAndBackoffTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testBackoffDoublesAndCaps() {
        XCTAssertEqual(Backoff.delay(failures: 0), 120)
        XCTAssertEqual(Backoff.delay(failures: 1), 240)
        XCTAssertEqual(Backoff.delay(failures: 3), 960)
        XCTAssertEqual(Backoff.delay(failures: 10), 1800)
    }

    func testResetText() {
        XCTAssertNil(UsageFormat.resetText(nil, now: now))
        XCTAssertEqual(UsageFormat.resetText(now.addingTimeInterval(51 * 60), now: now), "Resets in 51 min")
        XCTAssertEqual(UsageFormat.resetText(now.addingTimeInterval(3 * 3600 + 12 * 60), now: now), "Resets in 3h 12m")
        XCTAssertEqual(UsageFormat.resetText(now.addingTimeInterval(2 * 86400 + 4 * 3600), now: now), "Resets in 2d 4h")
        XCTAssertEqual(UsageFormat.resetText(now.addingTimeInterval(-5), now: now), "Resets now")
    }

    func testStaleText() {
        XCTAssertNil(UsageFormat.staleText(now.addingTimeInterval(-600), now: now))
        XCTAssertNotNil(UsageFormat.staleText(now.addingTimeInterval(-7200), now: now))
    }

    func testUptime() {
        XCTAssertNil(UsageFormat.uptime(since: nil, now: now))
        XCTAssertEqual(UsageFormat.uptime(since: now.addingTimeInterval(-45), now: now), "45s")
        XCTAssertEqual(UsageFormat.uptime(since: now.addingTimeInterval(-25 * 60), now: now), "25m")
        XCTAssertEqual(UsageFormat.uptime(since: now.addingTimeInterval(-3 * 3600 - 60), now: now), "3h 1m")
        XCTAssertEqual(UsageFormat.uptime(since: now.addingTimeInterval(-26 * 3600), now: now), "1d 2h")
    }

    func testISO8601Variants() {
        XCTAssertNotNil(ISO8601.parse("2026-08-16T04:10:40.914Z"))
        XCTAssertNotNil(ISO8601.parse("2026-08-16T04:10:40Z"))
        XCTAssertNotNil(ISO8601.parse("2026-09-05T02:00:00.123456+00:00"))
        XCTAssertNil(ISO8601.parse("yesterday"))
    }

    func testProjectName() {
        let pkg = Data(#"{"name":"@acker/thrivecmd"}"#.utf8)
        XCTAssertEqual(ProjectName.infer(cwd: "/Users/z/dev/thrivecmd", packageJSON: pkg, home: "/Users/z"), "thrivecmd")
        XCTAssertEqual(ProjectName.infer(cwd: "/Users/z/dev/nexus/backend", packageJSON: nil, home: "/Users/z"), "backend")
        XCTAssertNil(ProjectName.infer(cwd: "/Users/z", packageJSON: nil, home: "/Users/z"))
        XCTAssertNil(ProjectName.infer(cwd: "/", packageJSON: nil, home: "/Users/z"))
    }
}
