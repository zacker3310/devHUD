import XCTest
@testable import devHUD

final class PortlessRoutesTests: XCTestCase {
    func testArrayShape() throws {
        let data = Data(#"[{"hostname":"myapp.localhost","port":3000,"pid":42,"tailscaleUrl":null}]"#.utf8)
        let routes = try PortlessRoutes.decode(data)
        XCTAssertEqual(routes[3000]?.hostname, "myapp.localhost")
        XCTAssertEqual(routes[3000]?.pid, 42)
    }

    func testObjectKeyedByHostname() throws {
        let data = Data(#"{"api.localhost":{"hostname":"api.localhost","port":8000,"pid":7}}"#.utf8)
        let routes = try PortlessRoutes.decode(data)
        XCTAssertEqual(routes[8000]?.hostname, "api.localhost")
    }

    func testWrappedRoutesKey() throws {
        let data = Data(#"{"routes":[{"hostname":"web.localhost","port":5173,"pid":9}]}"#.utf8)
        XCTAssertEqual(try PortlessRoutes.decode(data)[5173]?.hostname, "web.localhost")
    }

    func testPidIsOptional() throws {
        let data = Data(#"[{"hostname":"nopid.localhost","port":7000}]"#.utf8)
        let routes = try PortlessRoutes.decode(data)
        XCTAssertEqual(routes[7000]?.hostname, "nopid.localhost")
        XCTAssertNil(routes[7000]?.pid)
    }

    func testOnlyLocalhostHostnamesAreTrusted() {
        XCTAssertTrue(PortlessRoutes.isTrustedHost("myapp.localhost"))
        XCTAssertTrue(PortlessRoutes.isTrustedHost("localhost"))
        XCTAssertTrue(PortlessRoutes.isTrustedHost("Api.Dev.LOCALHOST"))
        XCTAssertFalse(PortlessRoutes.isTrustedHost("login.attacker.example/gh"))
        XCTAssertFalse(PortlessRoutes.isTrustedHost("evil.com"))
        XCTAssertFalse(PortlessRoutes.isTrustedHost("user@x.localhost"))
        XCTAssertFalse(PortlessRoutes.isTrustedHost("x.localhost:3000"))
        XCTAssertFalse(PortlessRoutes.isTrustedHost(".localhost"))
        XCTAssertFalse(PortlessRoutes.isTrustedHost(""))
    }

    func testUnknownShapeThrows() {
        XCTAssertThrowsError(try PortlessRoutes.decode(Data("42".utf8)))
    }
}
