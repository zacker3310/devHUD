import XCTest
@testable import devHUD

final class ClaudeDiscoveryTests: XCTestCase {
    let home = URL(fileURLWithPath: "/Users/z")

    func testDefaultPlusSiblingDirsWithCredentials() {
        let dirs = ClaudeUsageProvider.discoverConfigDirs(
            home: home, configured: nil, environment: [:],
            homeEntries: [".claude", ".claude-work", ".claude_old", ".claudeignore", "dev"],
            hasCredentials: { $0.lastPathComponent != ".claude_old" }
        )
        XCTAssertEqual(dirs.map(\.lastPathComponent), [".claude", ".claude-work"])
    }

    func testConfiguredListOverridesDiscovery() {
        let dirs = ClaudeUsageProvider.discoverConfigDirs(
            home: home, configured: ["~/.claude", "/opt/claude-work"], environment: [:],
            homeEntries: [".claude-ignored"], hasCredentials: { _ in true }
        )
        XCTAssertEqual(dirs.map(\.path).last, "/opt/claude-work")
        XCTAssertEqual(dirs.count, 2)
    }

    func testEnvironmentDirComesFirstAndIsNotDuplicated() {
        let dirs = ClaudeUsageProvider.discoverConfigDirs(
            home: home, configured: nil, environment: ["CLAUDE_CONFIG_DIR": "/Users/z/.claude-work"],
            homeEntries: [".claude", ".claude-work"], hasCredentials: { _ in true }
        )
        XCTAssertEqual(dirs.map(\.lastPathComponent), [".claude-work", ".claude"])
    }

    func testTitles() {
        XCTAssertEqual(ClaudeUsageProvider.title(plan: "max", dirName: ".claude"), "Claude Max")
        XCTAssertEqual(ClaudeUsageProvider.title(plan: "enterprise", dirName: ".claude-work"), "Claude Enterprise")
        XCTAssertEqual(ClaudeUsageProvider.title(plan: nil, dirName: ".claude"), "Claude")
        XCTAssertEqual(ClaudeUsageProvider.title(plan: nil, dirName: ".claude-work"), "Claude (work)")
    }
}
