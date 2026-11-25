import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 973: the whole Alishan Forest Railway can be traced station
/// by station, and a stroke across a switchback says trains reverse there.
@MainActor
final class AlishanWholeLineTraceTests: XCTestCase {
    private static let heights = try? HeightGrid(
        data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_heights.dat"))
    )

    private func session(at name: String) throws -> GameSession {
        let start = try BundledRealData.station(name, in: "afr_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(start.anchor))
        try world.mapGround()
        let session = GameSession(world: world, language: .traditionalChinese)
        session.heights = try XCTUnwrap(Self.heights)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        return session
    }

    private func plan(from a: String, to b: String) throws -> TracePlan {
        let session = try session(at: a)
        let from = try BundledRealData.point(try BundledRealData.station(a, in: "afr_sched").coordinate, in: session.world)
        let to = try BundledRealData.point(try BundledRealData.station(b, in: "afr_sched").coordinate, in: session.world)
        let reach = Int64(60 * WorldCoordinate.unitsPerMetre)
        let start = try XCTUnwrap(session.tracedPoint(near: from, reach: reach), a)
        let end = try XCTUnwrap(session.tracedPoint(near: to, reach: reach), b)
        return try XCTUnwrap(session.tracePlan(from: .point(start), to: .point(end)), "\(a) to \(b)")
    }

    /// Every stretch between two neighbouring stations, the spiral, the
    /// switchbacks' legs and the Zhushan Line among them, is laid whole:
    /// before, four of them stopped at a kink in the drawing (16 to 19 m)
    /// or at an edge a little over 70‰.
    func testEveryStretchBetweenNeighbouringStationsIsTracedWhole() throws {
        let main = [
            "嘉義", "北門", "鹿麻產", "竹崎", "樟腦寮", "獨立山", "梨園寮", "交力坪", "水社寮", "奮起湖", "多林", "十字路", "屏遮那", "第一分道",
            "第二分道", "二萬平", "神木", "阿里山", "沼平",
        ]
        for (a, b) in Array(zip(main, main.dropFirst())) + [("阿里山", "對高岳"), ("對高岳", "祝山")] {
            let plan = try self.plan(from: a, to: b)
            XCTAssertNil(plan.problem, "\(a) to \(b)")
            XCTAssertEqual(plan.buildable, plan.stretches.count, "\(a) to \(b)")
            for stretch in plan.stretches {
                let grade = try XCTUnwrap(TrackGeometry(from: stretch.from, to: stretch.to, curve: stretch.curve)).steepestGrade
                XCTAssertTrue(grade.isNoSteeper(than: TrackProfile.maximumMountainGrade), "\(a) to \(b)")
            }
        }
    }

    /// One stroke across the first switchback stops where the trains
    /// reverse, and says so rather than that the line bends too tightly.
    func testAStrokeAcrossASwitchbackSaysTrainsReverseThere() throws {
        let plan = try plan(from: "屏遮那", to: "二萬平")
        XCTAssertEqual(plan.brief, "真實鐵路在這裡要折返")
        XCTAssertGreaterThan(plan.buildable, 0)
        XCTAssertLessThan(plan.buildable, plan.stretches.count)
    }

    /// A mountain line's tightest traced curve is its own.
    func testTheMountainLineHasItsOwnTightestCurve() {
        XCTAssertEqual(GameSession.traceMinimumRadius(ofSystem: "afr_sched"), GameSession.mountainTraceMinimumRadius)
        XCTAssertLessThan(GameSession.reversalRadius, GameSession.mountainTraceMinimumRadius)
        XCTAssertEqual(GameSession.traceMinimumRadius(ofSystem: "trtc_sched"), GameSession.urbanTraceMinimumRadius)
    }
}
