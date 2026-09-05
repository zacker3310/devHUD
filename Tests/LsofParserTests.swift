import XCTest
@testable import devHUD

final class LsofParserTests: XCTestCase {
    let sample = """
    p4242
    cnode
    n*:3000
    n[::1]:3000
    n127.0.0.1:3001
    p99
    crapportd
    n*:49152
    p7
    cpython3.12
    n127.0.0.1:4173
    ngarbage
    """

    func testParsesPidCommandPort() {
        let sockets = LsofParser.parse(sample)
        XCTAssertEqual(sockets.count, 4)
        XCTAssertEqual(sockets[0], ListeningSocket(pid: 4242, command: "node", host: "*", port: 3000))
        XCTAssertEqual(sockets[1].port, 3001)
        XCTAssertEqual(sockets[3], ListeningSocket(pid: 7, command: "python3.12", host: "127.0.0.1", port: 4173))
    }

    func testDedupesV4AndV6OnSamePort() {
        let ports = LsofParser.parse(sample).filter { $0.pid == 4242 }.map(\.port)
        XCTAssertEqual(ports, [3000, 3001])
    }

    func testDenylistFiltersSystemDaemons() {
        XCTAssertTrue(LsofParser.isDenied("rapportd"))
        XCTAssertTrue(LsofParser.isDenied("ControlCenter"))
        XCTAssertFalse(LsofParser.isDenied("node"))
        XCTAssertFalse(LsofParser.isDenied("python3.12"))
    }

    func testMalformedLinesAreIgnored() {
        XCTAssertEqual(LsofParser.parse("n*:3000\nxjunk\n"), [])
        XCTAssertEqual(LsofParser.parse(""), [])
    }

    func testNonPositivePidsAreDropped() {
        XCTAssertEqual(LsofParser.parse("p0\ncx\nn*:3000\np-1\ncy\nn*:3001\n"), [])
    }
}
