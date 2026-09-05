import Foundation
import Observation

// Live agent sessions per provider kind. Claude Code publishes a record per
// process; Codex is inferred from a rollout file being written right now.
@MainActor
@Observable
final class ActivityStore {
    private(set) var sessions: [AgentSession] = []

    let claudeSessionsDirectory: URL
    let codexSessionsDirectory: URL
    let interval: TimeInterval = 5
    // A rollout written this recently means Codex is mid-turn.
    static let codexBusyWindow: TimeInterval = 8

    private var task: Task<Void, Never>?
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: Int32 = -1

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        claudeSessionsDirectory = home.appendingPathComponent(".claude/sessions")
        codexSessionsDirectory = home.appendingPathComponent(".codex/sessions")
    }

    func summary(for kind: ProviderID) -> ActivitySummary? {
        ActivitySummary(sessions: sessions.filter { $0.kind == kind })
    }

    var anyActive: Bool {
        sessions.contains { $0.state != .idle }
    }

    func start() {
        task?.cancel()
        watchDirectory()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.rescan()
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        watcher?.cancel()
        watcher = nil
    }

    func rescan() {
        let claude = ActivityStore.readClaudeSessions(in: claudeSessionsDirectory)
        let codex = ActivityStore.readCodexActivity(in: codexSessionsDirectory)
        let found = claude + codex
        if found != sessions { sessions = found }
    }

    // Records whose process is gone, or whose pid now belongs to a different
    // process, are dropped: the file outlives a crashed session.
    nonisolated static func readClaudeSessions(in directory: URL, now: Date = Date()) -> [AgentSession] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { name -> AgentSession? in
            guard let data = FileManager.default.contents(atPath: directory.appendingPathComponent(name).path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let record = ClaudeSessionRecord(json: json),
                  isAlive(pid: record.pid, startedAt: record.startedAt) else { return nil }
            return record.session
        }.sorted { $0.since > $1.since }
    }

    nonisolated static func isAlive(pid: pid_t, startedAt: Date?) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
        guard let startedAt, let actual = ProcessInspector.startTime(pid: pid) else { return true }
        return abs(actual.timeIntervalSince(startedAt)) < 120
    }

    nonisolated static func readCodexActivity(in directory: URL, now: Date = Date()) -> [AgentSession] {
        guard let newest = newestRollout(in: directory),
              let modified = (try? newest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              now.timeIntervalSince(modified) < codexBusyWindow else { return [] }
        return [AgentSession(id: "codex:\(newest.lastPathComponent)", kind: .codex, name: "Codex", surface: "Codex", folder: "", state: .busy, since: modified)]
    }

    nonisolated static func newestRollout(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var best: (URL, Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if best == nil || date > best!.1 { best = (url, date) }
        }
        return best?.0
    }

    // Claude Code rewrites the session file on every status change; a
    // directory watch turns that into an immediate rescan.
    private func watchDirectory() {
        watcher?.cancel()
        watchedDescriptor = open(claudeSessionsDirectory.path, O_EVTONLY)
        guard watchedDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: watchedDescriptor, eventMask: [.write, .extend, .attrib, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        let descriptor = watchedDescriptor
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }
}
