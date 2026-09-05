import Foundation

// One live agent process: what it is, where it runs, and whether it is busy,
// waiting on the user, or idle.
struct AgentSession: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case busy
        case waiting
        case idle
    }

    let id: String
    let kind: ProviderID
    let name: String
    let surface: String
    let folder: String
    let state: State
    let since: Date
}

// Claude Code writes ~/.claude/sessions/<pid>.json for each running process:
// pid, cwd, status (busy | waiting | idle), startedAt (ms), name, entrypoint.
// This reads that file; liveness is checked separately against the kernel.
struct ClaudeSessionRecord: Equatable {
    let pid: pid_t
    let startedAt: Date?
    let session: AgentSession

    init?(json: [String: Any]) {
        guard let pid = (json["pid"] as? NSNumber)?.int32Value, pid > 0,
              let cwd = json["cwd"] as? String else { return nil }
        let state: AgentSession.State
        switch json["status"] as? String {
        case "busy": state = .busy
        case "waiting": state = .waiting
        default: state = .idle
        }
        let stamp = (json["statusUpdatedAt"] as? NSNumber)?.doubleValue ?? (json["updatedAt"] as? NSNumber)?.doubleValue
        let folder = (cwd as NSString).lastPathComponent
        self.pid = pid
        self.startedAt = (json["startedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        self.session = AgentSession(
            id: "claude:\(pid)",
            kind: .claude,
            name: (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? folder,
            surface: ClaudeSessionRecord.surface(json["entrypoint"] as? String),
            folder: folder,
            state: state,
            since: stamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        )
    }

    static func surface(_ entrypoint: String?) -> String {
        switch entrypoint {
        case "cli", nil: return "Terminal"
        case "claude-vscode": return "VS Code"
        case "claude-desktop", "claude-desktop-3p": return "Desktop"
        case "local-agent": return "Agent"
        case let other?: return other
        }
    }
}

// The one-line answer the ring gives: waiting beats working beats idle.
struct ActivitySummary: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case working
        case waiting
        case idle
    }

    let state: State
    let sessions: [AgentSession]

    init?(sessions: [AgentSession]) {
        guard !sessions.isEmpty else { return nil }
        self.sessions = sessions
        if sessions.contains(where: { $0.state == .waiting }) {
            state = .waiting
        } else if sessions.contains(where: { $0.state == .busy }) {
            state = .working
        } else {
            state = .idle
        }
    }

    var label: String {
        switch state {
        case .working: return "working"
        case .waiting: return "waiting for you"
        case .idle: return "idle"
        }
    }
}
