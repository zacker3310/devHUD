import Foundation
import Observation

struct PortlessRoute: Decodable, Equatable, Sendable {
    let hostname: String
    let port: Int
    let pid: Int?
}

enum PortlessRoutes {
    // routes.json is written by other software. Only a bare hostname under
    // .localhost is trusted as a link target; anything else stays a label.
    static func isTrustedHost(_ host: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        let lower = host.lowercased()
        guard !lower.isEmpty, lower.count <= 253, lower.allSatisfy({ allowed.contains($0) }) else { return false }
        guard !lower.hasPrefix(".") && !lower.hasPrefix("-") && !lower.contains("..") else { return false }
        return lower == "localhost" || lower.hasSuffix(".localhost")
    }

    // ~/.portless/routes.json. The CLI writes RouteMapping records; accept both
    // an array and an object keyed by hostname, since the on-disk shape is not
    // documented.
    static func decode(_ data: Data) throws -> [Int: PortlessRoute] {
        let decoder = JSONDecoder()
        var routes: [PortlessRoute] = []
        if let list = try? decoder.decode([PortlessRoute].self, from: data) {
            routes = list
        } else if let map = try? decoder.decode([String: PortlessRoute].self, from: data) {
            routes = Array(map.values)
        } else if let wrapper = try? decoder.decode([String: [PortlessRoute]].self, from: data),
                  let list = wrapper["routes"] {
            routes = list
        } else {
            throw ProviderError.badResponse("routes.json has an unknown shape")
        }
        var byPort: [Int: PortlessRoute] = [:]
        for route in routes { byPort[route.port] = route }
        return byPort
    }
}

@MainActor
@Observable
final class PortlessStore {
    private(set) var routesByPort: [Int: PortlessRoute] = [:]
    private(set) var isAvailable = false
    private(set) var lastError: String?

    let routesURL: URL
    let interval: TimeInterval = 12
    private var task: Task<Void, Never>?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        routesURL = home.appendingPathComponent(".portless/routes.json")
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.refresh()
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh() {
        guard let data = FileManager.default.contents(atPath: routesURL.path) else {
            isAvailable = false
            routesByPort = [:]
            return
        }
        do {
            routesByPort = try PortlessRoutes.decode(data)
            isAvailable = true
            lastError = nil
        } catch {
            // A file we cannot read is a file we cannot trust: drop old routes
            // rather than keep tagging listeners with stale hostnames.
            routesByPort = [:]
            isAvailable = false
            lastError = error.localizedDescription
            HUDLog.portless.error("routes.json decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
