import Foundation

enum CodexSessionParser {
    static func windowLabel(minutes: Int) -> String {
        switch minutes {
        case 300: return "5h"
        case 10080: return "weekly"
        case let m where m % 1440 == 0: return "\(m / 1440)d"
        case let m where m % 60 == 0: return "\(m / 60)h"
        default: return "\(minutes)m"
        }
    }

    // Scans from the end for the newest `rate_limits` payload. Lines are the raw
    // JSONL rows of one Codex session rollout file.
    static func snapshot(fromLines lines: [String]) -> UsageSnapshot? {
        for line in lines.reversed() where line.contains("\"rate_limits\"") {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any] else { continue }
            let stamp = (root["timestamp"] as? String).flatMap(ISO8601.parse) ?? Date()
            guard let primary = window(limits["primary"], at: stamp) else { continue }
            let secondary = window(limits["secondary"], at: stamp).map { [$0] } ?? []
            let plan = limits["plan_type"] as? String
            return UsageSnapshot(primary: primary, secondary: secondary, fetchedAt: stamp, planLabel: plan)
        }
        return nil
    }

    private static func window(_ raw: Any?, at stamp: Date) -> UsageWindow? {
        guard let dict = raw as? [String: Any],
              let used = dict["used_percent"] as? Double else { return nil }
        let minutes = dict["window_minutes"] as? Int ?? 0
        var resets: Date?
        if let epoch = dict["resets_at"] as? Double {
            resets = Date(timeIntervalSince1970: epoch)
        } else if let seconds = dict["resets_in_seconds"] as? Double {
            resets = stamp.addingTimeInterval(seconds)
        }
        return UsageWindow(label: windowLabel(minutes: minutes), percentUsed: used, resetsAt: resets)
    }
}

struct CodexUsageProvider: UsageProvider {
    let slot = ProviderSlot(id: "codex", kind: .codex, title: "Codex")
    let sessionsURL: URL
    let maxFiles = 20
    // Rollout files reach hundreds of MB. rate_limits rides on every
    // token_count event, so the newest one is always near the tail.
    let tailBytes = 4 * 1024 * 1024

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        sessionsURL = home.appendingPathComponent(".codex/sessions")
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let files = try newestSessionFiles()
        guard !files.isEmpty else { throw ProviderError.noData("no Codex session files") }
        for file in files {
            guard let lines = try? tailLines(of: file) else { continue }
            if let snap = CodexSessionParser.snapshot(fromLines: lines) { return snap }
        }
        throw ProviderError.noData("no rate_limits in the \(files.count) newest sessions")
    }

    private func tailLines(of file: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()
        var lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        // The first line of a mid-file read is a fragment.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    private func newestSessionFiles() throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sessionsURL, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            throw ProviderError.noData("~/.codex/sessions missing")
        }
        var dated: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            dated.append((url, mtime))
        }
        return dated.sorted { $0.1 > $1.1 }.prefix(maxFiles).map(\.0)
    }
}
