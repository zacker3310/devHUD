import Foundation

struct ListeningSocket: Equatable, Hashable {
    let pid: pid_t
    let command: String
    let host: String
    let port: Int
}

enum LsofParser {
    static let arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-w", "+c", "0", "-F", "pcn"]

    // System daemons that listen on TCP but are never a dev server.
    static let denylist: [String] = [
        "rapportd", "controlcenter", "sharingd", "ardagent", "launchd", "cupsd", "airplayxpc",
        "identityservicesd", "remoted", "bluetoothd", "wifiagent", "mdnsresponder",
        "apsd", "corespeechd", "contextstored", "screensharingd", "syncdefaultsd",
        "dropbox", "onedrive", "spotify", "1password", "logioptionsplus", "logitune",
        "creative cloud", "adobe", "google chrome", "com.docker", "docker", "figma_agent",
        "microsoft teams", "slack", "zoom.us", "discord", "notion", "setapp", "raycast",
        "bartender", "cleanshot", "fsevents", "vmware", "parallels", "tailscaled",
    ]

    static func isDenied(_ command: String) -> Bool {
        let lower = command.lowercased()
        return denylist.contains { lower.hasPrefix($0) }
    }

    // Parses `lsof -F pcn` field output: one `p` line per process, then `c`,
    // then one `n` line per socket. Dedupes v4/v6 listeners on the same port.
    static func parse(_ output: String) -> [ListeningSocket] {
        var results: [ListeningSocket] = []
        var seen = Set<String>()
        var pid: pid_t?
        var command = ""
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p":
                pid = pid_t(value).flatMap { $0 > 0 ? $0 : nil }
                command = ""
            case "c":
                command = value
            case "n":
                guard let pid, let split = splitAddress(value) else { continue }
                let key = "\(pid):\(split.port)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                results.append(ListeningSocket(pid: pid, command: command, host: split.host, port: split.port))
            default:
                continue
            }
        }
        return results
    }

    static func splitAddress(_ name: String) -> (host: String, port: Int)? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        guard let port = Int(name[name.index(after: colon)...]) else { return nil }
        return (String(name[..<colon]), port)
    }
}
