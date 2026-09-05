import Foundation
import Observation

// Runs a CLI the user is already signed into, through the login shell so the
// node-based ones resolve. Fixed command strings only; nothing interpolated.
enum WatchCLI {
    static func run(_ command: String) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            guard let result = try? Shell.run("/bin/zsh", ["-lc", command]), result.status == 0 else { return nil }
            return result.stdout
        }.value
    }

    static func exists(_ name: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.bun/bin", "\(home)/.local/bin"]
        return dirs.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") }
    }
}

@MainActor
@Observable
final class VercelStore {
    private(set) var summary = WatchSummary(items: [])
    private(set) var lastError: String?
    private(set) var lastSampledAt: Date?
    let isInstalled = WatchCLI.exists("vercel")
    private var task: Task<Void, Never>?

    func start() {
        guard isInstalled else { return }
        task?.cancel()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.sample()
                // Builds move fast; steady state does not.
                try? await Task.sleep(for: .seconds(self.summary.busy > 0 ? 30 : 120))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    func sample() async {
        guard let output = await WatchCLI.run("vercel ls --json 2>/dev/null") else {
            lastError = "vercel ls failed, run vercel login"
            return
        }
        summary = WatchSummary(items: VercelParser.latestPerProject(Data(output.utf8)))
        lastError = nil
        lastSampledAt = Date()
    }
}

@MainActor
@Observable
final class GitHubStore {
    private(set) var summary = WatchSummary(items: [])
    private(set) var lastError: String?
    private(set) var lastSampledAt: Date?
    let isInstalled = Shell.find("gh") != nil
    let interval: TimeInterval = 120
    private var task: Task<Void, Never>?

    func start() {
        guard isInstalled else { return }
        task?.cancel()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.sample()
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    // Four requests plus one per recently pushed repository: well inside the
    // 5000 per hour the API allows.
    func sample() async {
        guard let gh = Shell.find("gh") else { return }
        func api(_ path: String) async -> Data? {
            await Task.detached(priority: .utility) { () -> Data? in
                guard let result = try? Shell.run(gh, ["api", path]), result.status == 0 else { return nil }
                return Data(result.stdout.utf8)
            }.value
        }
        guard let notifications = await api("notifications") else {
            lastError = "gh api failed, run gh auth login"
            return
        }
        var items = GitHubParser.notifications(notifications)
        if let review = await api("search/issues?q=is:pr+is:open+review-requested:@me") {
            items += GitHubParser.pulls(review, kind: "review requested")
        }
        if let mine = await api("search/issues?q=is:pr+is:open+author:@me") {
            items += GitHubParser.pulls(mine, kind: "your PR")
        }
        if let repos = await api("user/repos?sort=pushed&per_page=4&affiliation=owner") {
            for repo in GitHubParser.recentRepos(repos) {
                if let runs = await api("repos/\(repo)/actions/runs?per_page=1"), let run = GitHubParser.latestRun(runs, repo: repo) {
                    items.append(run)
                }
            }
        }
        var seen = Set<String>()
        summary = WatchSummary(items: items.filter { seen.insert($0.id).inserted })
        lastError = nil
        lastSampledAt = Date()
    }
}
