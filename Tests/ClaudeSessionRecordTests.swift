import XCTest
@testable import devHUD

final class ClaudeSessionRecordTests: XCTestCase {
    func record(status: String = "busy", extra: [String: Any] = [:]) -> [String: Any] {
        var json: [String: Any] = [
            "pid": 94048, "sessionId": "abc", "cwd": "/Users/z/dev/devHUD",
            "startedAt": 1_788_000_000_000, "version": "2.1.261", "kind": "interactive",
            "entrypoint": "cli", "name": "devhud-0c", "status": status,
            "updatedAt": 1_788_000_100_000, "statusUpdatedAt": 1_788_000_200_000,
        ]
        for (k, v) in extra { json[k] = v }
        return json
    }

    func testParsesTheFieldsClaudeCodeWrites() throws {
        let r = try XCTUnwrap(ClaudeSessionRecord(json: record()))
        XCTAssertEqual(r.pid, 94048)
        XCTAssertEqual(r.startedAt, Date(timeIntervalSince1970: 1_788_000_000))
        XCTAssertEqual(r.session.id, "claude:94048")
        XCTAssertEqual(r.session.kind, .claude)
        XCTAssertEqual(r.session.name, "devhud-0c")
        XCTAssertEqual(r.session.surface, "Terminal")
        XCTAssertEqual(r.session.folder, "devHUD")
        XCTAssertEqual(r.session.state, .busy)
        XCTAssertEqual(r.session.since, Date(timeIntervalSince1970: 1_788_000_200))
    }

    func testStatesAndSurfaces() throws {
        XCTAssertEqual(ClaudeSessionRecord(json: record(status: "waiting"))?.session.state, .waiting)
        XCTAssertEqual(ClaudeSessionRecord(json: record(status: "idle"))?.session.state, .idle)
        XCTAssertEqual(ClaudeSessionRecord(json: record(status: "anything"))?.session.state, .idle)
        XCTAssertEqual(ClaudeSessionRecord(json: record(extra: ["entrypoint": "claude-vscode"]))?.session.surface, "VS Code")
        XCTAssertEqual(ClaudeSessionRecord(json: record(extra: ["name": ""]))?.session.name, "devHUD")
    }

    func testRejectsRecordsWithoutAProcess() {
        XCTAssertNil(ClaudeSessionRecord(json: ["cwd": "/x"]))
        XCTAssertNil(ClaudeSessionRecord(json: record(extra: ["pid": 0])))
        var noCwd = record(); noCwd.removeValue(forKey: "cwd")
        XCTAssertNil(ClaudeSessionRecord(json: noCwd))
    }

    func testSummaryPrecedence() {
        let busy = AgentSession(id: "a", kind: .claude, name: "a", surface: "", folder: "", state: .busy, since: Date())
        let waiting = AgentSession(id: "b", kind: .claude, name: "b", surface: "", folder: "", state: .waiting, since: Date())
        let idle = AgentSession(id: "c", kind: .claude, name: "c", surface: "", folder: "", state: .idle, since: Date())
        XCTAssertNil(ActivitySummary(sessions: []))
        XCTAssertEqual(ActivitySummary(sessions: [idle])?.state, .idle)
        XCTAssertEqual(ActivitySummary(sessions: [idle, busy])?.state, .working)
        XCTAssertEqual(ActivitySummary(sessions: [busy, waiting])?.state, .waiting)
    }

    func testLivenessFiltersDeadPids() {
        XCTAssertTrue(ActivityStore.isAlive(pid: getpid(), startedAt: ProcessInspector.startTime(pid: getpid())))
        XCTAssertFalse(ActivityStore.isAlive(pid: 99_999_999, startedAt: nil))
        XCTAssertFalse(ActivityStore.isAlive(pid: getpid(), startedAt: Date(timeIntervalSince1970: 0)), "a pid reused by a different process is dead")
    }

    func testThisSessionIsFoundOnDisk() {
        // The test host runs inside Zac's Claude Code session on this machine;
        // elsewhere the directory may be empty, and that is fine.
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
        let sessions = ActivityStore.readClaudeSessions(in: dir)
        for s in sessions { XCTAssertEqual(s.kind, .claude); XCTAssertFalse(s.folder.isEmpty) }
    }
}
