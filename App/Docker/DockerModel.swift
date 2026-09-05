import Foundation

struct PortMapping: Equatable, Hashable, Sendable {
    let host: Int
    let container: Int
    let proto: String
}

struct DockerContainer: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let image: String
    let state: String
    let status: String
    let health: String?
    let project: String?
    let ports: [PortMapping]
    var cpuPercent: Double?
    var memory: String?
    var kinds: [Int: ServerKind] = [:]

    // "public.ecr.aws/supabase/postgres:17.6.1.155" -> "postgres"
    var shortImage: String {
        let noTag = image.split(separator: ":").first.map(String.init) ?? image
        return noTag.split(separator: "/").last.map(String.init) ?? noTag
    }

    var isRunning: Bool { state == "running" }

    // The first published port that answers HTTP is where a click goes.
    var url: URL? {
        guard let web = ports.first(where: { kinds[$0.host]?.isOpenable == true }) else { return nil }
        return URL(string: "http://localhost:\(web.host)")
    }
}

// `docker ps --format '{{json .}}'`: one object per line.
enum DockerPS {
    static func parse(lines: [String]) -> [DockerContainer] {
        lines.compactMap { line -> DockerContainer? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["ID"] as? String, let name = json["Names"] as? String else { return nil }
            let labels = parseLabels(json["Labels"] as? String ?? "")
            let health = json["HealthStatus"] as? String
            return DockerContainer(
                id: id,
                name: name,
                image: json["Image"] as? String ?? "",
                state: json["State"] as? String ?? "",
                status: json["Status"] as? String ?? "",
                health: (health?.isEmpty ?? true) ? nil : health,
                project: labels["com.docker.compose.project"],
                ports: parsePorts(json["Ports"] as? String ?? "")
            )
        }.sorted { ($0.project ?? "", $0.name) < ($1.project ?? "", $1.name) }
    }

    // "0.0.0.0:54322->5432/tcp, [::]:54322->5432/tcp, 5432/tcp" -> one 54322->5432.
    static func parsePorts(_ text: String) -> [PortMapping] {
        var seen = Set<Int>()
        var result: [PortMapping] = []
        for part in text.split(separator: ",") {
            let entry = part.trimmingCharacters(in: .whitespaces)
            guard let arrow = entry.range(of: "->") else { continue }
            let hostSide = entry[..<arrow.lowerBound]
            let containerSide = entry[arrow.upperBound...]
            guard let hostColon = hostSide.lastIndex(of: ":"), let host = Int(hostSide[hostSide.index(after: hostColon)...]) else { continue }
            let containerParts = containerSide.split(separator: "/")
            guard let container = Int(containerParts.first ?? "") else { continue }
            let proto = containerParts.count > 1 ? String(containerParts[1]) : "tcp"
            guard seen.insert(host).inserted else { continue }
            result.append(PortMapping(host: host, container: container, proto: proto))
        }
        return result.sorted { $0.host < $1.host }
    }

    // "a=b,c=d" with values that may contain "=" but not ",".
    static func parseLabels(_ text: String) -> [String: String] {
        var labels: [String: String] = [:]
        for part in text.split(separator: ",") {
            guard let eq = part.firstIndex(of: "=") else { continue }
            labels[String(part[..<eq])] = String(part[part.index(after: eq)...])
        }
        return labels
    }
}

// `docker stats --no-stream --format '{{json .}}'`: id -> cpu percent, memory text.
enum DockerStats {
    struct Sample: Equatable {
        let cpuPercent: Double
        let memory: String
    }

    static func parse(lines: [String]) -> [String: Sample] {
        var result: [String: Sample] = [:]
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["ID"] as? String else { continue }
            let cpuText = (json["CPUPerc"] as? String ?? "").replacingOccurrences(of: "%", with: "")
            let memory = (json["MemUsage"] as? String ?? "").split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            result[id] = Sample(cpuPercent: Double(cpuText) ?? 0, memory: memory)
        }
        return result
    }
}
