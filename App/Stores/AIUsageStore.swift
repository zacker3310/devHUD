import Foundation
import Observation
import os

enum HUDLog {
    static let subsystem = "cloud.acker.devhud"
    static let usage = Logger(subsystem: subsystem, category: "usage")
    static let ports = Logger(subsystem: subsystem, category: "ports")
    static let portless = Logger(subsystem: subsystem, category: "portless")
    static let hud = Logger(subsystem: subsystem, category: "hud")
}

@MainActor
@Observable
final class AIUsageStore {
    private(set) var states: [String: ProviderState] = [:]

    let providers: [any UsageProvider]
    let interval: TimeInterval = 120
    private var tasks: [String: Task<Void, Never>] = [:]

    var slots: [ProviderSlot] { providers.map(\.slot) }

    private var cache: [String: CachedProvider]

    init(providers: [any UsageProvider], cache: [String: CachedProvider] = UsageCache.load()) {
        self.providers = providers
        self.cache = cache
        for provider in providers {
            var state = ProviderState()
            if let cached = cache[provider.slot.id] {
                state.lastGood = cached.snapshot
                state.lastAttempt = cached.attemptedAt
                state.nextAttempt = cached.nextAttempt
            }
            states[provider.slot.id] = state
        }
    }

    // How long to wait before the next fetch for a slot: a Retry-After wins,
    // then the failure backoff, then the regular interval measured from the
    // last attempt (so a relaunch seconds after the last poll waits its turn).
    nonisolated static func delayBeforeNextFetch(state: ProviderState, interval: TimeInterval, now: Date = Date()) -> TimeInterval {
        if let next = state.nextAttempt, next > now { return next.timeIntervalSince(now) }
        if state.failures > 0 { return Backoff.delay(failures: state.failures) }
        guard let last = state.lastAttempt else { return 0 }
        return max(0, interval - now.timeIntervalSince(last))
    }

    func state(for slot: ProviderSlot) -> ProviderState { states[slot.id] ?? ProviderState() }

    func start() {
        for provider in providers { startLoop(provider) }
    }

    func stop() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
    }

    // A manual refresh clears the interval wait but never a Retry-After.
    func refreshNow() {
        for key in states.keys { states[key]?.lastAttempt = nil }
        stop()
        start()
    }

    // One loop per provider. A stalled or failing provider only delays itself.
    private func startLoop(_ provider: any UsageProvider) {
        tasks[provider.slot.id]?.cancel()
        tasks[provider.slot.id] = Task { [weak self] in
            while let self, !Task.isCancelled {
                let wait = AIUsageStore.delayBeforeNextFetch(state: self.state(for: provider.slot), interval: self.interval)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                await self.fetch(provider)
            }
        }
    }

    // State is re-read after the await: the main actor is reentrant, and a
    // refreshNow() can run a second fetch for the same provider meanwhile.
    // A cancelled fetch is not a failure and must not touch the backoff ladder.
    private func fetch(_ provider: any UsageProvider) async {
        let key = provider.slot.id
        let attempt = Date()
        states[key, default: ProviderState()].lastAttempt = attempt
        do {
            let snapshot = try await provider.fetchUsage()
            guard !Task.isCancelled else { return }
            var state = self.state(for: provider.slot)
            state.lastGood = snapshot
            state.lastError = nil
            state.failures = 0
            state.nextAttempt = nil
            states[key] = state
            HUDLog.usage.info("\(key, privacy: .public): \(snapshot.primary.label, privacy: .public) \(snapshot.primary.percentUsed, privacy: .public)% used")
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            var state = self.state(for: provider.slot)
            if case ProviderError.rateLimited(let after) = error {
                state.nextAttempt = attempt.addingTimeInterval(after)
                state.failures = 0
            } else {
                state.failures += 1
            }
            state.lastError = error.localizedDescription
            states[key] = state
            HUDLog.usage.error("\(key, privacy: .public) failed (\(state.failures)): \(error.localizedDescription, privacy: .public)")
        }
        let final = state(for: provider.slot)
        cache[key] = CachedProvider(snapshot: final.lastGood, attemptedAt: final.lastAttempt, nextAttempt: final.nextAttempt)
        UsageCache.save(cache)
    }
}
