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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
        // 2027-01-15 08:00 local (a Friday)
        let base = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 8))!
        XCTAssertNil(UsageFormat.resetText(nil, now: base, calendar: calendar))
        XCTAssertEqual(UsageFormat.resetText(base.addingTimeInterval(51 * 60), now: base, calendar: calendar), "Resets in 51 min")
        XCTAssertEqual(UsageFormat.resetText(base.addingTimeInterval(3 * 3600 + 12 * 60), now: base, calendar: calendar), "Resets Fri 11:12 AM")
        XCTAssertEqual(UsageFormat.resetText(base.addingTimeInterval(2 * 86400), now: base, calendar: calendar), "Resets Sun 8:00 AM")
        XCTAssertEqual(UsageFormat.resetText(base.addingTimeInterval(9 * 86400), now: base, calendar: calendar), "Resets Jan 24")
        XCTAssertEqual(UsageFormat.resetText(base.addingTimeInterval(-5), now: base, calendar: calendar), "Resets now")
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
