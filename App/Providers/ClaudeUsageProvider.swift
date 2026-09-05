import Foundation

enum ClaudeUsageDecoder {
    static let labels: [String: String] = [
        "five_hour": "5h",
        "seven_day": "7d",
        "seven_day_opus": "7d Opus",
        "seven_day_sonnet": "7d Sonnet",
        "seven_day_oauth_apps": "7d apps",
    ]

    // The endpoint is unofficial. Newer responses carry a `limits` array with
    // per-model scoped windows (this is where a Fable-specific weekly limit
    // lives); older ones only have flat keys. Decode the array first, fall
    // back to any top-level object with a numeric `utilization`.
    static func decode(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.badResponse("top level is not an object")
        }
        if let limits = root["limits"] as? [[String: Any]] {
            let windows = limits.compactMap(limitWindow)
            if let primary = windows.first {
                return UsageSnapshot(primary: primary, secondary: Array(windows.dropFirst()), fetchedAt: now, planLabel: nil)
            }
        }
        #if DEBUG
        NSLog("claude usage keys: %@", root.map { key, value -> String in
            if let dict = value as? [String: Any] { return "\(key)=\(dict["utilization"] ?? "nil") resets=\(dict["resets_at"] ?? "nil")" }
            return "\(key)=\(value)"
        }.sorted().joined(separator: " | "))
        #endif
        var windows: [(key: String, window: UsageWindow)] = []
        for (key, value) in root {
            guard let dict = value as? [String: Any],
                  let utilization = dict["utilization"] as? Double else { continue }
            // Unknown keys are kept only once they carry a value; the endpoint
            // ships internal windows at 0 that mean nothing to the user.
            guard labels[key] != nil || utilization > 0 else { continue }
            let resets = (dict["resets_at"] as? String).flatMap(ISO8601.parse)
            windows.append((key, UsageWindow(label: labels[key] ?? key, percentUsed: utilization, resetsAt: resets)))
        }
        guard !windows.isEmpty else { throw ProviderError.noData("no utilization windows in response") }
        let order = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_oauth_apps"]
        windows.sort { a, b in
            let ia = order.firstIndex(of: a.key) ?? order.count
            let ib = order.firstIndex(of: b.key) ?? order.count
            return ia == ib ? a.key < b.key : ia < ib
        }
        let primary = windows[0].window
        let secondary = windows.dropFirst().map(\.window)
        return UsageSnapshot(primary: primary, secondary: Array(secondary), fetchedAt: now, planLabel: nil)
    }
}

extension ClaudeUsageDecoder {
    // One entry of the `limits` array: kind session | weekly_all | weekly_scoped,
    // percent, resets_at, and for scoped limits the model's display name.
    static func limitWindow(_ entry: [String: Any]) -> UsageWindow? {
        guard let percent = entry["percent"] as? Double, let kind = entry["kind"] as? String else { return nil }
        let resets = (entry["resets_at"] as? String).flatMap(ISO8601.parse)
        let label: String
        switch kind {
        case "session": label = "5h"
        case "weekly_all": label = "7d"
        case "weekly_scoped":
            let scope = entry["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            let name = (model?["display_name"] as? String) ?? (scope?["surface"] as? String) ?? "scoped"
            label = "7d \(name)"
        default: label = kind
        }
        return UsageWindow(label: label, percentUsed: percent, resetsAt: resets)
    }
}

struct ClaudeUsageProvider: UsageProvider {
    let slot: ProviderSlot
    let credentialsURL: URL
    let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    // One provider per Claude Code config directory: that is how Claude Code
    // itself keeps a personal and a work login apart (CLAUDE_CONFIG_DIR).
    init(configDir: URL) {
        credentialsURL = configDir.appendingPathComponent(".credentials.json")
        let plan = ClaudeUsageProvider.subscriptionType(at: credentialsURL)
        slot = ProviderSlot(
            id: "claude:" + configDir.path,
            kind: .claude,
            title: ClaudeUsageProvider.title(plan: plan, dirName: configDir.lastPathComponent)
        )
    }

    static func title(plan: String?, dirName: String) -> String {
        if let plan, !plan.isEmpty { return "Claude " + plan.prefix(1).uppercased() + plan.dropFirst() }
        return dirName == ".claude" ? "Claude" : "Claude (\(dirName.replacingOccurrences(of: ".claude", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "-_"))))"
    }

    private static func subscriptionType(at url: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["subscriptionType"] as? String
    }

    // Every config directory that holds a login. `claudeConfigDirs` in
    // UserDefaults overrides discovery; otherwise CLAUDE_CONFIG_DIR, ~/.claude,
    // and any ~/.claude-* or ~/.claude_* sibling with a credentials file.
    static func discoverConfigDirs(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        configured: [String]? = UserDefaults.standard.stringArray(forKey: "claudeConfigDirs"),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeEntries: [String]? = nil,
        hasCredentials: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.appendingPathComponent(".credentials.json").path) }
    ) -> [URL] {
        if let configured, !configured.isEmpty {
            return configured.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
        }
        var dirs: [URL] = []
        if let env = environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            dirs.append(URL(fileURLWithPath: NSString(string: env).expandingTildeInPath))
        }
        dirs.append(home.appendingPathComponent(".claude"))
        let entries = homeEntries ?? ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [])
        for name in entries.sorted() where name.hasPrefix(".claude-") || name.hasPrefix(".claude_") {
            dirs.append(home.appendingPathComponent(name))
        }
        var seen = Set<String>()
        return dirs.filter { seen.insert($0.standardizedFileURL.path).inserted && hasCredentials($0) }
    }

    static func discovered() -> [ClaudeUsageProvider] {
        let dirs = discoverConfigDirs()
        if dirs.isEmpty { return [ClaudeUsageProvider(configDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"))] }
        return dirs.map(ClaudeUsageProvider.init(configDir:))
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let token = try readToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("devHUD/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            #if DEBUG
            NSLog("claude usage HTTP %d retry-after=%@ ratelimit=%@ body=%@", http.statusCode,
                  http.value(forHTTPHeaderField: "Retry-After") ?? "-",
                  http.allHeaderFields.filter { "\($0.key)".lowercased().contains("ratelimit") || "\($0.key)".lowercased().contains("retry") }.description,
                  String(decoding: data.prefix(300), as: UTF8.self))
            #endif
            throw ProviderError.from(http)
        }
        return try ClaudeUsageDecoder.decode(data)
    }

    // Read-only. Claude Code owns and refreshes this file.
    private func readToken() throws -> String {
        guard let data = try? Data(contentsOf: credentialsURL) else {
            throw ProviderError.missingCredentials("\(credentialsURL.path) not readable")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw ProviderError.missingCredentials("no claudeAiOauth.accessToken")
        }
        return token
    }
}
