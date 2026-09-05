import Foundation

// What a listening port is, as far as a glance needs: something to open in a
// browser, an HTTP API, a named service, or a plain socket.
enum ServerKind: Equatable, Sendable {
    case web
    case api
    case service(String)
    case tcp
    case unknown

    var tag: String? {
        switch self {
        case .web: return "web"
        case .api: return "api"
        case .service(let name): return name
        case .tcp: return "tcp"
        case .unknown: return nil
        }
    }

    var isOpenable: Bool { self == .web || self == .api }

    // Commands that never need a probe. Probing a database port with an HTTP
    // request is rude and slow; the name is what the user wants anyway.
    static func known(command: String) -> ServerKind? {
        let lower = command.lowercased()
        let table: [(prefix: String, kind: ServerKind)] = [
            ("postgres", .service("postgres")), ("redis-server", .service("redis")),
            ("mysqld", .service("mysql")), ("mariadbd", .service("mariadb")),
            ("mongod", .service("mongo")), ("sshd", .service("ssh")),
            ("memcached", .service("memcached")), ("ollama", .api),
            ("com.docker", .service("docker")), ("docker", .service("docker")),
        ]
        return table.first { lower.hasPrefix($0.prefix) }?.kind
    }
}

enum ServerProbe {
    static let timeout: TimeInterval = 1.5

    // Pure classification so the mapping is testable without sockets.
    static func classify(response: HTTPURLResponse?, error: Error?) -> ServerKind {
        if let response {
            let type = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            return type.contains("text/html") ? .web : .api
        }
        guard let urlError = error as? URLError else { return .tcp }
        switch urlError.code {
        case .cannotConnectToHost, .timedOut, .networkConnectionLost:
            return .unknown // not up yet, try again next sample
        default:
            return .tcp // answered, but not in HTTP
        }
    }

    static func probe(port: Int) async -> ServerKind {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return .tcp }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("devHUD/0.1", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(for: request)
            return classify(response: response as? HTTPURLResponse, error: nil)
        } catch {
            return classify(response: nil, error: error)
        }
    }
}

// A local listener does not get to send the probe anywhere else.
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
