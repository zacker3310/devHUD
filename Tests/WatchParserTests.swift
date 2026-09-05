import XCTest
@testable import devHUD

final class WatchParserTests: XCTestCase {
    func testVercelLatestPerProject() {
        let json = #"{"contextName":"ackercloud","deployments":[{"url":"stagger-a.vercel.app","name":"stagger","state":"READY","target":"production","createdAt":1788644379031,"meta":{"githubCommitMessage":"chore(db): tighten grants\n\nbody"}},{"url":"stagger-b.vercel.app","name":"stagger","state":"ERROR","target":"production","createdAt":1788640000000},{"url":"zckr-c.vercel.app","name":"zckr","state":"BUILDING","target":"production","createdAt":1788650000000}]}"#
        let items = VercelParser.latestPerProject(Data(json.utf8))
        XCTAssertEqual(items.map(\.title), ["zckr", "stagger"])
        XCTAssertEqual(items[1].state, .ok, "the newer READY wins over the older ERROR")
        XCTAssertEqual(items[1].subtitle, "ready · production · chore(db): tighten grants")
        XCTAssertEqual(items[1].url?.absoluteString, "https://stagger-a.vercel.app")
        XCTAssertEqual(items[0].state, .busy)
        let summary = WatchSummary(items: items)
        XCTAssertEqual(summary.badge, 1)
        XCTAssertEqual(summary.worst, .busy)
    }

    func testVercelStates() {
        XCTAssertEqual(VercelParser.itemState("READY"), .ok)
        XCTAssertEqual(VercelParser.itemState("ERROR"), .failed)
        XCTAssertEqual(VercelParser.itemState("QUEUED"), .busy)
        XCTAssertEqual(VercelParser.itemState("CANCELED"), .attention)
    }

    func testGitHubNotificationsAndURLs() {
        let json = #"[{"id":"1","reason":"review_requested","updated_at":"2026-09-05T13:00:00Z","subject":{"title":"Fix hover","type":"PullRequest","url":"https://api.github.com/repos/zacker3310/zckr/pulls/12"},"repository":{"full_name":"zacker3310/zckr"}}]"#
        let items = GitHubParser.notifications(Data(json.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Fix hover")
        XCTAssertEqual(items[0].subtitle, "zacker3310/zckr · pullrequest · review requested")
        XCTAssertEqual(items[0].url?.absoluteString, "https://github.com/zacker3310/zckr/pull/12")
        XCTAssertEqual(items[0].state, .attention)
    }

    func testGitHubPullsAndRuns() {
        let prs = #"{"total_count":1,"items":[{"number":7,"title":"Add docker","draft":true,"updated_at":"2026-09-05T13:00:00Z","html_url":"https://github.com/zacker3310/devHUD/pull/7","repository_url":"https://api.github.com/repos/zacker3310/devHUD"}]}"#
        let mine = GitHubParser.pulls(Data(prs.utf8), kind: "your PR")
        XCTAssertEqual(mine[0].subtitle, "zacker3310/devHUD · #7 · your PR · draft")
        XCTAssertEqual(mine[0].state, .ok)
        XCTAssertEqual(GitHubParser.pulls(Data(prs.utf8), kind: "review requested")[0].state, .attention)
        let runs = #"{"workflow_runs":[{"name":"verify","status":"completed","conclusion":"failure","head_branch":"main","html_url":"https://github.com/zacker3310/zckr/actions/runs/1","updated_at":"2026-09-05T13:50:09Z"}]}"#
        let run = GitHubParser.latestRun(Data(runs.utf8), repo: "zacker3310/zckr")
        XCTAssertEqual(run?.state, .failed)
        XCTAssertEqual(run?.subtitle, "verify · main · failure")
        let running = #"{"workflow_runs":[{"name":"verify","status":"in_progress","conclusion":null,"head_branch":"main","updated_at":"2026-09-05T13:50:09Z"}]}"#
        XCTAssertEqual(GitHubParser.latestRun(Data(running.utf8), repo: "r")?.state, .busy)
        XCTAssertNil(GitHubParser.latestRun(Data(#"{"workflow_runs":[]}"#.utf8), repo: "r"))
        let repos = #"[{"full_name":"zacker3310/stagger"},{"full_name":"zacker3310/devHUD"}]"#
        XCTAssertEqual(GitHubParser.recentRepos(Data(repos.utf8)), ["zacker3310/stagger", "zacker3310/devHUD"])
    }
}
