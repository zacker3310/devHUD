import XCTest
@testable import devHUD

final class UsageScheduleTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRetryAfterHeaderForms() {
        XCTAssertEqual(ProviderError.retryAfterSeconds("2485"), 2485)
        XCTAssertEqual(ProviderError.retryAfterSeconds(" 60 "), 60)
        XCTAssertNil(ProviderError.retryAfterSeconds("soon"))
        XCTAssertNil(ProviderError.retryAfterSeconds("-5"))
        let future = Date().addingTimeInterval(120)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "GMT"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let parsed = ProviderError.retryAfterSeconds(f.string(from: future))
        XCTAssertNotNil(parsed)
        XCTAssertGreaterThan(parsed ?? 0, 100)
    }

    func testRateLimitedSchedulesNotFails() {
        var state = ProviderState()
        state.nextAttempt = now.addingTimeInterval(2485)
        XCTAssertEqual(AIUsageStore.delayBeforeNextFetch(state: state, interval: 120, now: now), 2485)
        XCTAssertEqual(state.statusText(now: now), "rate limited, retry in 41 min")
    }

    func testFreshCacheWaitsOutTheInterval() {
        var state = ProviderState()
        state.lastAttempt = now.addingTimeInterval(-30)
        XCTAssertEqual(AIUsageStore.delayBeforeNextFetch(state: state, interval: 120, now: now), 90)
        state.lastAttempt = now.addingTimeInterval(-500)
        XCTAssertEqual(AIUsageStore.delayBeforeNextFetch(state: state, interval: 120, now: now), 0)
        XCTAssertEqual(AIUsageStore.delayBeforeNextFetch(state: ProviderState(), interval: 120, now: now), 0)
    }

    func testFailuresBackOff() {
        var state = ProviderState()
        state.failures = 2
        state.lastAttempt = now
        XCTAssertEqual(AIUsageStore.delayBeforeNextFetch(state: state, interval: 120, now: now), 480)
    }

    func testCacheRoundTrip() {
        let store = UserDefaults(suiteName: "devHUD.tests.usagecache")!
        store.removePersistentDomain(forName: "devHUD.tests.usagecache")
        XCTAssertEqual(UsageCache.load(from: store), [:])
        let snap = UsageSnapshot(primary: UsageWindow(label: "5h", percentUsed: 12.5, resetsAt: now), secondary: [], fetchedAt: now, planLabel: "max")
        let cache = ["claude:/x": CachedProvider(snapshot: snap, attemptedAt: now, nextAttempt: now.addingTimeInterval(60))]
        UsageCache.save(cache, to: store)
        XCTAssertEqual(UsageCache.load(from: store), cache)
    }

    @MainActor
    func testStoreStartsFromTheCache() {
        let snap = UsageSnapshot(primary: UsageWindow(label: "5h", percentUsed: 7, resetsAt: nil), secondary: [], fetchedAt: now, planLabel: nil)
        let slot = ProviderSlot(id: "codex", kind: .codex, title: "Codex")
        let store = AIUsageStore(providers: [CodexUsageProvider()], cache: ["codex": CachedProvider(snapshot: snap, attemptedAt: now, nextAttempt: nil)])
        XCTAssertEqual(store.state(for: slot).lastGood, snap)
        XCTAssertEqual(store.state(for: slot).lastAttempt, now)
    }
}
