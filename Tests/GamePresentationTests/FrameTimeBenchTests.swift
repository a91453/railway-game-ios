import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 421 (V2): the fixed frame time test's scenarios, paths and
/// game are the same every run, and three runs are summed up right.
@MainActor
final class FrameTimeBenchTests: XCTestCase {
    private func run(_ scenario: FrameTimeBench.Scenario, device: String = "iPhone14,5", p95: Double, severe: Int = 0, longest: Double = 80,
                     cold: Bool = true, simulator: Bool = false) -> FrameTimeBenchRun {
        let segment = FrameTimeSegment(
            context: FrameTimeContext(screen: .map3D), began: 0, seconds: 60,
            intervals: FrameTimeStats(count: 3_600, median: 16.7, p95: p95, p99: p95 + 5, longest: longest),
            stalls: FrameTimeStalls(severe: severe), longest: FrameTimeStall(milliseconds: longest, at: 12, parts: [])
        )
        return FrameTimeBenchRun(scenario: scenario, device: device, simulator: simulator, cold: cold, segment: segment)
    }

    func testTheScenariosAreTwelveInAFixedOrder() {
        XCTAssertEqual(FrameTimeBench.scenarios.count, 12)
        XCTAssertEqual(FrameTimeBench.scenarios.map(\.id).prefix(4), ["1-pan2D", "1-orbit3D", "1-follow3D", "5-pan2D"])
        XCTAssertEqual(Set(FrameTimeBench.scenarios.map(\.id)).count, 12)
        XCTAssertEqual(FrameTimeBench.scenarios.map(\.lines), [1, 1, 1, 5, 5, 5, 10, 10, 10, 20, 20, 20])
        XCTAssertEqual(FrameTimeBench.seconds, 60)
        XCTAssertEqual(FrameTimeBench.runs, 3)
    }

