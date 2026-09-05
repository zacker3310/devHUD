import Foundation

// One thing worth a glance from a hosted service: a deployment, a PR, a run.
struct WatchItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case ok
        case busy
        case attention
        case failed
    }

    let id: String
    let title: String
    let subtitle: String
    let state: State
    let at: Date?
    let url: URL?
}

struct WatchSummary: Equatable, Sendable {
    let items: [WatchItem]
    var failed: Int { items.filter { $0.state == .failed }.count }
    var busy: Int { items.filter { $0.state == .busy }.count }
    var attention: Int { items.filter { $0.state == .attention }.count }
    // What the pill shows: things that want a look.
    var badge: Int { failed + busy + attention }
    var worst: WatchItem.State {
        if failed > 0 { return .failed }
        if attention > 0 { return .attention }
        if busy > 0 { return .busy }
        return .ok
    }
}

enum WatchDate {
    static func iso(_ text: Any?) -> Date? { (text as? String).flatMap(ISO8601.parse) }
    static func millis(_ value: Any?) -> Date? { (value as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } }
}

// `vercel ls --json`: { contextName, deployments: [{ name, url, state, target, createdAt, ready, meta }] }
enum VercelParser {
    static func latestPerProject(_ data: Data, now: Date = Date()) -> [WatchItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deployments = root["deployments"] as? [[String: Any]] else { return [] }
        var newest: [String: [String: Any]] = [:]
        for d in deployments {
            guard let name = d["name"] as? String else { continue }
            let created = (d["createdAt"] as? Double) ?? 0
            if let current = newest[name], ((current["createdAt"] as? Double) ?? 0) >= created { continue }
            newest[name] = d
        }
        return newest.values.map { d in
            let name = d["name"] as? String ?? "?"
            let state = (d["state"] as? String ?? "").uppercased()
            let target = d["target"] as? String ?? "preview"
            let meta = d["meta"] as? [String: Any] ?? [:]
            let message = (meta["githubCommitMessage"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? ""
            let url = (d["url"] as? String).flatMap { URL(string: "https://\($0)") }
            return WatchItem(
                id: "vercel:\(name)",
                title: name,
                subtitle: [state.lowercased(), target, message].filter { !$0.isEmpty }.joined(separator: " · "),
                state: itemState(state),
                at: WatchDate.millis(d["createdAt"]),
                url: url
            )
        }.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
    }

    static func itemState(_ state: String) -> WatchItem.State {
        switch state {
        case "READY": return .ok
        case "ERROR": return .failed
        case "BUILDING", "QUEUED", "INITIALIZING": return .busy
        case "CANCELED": return .attention
        default: return .attention
        }
    }
}

// gh api shapes: notifications, search/issues, actions/runs.
enum GitHubParser {
    static func notifications(_ data: Data) -> [WatchItem] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { n in
            guard let id = n["id"] as? String, let subject = n["subject"] as? [String: Any] else { return nil }
            let repo = (n["repository"] as? [String: Any])?["full_name"] as? String ?? ""
            let type = subject["type"] as? String ?? ""
            let reason = n["reason"] as? String ?? ""
            return WatchItem(
                id: "gh:notification:\(id)",
                title: subject["title"] as? String ?? type,
                subtitle: [repo, type.lowercased(), reason.replacingOccurrences(of: "_", with: " ")].filter { !$0.isEmpty }.joined(separator: " · "),
                state: .attention,
                at: WatchDate.iso(n["updated_at"]),
                url: htmlURL(fromAPI: subject["url"] as? String, repo: repo)
            )
        }
    }

    // "https://api.github.com/repos/o/r/pulls/12" -> "https://github.com/o/r/pull/12"
    static func htmlURL(fromAPI api: String?, repo: String) -> URL? {
        guard let api else { return URL(string: "https://github.com/\(repo)") }
        var path = api.replacingOccurrences(of: "https://api.github.com/repos/", with: "")
        path = path.replacingOccurrences(of: "/pulls/", with: "/pull/")
        return URL(string: "https://github.com/\(path)")
    }

    static func pulls(_ data: Data, kind: String) -> [WatchItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { pr in
            guard let number = pr["number"] as? Int, let title = pr["title"] as? String else { return nil }
            let repoURL = pr["repository_url"] as? String ?? ""
            let repo = repoURL.replacingOccurrences(of: "https://api.github.com/repos/", with: "")
            let draft = pr["draft"] as? Bool ?? false
            return WatchItem(
                id: "gh:pr:\(repo)#\(number)",
                title: title,
                subtitle: [repo, "#\(number)", kind, draft ? "draft" : ""].filter { !$0.isEmpty }.joined(separator: " · "),
                state: kind == "review requested" ? .attention : .ok,
                at: WatchDate.iso(pr["updated_at"]),
                url: (pr["html_url"] as? String).flatMap(URL.init(string:))
            )
        }
    }

    static func latestRun(_ data: Data, repo: String) -> WatchItem? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let run = (root["workflow_runs"] as? [[String: Any]])?.first else { return nil }
        let status = run["status"] as? String ?? ""
        let conclusion = run["conclusion"] as? String
        let state: WatchItem.State
        switch (status, conclusion) {
        case ("completed", "success"?): state = .ok
        case ("completed", "failure"?), ("completed", "timed_out"?): state = .failed
        case ("completed", _): state = .attention
        default: state = .busy
        }
        return WatchItem(
            id: "gh:run:\(repo)",
            title: repo,
            subtitle: [run["name"] as? String ?? "workflow", run["head_branch"] as? String ?? "", conclusion ?? status].filter { !$0.isEmpty }.joined(separator: " · "),
            state: state,
            at: WatchDate.iso(run["updated_at"]),
            url: (run["html_url"] as? String).flatMap(URL.init(string:))
        )
    }

    static func recentRepos(_ data: Data, limit: Int = 4) -> [String] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.prefix(limit).compactMap { $0["full_name"] as? String }
    }
}
