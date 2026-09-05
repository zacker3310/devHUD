import XCTest
@testable import devHUD

final class ServerKindTests: XCTestCase {
    func testKnownCommandsSkipTheProbe() {
        XCTAssertEqual(ServerKind.known(command: "postgres"), .service("postgres"))
        XCTAssertEqual(ServerKind.known(command: "redis-server"), .service("redis"))
        XCTAssertEqual(ServerKind.known(command: "ollama"), .api)
        XCTAssertNil(ServerKind.known(command: "node"))
    }

    func testHTMLIsWebAndOtherHTTPIsAPI() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:3000/"))
        let html = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])
        let json = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        let bare = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        XCTAssertEqual(ServerProbe.classify(response: html, error: nil), .web)
        XCTAssertEqual(ServerProbe.classify(response: json, error: nil), .api)
        XCTAssertEqual(ServerProbe.classify(response: bare, error: nil), .api)
    }

    func testConnectFailuresRetryAndProtocolErrorsAreTCP() {
        XCTAssertEqual(ServerProbe.classify(response: nil, error: URLError(.cannotConnectToHost)), .unknown)
        XCTAssertEqual(ServerProbe.classify(response: nil, error: URLError(.timedOut)), .unknown)
        XCTAssertEqual(ServerProbe.classify(response: nil, error: URLError(.badServerResponse)), .tcp)
        XCTAssertEqual(ServerProbe.classify(response: nil, error: URLError(.cannotParseResponse)), .tcp)
    }

    func testOpenableURLs() {
        var server = DevServer(pid: 1, port: 3000, command: "node", projectName: "web", cwd: nil, startedAt: nil, rssBytes: nil, cpuPercent: nil, portlessHost: nil)
        XCTAssertNil(server.url)
        server.kind = .web
        XCTAssertEqual(server.url?.absoluteString, "http://localhost:3000")
        server.portlessHost = "web.localhost"
        XCTAssertEqual(server.url?.absoluteString, "http://web.localhost")
        server.portlessHost = "login.attacker.example/gh"
        XCTAssertEqual(server.url?.absoluteString, "http://localhost:3000", "untrusted hostnames fall back to the port")
        server.kind = .service("postgres")
        XCTAssertNil(server.url)
        XCTAssertEqual(server.kind.tag, "postgres")
    }
}
