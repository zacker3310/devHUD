import Foundation

struct DevServer: Identifiable, Equatable {
    let pid: pid_t
    let port: Int
    let command: String
    let projectName: String?
    let cwd: String?
    let startedAt: Date?
    let rssBytes: UInt64?
    let cpuPercent: Double?
    var portlessHost: String?
    var kind: ServerKind = .unknown

    var id: String { "\(pid):\(port)" }

    var displayName: String { projectName ?? command }

    var addressText: String {
        if let portlessHost { return portlessHost }
        return "localhost:\(port)"
    }

    // Where a click goes. A trusted portless hostname (*.localhost) fronts the
    // app over HTTP; anything else falls back to the raw port.
    var url: URL? {
        guard kind.isOpenable else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        if let portlessHost, PortlessRoutes.isTrustedHost(portlessHost) {
            components.host = portlessHost
        } else {
            components.host = "localhost"
            components.port = port
        }
        return components.url
    }
}

enum ProjectName {
    // The cwd basename, or the package.json name when one exists. Scoped npm
    // names drop the scope. Root and home are not projects.
    static func infer(cwd: String, packageJSON: Data?, home: String) -> String? {
        if let data = packageJSON,
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var name = root["name"] as? String, !name.isEmpty {
            if name.hasPrefix("@"), let slash = name.firstIndex(of: "/") {
                name = String(name[name.index(after: slash)...])
            }
            return name
        }
        let path = (cwd as NSString).standardizingPath
        if path == "/" || path == home || path.isEmpty { return nil }
        return (path as NSString).lastPathComponent
    }
}
