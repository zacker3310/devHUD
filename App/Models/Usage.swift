import Foundation

enum ProviderID: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case copilot
    case cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .copilot: return "Copilot"
        case .cursor: return "Cursor"
        }
    }

    // Asset catalog names; Simple Icons marks, see THIRD_PARTY.md.
    var brandImageName: String {
        switch self {
        case .claude: return "brand-claude"
        case .codex: return "brand-openai"
        case .copilot: return "brand-copilot"
        case .cursor: return "brand-cursor"
        }
    }
}

// How close a window is to its limit. Colour names the state; the glyph
// names the provider.
enum UsageBand: Equatable, Sendable {
    case ample
    case watch
    case critical
    case exhausted

    init(percentUsed: Double) {
        switch percentUsed {
        case ..<50: self = .ample
        case ..<70: self = .watch
        case ..<100: self = .critical
        default: self = .exhausted
        }
    }
}

// One provider instance. Two Claude logins are two slots of kind .claude.
struct ProviderSlot: Hashable, Identifiable, Sendable {
    let id: String
    let kind: ProviderID
    let title: String
}

struct UsageWindow: Sendable, Equatable, Codable {
    let label: String
    let percentUsed: Double
    let resetsAt: Date?
}

struct UsageSnapshot: Sendable, Equatable, Codable {
    let primary: UsageWindow
    let secondary: [UsageWindow]
    let fetchedAt: Date
    let planLabel: String?
}

struct ProviderState: Sendable {
    var lastGood: UsageSnapshot?
    var lastError: String?
    var failures = 0
    var lastAttempt: Date?
    // Set from a Retry-After header; the loop and a relaunch both honor it.
    var nextAttempt: Date?

    var hasData: Bool { lastGood != nil }

    // A reading older than an hour, or one the provider refused to refresh,
    // is shown dimmed rather than hidden.
    func isStale(now: Date = Date()) -> Bool {
        if let nextAttempt, nextAttempt > now { return true }
        guard let lastGood else { return false }
        return now.timeIntervalSince(lastGood.fetchedAt) > 3600
    }

    // What the card says under a provider with no fresh data.
    func statusText(now: Date = Date()) -> String? {
        if let nextAttempt, nextAttempt > now {
            let minutes = max(Int(nextAttempt.timeIntervalSince(now) / 60), 1)
            return "rate limited, retry in \(minutes) min"
        }
        return lastError
    }
}

// Last snapshot and schedule per provider slot, kept across launches so a
// relaunch shows numbers at once and does not spend another request.
struct CachedProvider: Codable, Equatable {
    var snapshot: UsageSnapshot?
    var attemptedAt: Date?
    var nextAttempt: Date?
}

enum UsageCache {
    static let key = "usageCache"

    static func load(from store: UserDefaults = .standard) -> [String: CachedProvider] {
        guard let data = store.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: CachedProvider].self, from: data)) ?? [:]
    }

    static func save(_ cache: [String: CachedProvider], to store: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(cache) { store.set(data, forKey: key) }
    }
}
