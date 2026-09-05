import Foundation
import Observation

// Running containers through the docker CLI. The list is cheap and polled
// often; stats cost over a second and are polled less.
@MainActor
@Observable
final class DockerStore {
    private(set) var containers: [DockerContainer] = []
    private(set) var isAvailable = false
    private(set) var pending: [String: PendingAction] = [:]

    let listInterval: TimeInterval = 5
    let statsInterval: TimeInterval = 15
    private var listTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var stats: [String: DockerStats.Sample] = [:]
    private var kinds: [Int: ServerKind] = [:]
    private var probing: Set<Int> = []
    private let binary: String?

    nonisolated static func findBinary(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let candidates = [
            "/usr/local/bin/docker", "/opt/homebrew/bin/docker",
            home.appendingPathComponent(".orbstack/bin/docker").path,
            home.appendingPathComponent(".docker/bin/docker").path,
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    init(binary: String? = DockerStore.findBinary()) {
        self.binary = binary
    }

    var isInstalled: Bool { binary != nil }

    func start() {
        guard binary != nil else { return }
        listTask?.cancel()
        statsTask?.cancel()
        listTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.sampleList()
                try? await Task.sleep(for: .seconds(self.listInterval))
            }
        }
        statsTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.sampleStats()
                try? await Task.sleep(for: .seconds(self.statsInterval))
            }
        }
    }

    func stop() {
        listTask?.cancel()
        statsTask?.cancel()
        listTask = nil
        statsTask = nil
    }

    private func run(_ arguments: [String]) async -> Shell.Result? {
        guard let binary else { return nil }
        return await Task.detached(priority: .utility) { try? Shell.run(binary, arguments) }.value
    }

    func sampleList() async {
        guard let result = await run(["ps", "--format", "{{json .}}"]) else { return }
        // A non-zero exit is the daemon not running; that is a state, not an error.
        guard result.status == 0 else {
            isAvailable = false
            containers = []
            return
        }
        isAvailable = true
        var parsed = DockerPS.parse(lines: result.stdout.split(separator: "\n").map(String.init))
        for index in parsed.indices {
            let id = parsed[index].id
            parsed[index].cpuPercent = stats[id]?.cpuPercent
            parsed[index].memory = stats[id]?.memory
            for port in parsed[index].ports {
                if let kind = kinds[port.host], kind != .unknown {
                    parsed[index].kinds[port.host] = kind
                } else {
                    scheduleProbe(port.host)
                }
            }
        }
        containers = parsed
        let live = Set(parsed.map(\.id))
        pending = pending.filter { live.contains($0.key) }
    }

    func sampleStats() async {
        guard isAvailable, let result = await run(["stats", "--no-stream", "--format", "{{json .}}"]), result.status == 0 else { return }
        stats = DockerStats.parse(lines: result.stdout.split(separator: "\n").map(String.init))
        for index in containers.indices {
            containers[index].cpuPercent = stats[containers[index].id]?.cpuPercent
            containers[index].memory = stats[containers[index].id]?.memory
        }
    }

    private func scheduleProbe(_ port: Int) {
        guard !probing.contains(port) else { return }
        probing.insert(port)
        Task { [weak self] in
            let kind = await ServerProbe.probe(port: port)
            await MainActor.run {
                guard let self else { return }
                self.probing.remove(port)
                self.kinds[port] = kind
                for index in self.containers.indices where self.containers[index].ports.contains(where: { $0.host == port }) {
                    self.containers[index].kinds[port] = kind
                }
            }
        }
    }

    // MARK: actions

    func state(for container: DockerContainer) -> PendingAction? {
        if case .confirmKill(let until) = pending[container.id], until < Date() {
            pending[container.id] = nil
            return nil
        }
        return pending[container.id]
    }

    func requestStop(_ container: DockerContainer) {
        pending[container.id] = .confirmKill(until: Date().addingTimeInterval(ServerActions.confirmWindow))
    }

    func cancelStop(_ container: DockerContainer) {
        if case .confirmKill = pending[container.id] { pending[container.id] = nil }
    }

    func confirmStop(_ container: DockerContainer) {
        pending[container.id] = .killing
        Task { [weak self] in
            let result = await self?.run(["stop", container.id])
            guard let self else { return }
            self.pending[container.id] = result?.status == 0 ? nil : .failed("docker stop failed")
            await self.sampleList()
        }
    }

    func restart(_ container: DockerContainer) {
        pending[container.id] = .restarting
        Task { [weak self] in
            let result = await self?.run(["restart", container.id])
            guard let self else { return }
            self.pending[container.id] = result?.status == 0 ? nil : .failed("docker restart failed")
            await self.sampleList()
        }
    }
}
