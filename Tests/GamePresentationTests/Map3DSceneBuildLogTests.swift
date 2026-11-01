@testable import GamePresentation
import XCTest

/// Decision 517 續 (PR 3b's measurement): the 3D scene's build times kept
/// for a problem report.
final class Map3DSceneBuildLogTests: XCTestCase {
    private func time(_ why: Map3DSceneBuildTime.Why = .track, edges: Int = 12) -> Map3DSceneBuildTime {
        Map3DSceneBuildTime(why: why, realWorld: true, edges: edges, chunks: 40, triangles: 1_200_000, readSeconds: 0.25, buildSeconds: 3.5,
                            wall: 1_793_000_000)
    }

    func testNothingBuiltWritesNothing() {
        XCTAssertNil(Map3DSceneBuildLog().reportText(in: .english))
    }

    func testOnlyTheNewestBuildsAreKept() {
        let log = Map3DSceneBuildLog()
        for edges in 1...(Map3DSceneBuildLog.capacity + 3) { log.add(time(edges: edges)) }
        XCTAssertEqual(log.times.map(\.edges), Array(4...(Map3DSceneBuildLog.capacity + 3)))
    }

    func testTheTimeToShowIsTheFirstShowsAndOnlyItsOwn() {
        let log = Map3DSceneBuildLog()
        let first = log.add(time(.first))
        let second = log.add(time(.track))
        log.shown(second, seconds: 0.4)
        log.shown(second, seconds: 9)
        log.shown(first + 100, seconds: 1)
        XCTAssertNil(log.times[0].showSeconds)
        XCTAssertEqual(log.times[1].showSeconds, 0.4)
        // A build let go of before it was shown is not found.
        for _ in 0..<Map3DSceneBuildLog.capacity { log.add(time()) }
        log.shown(first, seconds: 1)
        XCTAssertTrue(log.times.allSatisfy { $0.showSeconds == nil })
    }

    func testTheReportSaysWhyHowBigAndHowLong() throws {
        let log = Map3DSceneBuildLog()
        log.add(time(.first))
        let number = log.add(time(.track))
        log.shown(number, seconds: 0.5)
        let english = try XCTUnwrap(log.reportText(in: .english))
        XCTAssertEqual(english, """
            3D scene builds (oldest first):
              2026-10-26 07:33:20 UTC first, real-world map, 12 edges, 40 chunks, 1200000 triangles: read 0.25 s, built 3.50 s, not shown (total 3.75 s)
              2026-10-26 07:33:20 UTC track changed, real-world map, 12 edges, 40 chunks, 1200000 triangles: read 0.25 s, built 3.50 s, shown 0.50 s (total 4.25 s)
            """)
        let chinese = try XCTUnwrap(log.reportText(in: .traditionalChinese))
        XCTAssertTrue(chinese.contains("軌道變了"))
        XCTAssertTrue(chinese.contains("上 GPU 0.50 s（共 4.25 s）"))
    }
}
