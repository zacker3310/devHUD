import XCTest
@testable import devHUD

final class ServerCommandTests: XCTestCase {
    func testShellQuoteSurvivesSpacesAndQuotes() {
        XCTAssertEqual(ServerCommand.shellQuote("/Users/z/my dir"), "'/Users/z/my dir'")
        XCTAssertEqual(ServerCommand.shellQuote("it's"), #"'it'\''s'"#)
    }

    func testRelaunchScriptUsesTheExecutableAndQuotesEveryToken() {
        let script = ServerCommand.relaunchScript(executable: "/opt/homebrew/bin/node", arguments: ["node", "server.js", "--port", "3000"], cwd: "/Users/z/dev/app", log: "/Users/z/Library/Logs/devHUD/app-3000.log")
        XCTAssertEqual(script, "cd '/Users/z/dev/app' && nohup '/opt/homebrew/bin/node' 'server.js' '--port' '3000' </dev/null >>'/Users/z/Library/Logs/devHUD/app-3000.log' 2>&1 &")
    }

    func testHostileArgvCannotEscapeTheQuotes() {
        let script = ServerCommand.relaunchScript(executable: "/usr/bin/node", arguments: ["evil; id", "x; touch /tmp/pwned", "$(whoami)", "a'b", "`id`"], cwd: "/tmp", log: "/tmp/l")
        XCTAssertTrue(script.contains("'/usr/bin/node' 'x; touch /tmp/pwned' '$(whoami)' 'a'\\''b' '`id`'"))
        XCTAssertFalse(script.contains("evil"))
    }

    func testLogNamesAreSanitized() {
        XCTAssertEqual(ServerCommand.safeLogName("../../.zshrc"), "zshrc")
        XCTAssertEqual(ServerCommand.safeLogName("my app/../x"), "myapp..x")
        XCTAssertEqual(ServerCommand.safeLogName("@scope/pkg"), "scopepkg")
        XCTAssertEqual(ServerCommand.safeLogName("....."), "server")
        XCTAssertEqual(ServerCommand.safeLogName(String(repeating: "a", count: 100)).count, 64)
    }

    func testProcArgsParse() {
        // argc=3, exec path, padding, then argv, then env.
        var bytes: [UInt8] = [3, 0, 0, 0]
        bytes += Array("/usr/bin/node".utf8) + [0, 0, 0]
        bytes += Array("node".utf8) + [0] + Array("server.js".utf8) + [0] + Array("--port=3000".utf8) + [0]
        bytes += Array("HOME=/Users/z".utf8) + [0]
        XCTAssertEqual(ProcArgs.parse(Data(bytes)), ProcArgs(executable: "/usr/bin/node", arguments: ["node", "server.js", "--port=3000"]))
        XCTAssertNil(ProcArgs.parse(Data([0, 0, 0, 0])))
        XCTAssertNil(ProcArgs.parse(Data([1, 0])))
        var relative: [UInt8] = [1, 0, 0, 0]
        relative += Array("node".utf8) + [0, 0] + Array("node".utf8) + [0]
        XCTAssertNil(ProcArgs.parse(Data(relative)), "a non-absolute executable is rejected")
    }

    func testOwnArgvIsReadable() {
        let args = ProcessInspector.arguments(pid: getpid())
        XCTAssertNotNil(args)
        XCTAssertTrue(args?.executable.hasPrefix("/") ?? false)
        XCTAssertNil(ProcessInspector.arguments(pid: 0))
    }

    func testLogNameUsesProjectThenCommand() {
        let logs = URL(fileURLWithPath: "/logs")
        var server = DevServer(pid: 1, port: 3000, command: "node", projectName: "thrivecmd", cwd: "/x", startedAt: nil, rssBytes: nil, cpuPercent: nil, portlessHost: nil)
        XCTAssertEqual(ServerCommand.logURL(for: server, logs: logs).path, "/logs/thrivecmd-3000.log")
        server = DevServer(pid: 1, port: 8000, command: "python3.12", projectName: nil, cwd: nil, startedAt: nil, rssBytes: nil, cpuPercent: nil, portlessHost: nil)
        XCTAssertEqual(ServerCommand.logURL(for: server, logs: logs).lastPathComponent, "python3.12-8000.log")
    }

    func testTerminateReturnsTrueForADeadPidAndRefusesBadPids() async {
        // A pid that cannot exist on macOS.
        let gone = await ServerActions.terminate(pid: 99_999_999, startedAt: nil)
        XCTAssertTrue(gone)
        let zero = await ServerActions.terminate(pid: 0, startedAt: nil)
        XCTAssertFalse(zero)
        let negative = await ServerActions.terminate(pid: -1, startedAt: nil)
        XCTAssertFalse(negative)
    }
}
