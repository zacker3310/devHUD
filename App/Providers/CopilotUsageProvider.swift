import Foundation

enum CopilotUsageDecoder {
    static let labels: [String: String] = [
        "premium_interactions": "Premium",
        "chat": "Chat",
        "completions": "Completions",
    ]
    static let order = ["premium_interactions", "chat", "completions"]

    static func decode(_ data: Data, now: Date = Date(), calendar: Calendar = .current) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.badResponse("top level is not an object")
        }
        guard let snapshots = root["quota_snapshots"] as? [String: Any] else {
            throw ProviderError.noData("no quota_snapshots")
        }
        let resets = (root["quota_reset_date"] as? String).flatMap { resetDate($0, calendar: calendar) }
        var windows: [UsageWindow] = []
        for key in order {
            guard let q = snapshots[key] as? [String: Any] else { continue }
            let hasQuota = q["has_quota"] as? Bool ?? false
            let unlimited = q["unlimited"] as? Bool ?? false
            guard hasQuota, !unlimited, let remaining = q["percent_remaining"] as? Double else { continue }
            let used = min(max(100 - remaining, 0), 100)
            windows.append(UsageWindow(label: labels[key] ?? key, percentUsed: used, resetsAt: resets))
        }
        guard let primary = windows.first else { throw ProviderError.noData("no quota with an entitlement") }
        let plan = root["copilot_plan"] as? String
        return UsageSnapshot(primary: primary, secondary: Array(windows.dropFirst()), fetchedAt: now, planLabel: plan)
    }

    // "2026-10-01" is a calendar date, not an instant. Resolve it to local midnight.
    static func resetDate(_ raw: String, calendar: Calendar) -> Date? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

struct CopilotUsageProvider: UsageProvider {
    let slot = ProviderSlot(id: "copilot", kind: .copilot, title: "Copilot")
    let endpoint = URL(string: "https://api.github.com/copilot_internal/user")!

    func fetchUsage() async throws -> UsageSnapshot {
        let token = try await Task.detached(priority: .utility) { try readToken() }.value
        var request = URLRequest(url: endpoint)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("devHUD/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ProviderError.from(http)
        }
        return try CopilotUsageDecoder.decode(data)
    }

    // Reuses the gh CLI's stored token. No new auth flow, no copy on disk.
    private func readToken() throws -> String {
        guard let gh = Shell.find("gh") else { throw ProviderError.missingCredentials("gh not installed") }
        let result = try Shell.run(gh, ["auth", "token"])
        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !token.isEmpty else {
            throw ProviderError.missingCredentials("gh auth token exited \(result.status)")
        }
        return token
    }
}
