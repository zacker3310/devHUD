import XCTest
@testable import devHUD

final class DockerParserTests: XCTestCase {
    // Shapes captured from docker 29.5.3 on this machine, trimmed.
    let ps = [
        #"{"Command":"\"sh -c\"","CreatedAt":"2026-09-05 17:37:50 -0400 EDT","HealthStatus":"healthy","ID":"520e88989ed1","Image":"public.ecr.aws/supabase/postgres:17.6.1.155","Labels":"com.docker.compose.project=stagger,com.supabase.cli.workdir=/Users/z/dev/stagger,desktop.docker.io/ports/5432/tcp=:54322","Names":"supabase_db_stagger","Ports":"0.0.0.0:54322->5432/tcp, [::]:54322->5432/tcp","State":"running","Status":"Up 20 minutes (healthy)"}"#,
        #"{"ID":"c4f7c6283b9a","Image":"public.ecr.aws/supabase/studio:2026.08.10-sha-5b68af1","Labels":"","Names":"supabase_studio_stagger","Ports":"3000/tcp","State":"running","Status":"Up 2 weeks","HealthStatus":""}"#,
        "not json",
    ]

    func testParsesContainers() {
        let list = DockerPS.parse(lines: ps)
        XCTAssertEqual(list.count, 2)
        let db = list.first { $0.name == "supabase_db_stagger" }!
        XCTAssertEqual(db.project, "stagger")
        XCTAssertEqual(db.health, "healthy")
        XCTAssertEqual(db.shortImage, "postgres")
        XCTAssertEqual(db.ports, [PortMapping(host: 54322, container: 5432, proto: "tcp")])
        let studio = list.first { $0.name == "supabase_studio_stagger" }!
        XCTAssertNil(studio.project)
        XCTAssertNil(studio.health)
        XCTAssertEqual(studio.ports, [], "an unpublished port is not a mapping")
        XCTAssertEqual(studio.shortImage, "studio")
    }

    func testPortsAndLabels() {
        XCTAssertEqual(DockerPS.parsePorts("0.0.0.0:8080->80/tcp, [::]:8080->80/tcp, 0.0.0.0:8443->443/tcp"), [PortMapping(host: 8080, container: 80, proto: "tcp"), PortMapping(host: 8443, container: 443, proto: "tcp")])
        XCTAssertEqual(DockerPS.parsePorts(""), [])
        XCTAssertEqual(DockerPS.parseLabels("a=1,b=x=y,c")["b"], "x=y")
    }

    func testStats() {
        let lines = [#"{"BlockIO":"0B / 198MB","CPUPerc":"0.73%","ID":"520e88989ed1","MemPerc":"2.05%","MemUsage":"162.4MiB / 7.75GiB","Name":"supabase_db_stagger"}"#]
        let stats = DockerStats.parse(lines: lines)
        XCTAssertEqual(stats["520e88989ed1"], DockerStats.Sample(cpuPercent: 0.73, memory: "162.4MiB"))
    }

    func testURLNeedsAWebPort() {
        var c = DockerPS.parse(lines: ps).first { $0.name == "supabase_db_stagger" }!
        XCTAssertNil(c.url)
        c.kinds[54322] = .tcp
        XCTAssertNil(c.url)
        c.kinds[54322] = .web
        XCTAssertEqual(c.url?.absoluteString, "http://localhost:54322")
    }

    func testBinaryDiscoveryHere() {
        // Docker Desktop is installed on this machine; elsewhere nil is fine.
        _ = DockerStore.findBinary()
    }
}