    func testTheCamerasPathsAreTheSameEveryTime() {
        let bounds = WorldBounds.standard
        let plan = PlanCamera(bounds: bounds, viewport: ScreenSize(width: 390, height: 844))
        let steps = stride(from: 0.0, through: FrameTimeBench.seconds, by: 1 / 60.0)
        let first = steps.map { FrameTimeBench.camera2D(from: plan, at: $0) }
        let second = steps.map { FrameTimeBench.camera2D(from: plan, at: $0) }
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first, FrameTimeBench.camera2D(from: plan, at: 0))
        XCTAssertEqual(first[0].centerX, plan.centerX, accuracy: 1e-6, "starts where the map opened")
        XCTAssertEqual(first[0].referenceSize, plan.referenceSize, accuracy: 1e-6)
        // A quarter of the eight, 5 s in: a kilometre east.
        XCTAssertEqual(FrameTimeBench.camera2D(from: plan, at: 5).centerX - plan.centerX, 1_000 * Double(WorldCoordinate.unitsPerMetre), accuracy: 1)
        XCTAssertNotEqual(first[300], first[0], "it moves")
        let start = Map3DCamera(distance: 1_200, heading: 0.5)
        let orbit = steps.map { FrameTimeBench.camera3D(from: start, at: $0) }
        XCTAssertEqual(orbit, steps.map { FrameTimeBench.camera3D(from: start, at: $0) })
        XCTAssertEqual(orbit[0], start)
        XCTAssertEqual(FrameTimeBench.camera3D(from: start, at: 15).heading, 0.5 + .pi, accuracy: 1e-5, "half round in 15 s")
        XCTAssertEqual(FrameTimeBench.camera3D(from: start, at: 10).distance, 1_800, accuracy: 0.01, "half as far again out at 10 s")
    }

    func testThreeRunsSumUpAndUnsteadyIsMarked() {
        let scenario = FrameTimeBench.scenarios[1]
        let steady = FrameTimeBenchSummary(runs: [run(scenario, p95: 18, longest: 80), run(scenario, p95: 21.6, longest: 120), run(scenario, p95: 19, longest: 100)])
        XCTAssertTrue(steady.isComplete)
        XCTAssertEqual(steady.p95.middle, 19)
        XCTAssertEqual(steady.p95.spread, 3.6, accuracy: 1e-9)
        XCTAssertEqual(steady.longest.middle, 100)
        XCTAssertEqual(steady.longest.spread, 40)
        XCTAssertEqual(steady.median.middle, 16.7)
        XCTAssertFalse(steady.isUnsteady, "exactly 20% apart is steady")
        let wide = FrameTimeBenchSummary(runs: [run(scenario, p95: 18), run(scenario, p95: 21.7), run(scenario, p95: 19)])
        XCTAssertTrue(wide.isUnsteady, "more than 20% apart")
        let stalls = FrameTimeBenchSummary(runs: [run(scenario, p95: 18, severe: 0), run(scenario, p95: 18, severe: 1), run(scenario, p95: 18, severe: 0)])
        XCTAssertTrue(stalls.isUnsteady, "the severe stalls differ")
        XCTAssertEqual(stalls.severe.middle, 0)
        XCTAssertEqual(stalls.severe.spread, 1)
        let one = FrameTimeBenchSummary(runs: [run(scenario, p95: 18)])
        XCTAssertFalse(one.isUnsteady)
        XCTAssertFalse(one.isComplete)
        let lines = wide.lines(of: scenario, in: .traditionalChinese).joined(separator: "\n")
        XCTAssertTrue(lines.contains("台北 1 線 · 3D 環繞：3／3 次（冷啟動後 3 次）"), lines)
        XCTAssertTrue(lines.contains("不穩定"), lines)
        XCTAssertTrue(lines.contains("中間值（最大最小差）：中位數 16.7 ms（0.0 ms）、p95 19.0 ms（3.7 ms）"), lines)
        XCTAssertFalse(lines.contains("模擬器"), lines)
        let simulated = FrameTimeBenchSummary(runs: [run(scenario, p95: 18, simulator: true)]).lines(of: scenario, in: .english).joined()
        XCTAssertTrue(simulated.contains("not GPU figures"), simulated)
    }

    func testTheResultsKeepTheNewestThreeOfEachScenarioOnEachDevice() throws {
        var results = FrameTimeBenchResults()
        let a = FrameTimeBench.scenarios[0], b = FrameTimeBench.scenarios[5]
        for p95 in [10.0, 11, 12, 13] { results.add(run(a, p95: p95)) }
        results.add(run(b, p95: 30))
        results.add(run(a, device: "iPad13,1", p95: 40))
        XCTAssertEqual(results.summary(of: a, on: "iPhone14,5").runs.map(\.p95), [11, 12, 13], "the newest three, oldest first")
        XCTAssertEqual(results.summary(of: b, on: "iPhone14,5").runs.count, 1)
        XCTAssertEqual(results.summary(of: a, on: "iPad13,1").runs.count, 1)
        XCTAssertEqual(FrameTimeBenchResults.decoded(try results.encoded()), results)
        let text = try XCTUnwrap(results.reportText(on: "iPhone14,5", in: .english))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "1 lines")).lowerBound, try XCTUnwrap(text.range(of: "5 lines")).lowerBound)
        XCTAssertNil(results.reportText(on: "iPhone9,9", in: .english))
        results.clear(device: "iPhone14,5")
        XCTAssertEqual(results.runs.count, 1)
    }

    /// The game: Taipei with its real lines, by the demo mode's steps, to
    /// the count asked, and the same every time.
    func testTheGameHasTheLinesAskedTheSameEveryTime() async throws {
        // Through the launcher, as the test builds' entry opens it.
        func laid(_ count: Int) async throws -> GameWorld {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FrameTimeBenchTests-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
            await launcher.loadRealWorldData { Map3DOpenEveryStartTests.data }.value
            let opened = await launcher.openFrameTimeBench(lines: count)
            let session = try XCTUnwrap(opened)
            XCTAssertTrue(session.news.isDemo)
            XCTAssertEqual(session.world.lines.count, count)
            return session.world
        }
        // One line, twice: laying more takes minutes in a debug build; the
        // counts beyond are the same steps with a larger `routes`.
        let one = try await laid(1)
        XCTAssertEqual(one.lines.count, 1)
        XCTAssertTrue(one.lines.allSatisfy { !$0.assignedTrains.isEmpty }, "\(one.lines.map(\.name))")
        let again = try await laid(1)
        XCTAssertEqual(again.lines.map(\.name), one.lines.map(\.name))
        XCTAssertEqual(again.lines.map(\.stops), one.lines.map(\.stops))
        XCTAssertEqual(again.stations.count, one.stations.count)
        XCTAssertNotNil(FrameTimeBench.followed(in: one))
        // Decision 313, later: its 3D map opens where the 2D map looks, as
        // every start's (Map3DOpenEveryStartTests).
        Map3DOpenEveryStartTests.assertOpensWhereThe2DMapLooks(one, "openFrameTimeBench")
    }
}
