import AppKit
import Foundation
import Observation

// Pure builders for the shell we hand to the login shell. Tested.
enum ServerCommand {
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // The relaunch runs in the user's login shell so the environment matches
    // Terminal, but the command word is the absolute executable the kernel
    // reported, not argv[0]. Every token is quoted: they come from another
    // process and must never be parsed as shell. nohup + background detaches
    // it from devHUD; output lands in a log file.
    static func relaunchScript(executable: String, arguments: [String], cwd: String, log: String) -> String {
        let words = [executable] + Array(arguments.dropFirst())
        let command = words.map(shellQuote).joined(separator: " ")
        return "cd \(shellQuote(cwd)) && nohup \(command) </dev/null >>\(shellQuote(log)) 2>&1 &"
    }

    // The name comes from a package.json the app did not write: keep it to a
    // safe character set, never a path.
    static func safeLogName(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        var name = String(raw.filter { allowed.contains($0) }.prefix(64))
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? "server" : name
    }

    static func logURL(for server: DevServer, logs: URL) -> URL {
        logs.appendingPathComponent("\(safeLogName(server.projectName ?? server.command))-\(server.port).log")
    }
}

enum PendingAction: Equatable {
    case confirmKill(until: Date)
    case killing
    case restarting
    case failed(String)
}

@MainActor
@Observable
final class ServerActions {
    private(set) var pending: [String: PendingAction] = [:]
    let ports: PortsStore
    let logsDirectory: URL
    static let confirmWindow: TimeInterval = 5
    static let termGrace: TimeInterval = 3

    var editorApp: String {
        UserDefaults.standard.string(forKey: "editorApp") ?? "Visual Studio Code"
    }

    init(ports: PortsStore) {
        self.ports = ports
        logsDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/devHUD")
    }

    func state(for server: DevServer) -> PendingAction? {
        if case .confirmKill(let until) = pending[server.id], until < Date() {
            pending[server.id] = nil
            return nil
        }
        return pending[server.id]
    }

    // MARK: open

    func openEditor(_ server: DevServer) {
        guard let cwd = server.cwd else { return }
        launch("/usr/bin/open", ["-a", editorApp, cwd], for: server)
    }

    func openTerminal(_ server: DevServer) {
        guard let cwd = server.cwd else { return }
        launch("/usr/bin/open", ["-a", "Terminal", cwd], for: server)
    }

    private func launch(_ executable: String, _ arguments: [String], for server: DevServer) {
        Task.detached(priority: .userInitiated) {
            let result = try? Shell.run(executable, arguments)
            if result?.status != 0 {
                await MainActor.run { self.pending[server.id] = .failed("could not open") }
            }
        }
    }

    // MARK: kill

    func requestKill(_ server: DevServer) {
        pending[server.id] = .confirmKill(until: Date().addingTimeInterval(ServerActions.confirmWindow))
    }

    func cancelKill(_ server: DevServer) {
        if case .confirmKill = pending[server.id] { pending[server.id] = nil }
    }

    // A pid can be reused between the sample and the click; the start time
    // must still match the row the user saw.
    static func isSameProcess(_ server: DevServer) -> Bool {
        guard let started = server.startedAt, let now = ProcessInspector.startTime(pid: server.pid) else { return false }
        return abs(now.timeIntervalSince(started)) < 1
    }

    func confirmKill(_ server: DevServer) {
        guard ServerActions.isSameProcess(server) else {
            pending[server.id] = .failed("process changed, not killed")
            return
        }
        pending[server.id] = .killing
        Task { [weak self] in
            let ok = await ServerActions.terminate(pid: server.pid, startedAt: server.startedAt)
            guard let self else { return }
            self.pending[server.id] = ok ? nil : .failed("still running")
            await self.ports.sample()
        }
    }

    // SIGTERM, a grace period, then SIGKILL. Returns true once the pid is gone.
    // A pid that now belongs to a process with a different start time is
    // treated as gone: the kernel reused it, and it is not ours to signal.
    nonisolated static func terminate(pid: pid_t, startedAt: Date?) async -> Bool {
        guard pid > 0 else { return false }
        func stillOurs() -> Bool {
            guard kill(pid, 0) == 0 else { return false }
            guard let startedAt, let now = ProcessInspector.startTime(pid: pid) else { return true }
            return abs(now.timeIntervalSince(startedAt)) < 1
        }
        if kill(pid, SIGTERM) != 0 && errno != ESRCH { return false }
        let deadline = Date().addingTimeInterval(termGrace)
        while Date() < deadline {
            if !stillOurs() { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard stillOurs() else { return true }
        kill(pid, SIGKILL)
        try? await Task.sleep(for: .milliseconds(300))
        return !stillOurs()
    }

    // MARK: restart

    func restart(_ server: DevServer) {
        guard let cwd = server.cwd else {
            pending[server.id] = .failed("no working directory")
            return
        }
        guard ServerActions.isSameProcess(server) else {
            pending[server.id] = .failed("process changed, not restarted")
            return
        }
        pending[server.id] = .restarting
        let log = ServerCommand.logURL(for: server, logs: logsDirectory).path
        let logsDirectory = logsDirectory
        Task { [weak self] in
            let procArgs = ProcessInspector.arguments(pid: server.pid)
            guard let self else { return }
            guard let procArgs, !procArgs.arguments.isEmpty else {
                self.pending[server.id] = .failed("could not read command")
                return
            }
            guard await ServerActions.terminate(pid: server.pid, startedAt: server.startedAt) else {
                self.pending[server.id] = .failed("still running")
                return
            }
            let script = ServerCommand.relaunchScript(executable: procArgs.executable, arguments: procArgs.arguments, cwd: cwd, log: log)
            let status = await Task.detached(priority: .userInitiated) { () -> Int32 in
                try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                return (try? Shell.run("/bin/zsh", ["-lc", script]).status) ?? -1
            }.value
            self.pending[server.id] = status == 0 ? nil : .failed("relaunch exited \(status)")
            try? await Task.sleep(for: .seconds(1))
            await self.ports.sample()
        }
    }

    func prune(keeping ids: Set<String>) {
        pending = pending.filter { ids.contains($0.key) }
    }
}
