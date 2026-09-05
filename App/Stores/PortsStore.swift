import Foundation
import Observation

// Everything lsof and libproc can tell us about one listener, gathered off
// the main actor. CPU percent needs the previous sample, so it is joined later.
struct RawServer: Sendable {
    let socket: ListeningSocket
    let cwd: String?
    let projectName: String?
    let startedAt: Date?
    let resources: ProcessResourceSample?
}

enum CPUDelta {
    // Percent of one core over the wall interval. A negative delta (pid reuse)
    // or an interval too short to mean anything yields nil rather than a spike.
    static func percent(previousSeconds: TimeInterval, currentSeconds: TimeInterval, wall: TimeInterval) -> Double? {
        guard wall >= 1 else { return nil }
        let delta = currentSeconds - previousSeconds
        guard delta >= 0 else { return nil }
        return delta / wall * 100
    }
}

@MainActor
@Observable
final class PortsStore {
    private(set) var servers: [DevServer] = []
    private(set) var lastError: String?
    private(set) var lastSampledAt: Date?

    let portless: PortlessStore
    let interval: TimeInterval = 4
    private var task: Task<Void, Never>?
    private var isSampling = false
    // Kind per server id, probed once and kept; unknown means try again.
    private var kinds: [String: ServerKind] = [:]
    private var probing: Set<String> = []
    // Keyed by pid and start time so a reused pid cannot inherit a dead
    // process's CPU baseline.
    private var previousCPU: [String: (seconds: TimeInterval, at: Date)] = [:]

    init(portless: PortlessStore) {
        self.portless = portless
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.sample()
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func sample() async {
        // The poll loop and a manual refresh can overlap across the lsof await;
        // let the in-flight sample win rather than racing two writes.
        guard !isSampling else { return }
        isSampling = true
        defer { isSampling = false }
        let raw: [RawServer]
        do {
            raw = try await Task.detached(priority: .utility) {
                // Fixed path on purpose: the app is unsandboxed, so a PATH
                // search would run whatever sits in /usr/local/bin.
                let output = try Shell.run("/usr/sbin/lsof", LsofParser.arguments).stdout
                return LsofParser.parse(output)
                    .filter { !LsofParser.isDenied($0.command) }
                    .map { socket in
                        let cwd = ProcessInspector.cwd(pid: socket.pid)
                        return RawServer(
                            socket: socket,
                            cwd: cwd,
                            projectName: ProcessInspector.projectName(cwd: cwd),
                            startedAt: ProcessInspector.startTime(pid: socket.pid),
                            resources: ProcessInspector.resources(pid: socket.pid)
                        )
                    }
            }.value
        } catch {
            servers = []
            lastError = error.localizedDescription
            HUDLog.ports.error("lsof failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let now = Date()
        var next: [String: (seconds: TimeInterval, at: Date)] = [:]
        var enriched: [DevServer] = []
        for item in raw {
            let socket = item.socket
            var cpu: Double?
            if let resources = item.resources {
                let key = "\(socket.pid):\(item.startedAt?.timeIntervalSince1970 ?? 0)"
                if let prev = previousCPU[key] {
                    cpu = CPUDelta.percent(previousSeconds: prev.seconds, currentSeconds: resources.cpuSeconds, wall: now.timeIntervalSince(prev.at))
                }
                next[key] = (resources.cpuSeconds, now)
            }
            let portlessHost = portless.routesByPort[socket.port]?.hostname
            var server = DevServer(
                pid: socket.pid,
                port: socket.port,
                command: socket.command,
                projectName: item.projectName,
                cwd: item.cwd,
                startedAt: item.startedAt,
                rssBytes: item.resources?.rssBytes,
                cpuPercent: cpu,
                portlessHost: portlessHost
            )
            server.kind = kind(for: server)
            enriched.append(server)
        }
        previousCPU = next
        servers = enriched.sorted { $0.port < $1.port }
        lastError = nil
        lastSampledAt = now
        let live = Set(servers.map(\.id))
        kinds = kinds.filter { live.contains($0.key) }
    }

    private func kind(for server: DevServer) -> ServerKind {
        if let known = ServerKind.known(command: server.command) { return known }
        if let host = server.portlessHost, PortlessRoutes.isTrustedHost(host) { return .web }
        if let cached = kinds[server.id], cached != .unknown { return cached }
        scheduleProbe(server)
        return .unknown
    }

    private func scheduleProbe(_ server: DevServer) {
        guard !probing.contains(server.id) else { return }
        probing.insert(server.id)
        let id = server.id
        let port = server.port
        Task { [weak self] in
            let kind = await ServerProbe.probe(port: port)
            await MainActor.run {
                guard let self else { return }
                self.probing.remove(id)
                self.kinds[id] = kind
                if let index = self.servers.firstIndex(where: { $0.id == id }) {
                    self.servers[index].kind = kind
                }
            }
        }
    }
}
