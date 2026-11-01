import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// TRACELAG (decision 521): the owner's 100.1 report, a drag from the end
/// of track on the real map held each step of the map for 650–870 ms.
/// Each step previews the stretch on a copy of the world, and the copy read
/// the ground of the blocks under it from the heights file again: some
/// twenty of the file's rows decoded for each block, at every step, and
/// again when the stretch was built on the copy. A block's ground is worked
/// out once now.
@MainActor
final class TraceDragCostTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre
    private let metre = Int64(WorldCoordinate.unitsPerMetre)

    /// Track laid along the Yilan Line from Waiao towards Toucheng on the
    /// coast, as the owner's, and the finger's places along a drag on from
    /// its end.
    private func coast(heights: HeightGrid) throws -> (session: GameSession, end: PlanPoint, steps: [PlanPoint]) {
        let waiao = try BundledRealData.station("外澳", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(waiao.anchor))
        try world.mapGround()
        let session = GameSession(world: world, language: .english)
        session.heights = heights
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        let from = try BundledRealData.point(waiao.coordinate, in: world)
        let toucheng = try BundledRealData.point(try BundledRealData.station("頭城", in: "tra_sched").coordinate, in: world)
        let middle = PlanPoint(x: (from.x + toucheng.x) / 2, y: (from.y + toucheng.y) / 2)
        session.networkTracesRealRailway = true
        session.tapNetwork(at: from, reach: reach)
        session.tapNetwork(at: middle, reach: reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.networkTracesRealRailway = false
        guard case .node(let node)? = session.networkStart, let end = session.world.network.node(node)?.position.plan else {
            throw XCTSkip("no end to drag from")
        }
        let steps = (1...8).map { step in
            PlanPoint(x: end.x + (toucheng.x - end.x) * Int64(step) / 8 + Int64(step) * 8 * metre, y: end.y + (toucheng.y - end.y) * Int64(step) / 8)
        }
        return (session, end, steps)
    }

    private func drag(_ session: GameSession, from end: PlanPoint, over steps: [PlanPoint]) -> [NetworkPreview?] {
        let previews = steps.map { step -> NetworkPreview? in
            session.dragNetwork(from: end, to: step, reach: reach)
            _ = session.networkOverlay
            return session.networkPreview
        }
        session.endNetworkDrag(from: end, to: steps.last ?? end, reach: reach)
        return previews
    }

    /// Dragging over the same ground again reads none of it from the
    /// heights file, and the previews are the same as with it read afresh.
    func testADragReadsEachBlocksGroundOnce() throws {
        let heights = try XCTUnwrap(TRADemoTests.heights)
        let (session, end, steps) = try coast(heights: heights)
        let first = drag(session, from: end, over: steps)
        XCTAssertTrue(first.contains { $0?.problem == nil && $0?.cost != nil }, "some step can be built")
        let read = heights.groundMemo.blocksWorkedOut
        let previews = session.buildPreviewsWorkedOut
        let again = drag(session, from: end, over: steps)
        XCTAssertEqual(session.buildPreviewsWorkedOut, previews + steps.count, "each step is previewed again")
        XCTAssertEqual(heights.groundMemo.blocksWorkedOut, read, "and reads no ground from the file")
        XCTAssertEqual(again, first)

        // The same drag with the ground read afresh: the same previews.
        let fresh = try HeightGrid(data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent(
            "RealWorld/taiwan_heights.dat"
        )))
        let (other, otherEnd, otherSteps) = try coast(heights: fresh)
        XCTAssertEqual(drag(other, from: otherEnd, over: otherSteps), first)
    }

    /// Decision 521's second sequel: the traced preview prices the copy the
    /// trace built its stretches on, not the chain built a second time,
    /// and that copy is the chain built afresh.
    func testATracedPreviewBuildsTheChainOnce() throws {
        let heights = try XCTUnwrap(TRADemoTests.heights)
        let waiao = try BundledRealData.station("外澳", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(waiao.anchor))
        try world.mapGround()
        let session = GameSession(world: world, language: .english)
        session.heights = heights
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        // Single track, the player's choice: the real line is double here,
        // and the double track's preview is planned apart (decision 247).
        session.networkBuildsDouble = false
        let from = try BundledRealData.point(waiao.coordinate, in: world)
        let toucheng = try BundledRealData.point(try BundledRealData.station("頭城", in: "tra_sched").coordinate, in: world)
        session.tapNetwork(at: from, reach: reach)
        session.tapNetwork(at: PlanPoint(x: (from.x + toucheng.x) / 2, y: (from.y + toucheng.y) / 2), reach: reach)
        let start = try XCTUnwrap(session.networkStart), end = try XCTUnwrap(session.networkEnd)

        let plan = try XCTUnwrap(session.traceAlong(from: start, to: end))
        XCTAssertGreaterThan(plan.buildable, 0, "some of it can be built")
        let traced = try XCTUnwrap(plan.built, "the trace keeps the copy it built on")
        var again = session.world.trackPreviewCopy()
        _ = try session.apply(.buildTrackChain(Array(plan.stretches.prefix(plan.buildable))), to: &again)
        XCTAssertEqual(traced.network, again.network)
        XCTAssertEqual(traced.economy.balance, again.economy.balance)
        XCTAssertEqual(traced.placedBuildings, again.placedBuildings)

        let preview = try XCTUnwrap(session.tracePreview(from: start, to: end)?.0)
        XCTAssertEqual(preview.cost, Money(GameWorld.pricingBalance.amount - again.economy.balance.amount))
    }

    /// Decision 521's fourth sequel: a trace that joins track already laid
    /// (Taipei to Banqiao over its middle third, decision 468) builds its
    /// pieces on one copy, and that copy is the chain built afresh.
    func testAJoinedTraceBuildsItsPiecesOnOneCopy() throws {
        let taipei = try BundledRealData.station("臺北", in: "tra_sched")
        let session = GameSession(world: GameWorld.newGame(anchor: try XCTUnwrap(taipei.anchor)), language: .english)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = false
        session.networkDoubleChosen = true
        let from = try BundledRealData.point(taipei.coordinate, in: session.world)
        let to = try BundledRealData.point(try BundledRealData.station("板橋", in: "tra_sched").coordinate, in: session.world)
        let traces = try XCTUnwrap(session.realRailwayTraces)
        let way = WorldPath(try XCTUnwrap(traces.path(
            from: try XCTUnwrap(traces.snap(WorldVector(from), within: 50 * Double(metre))).place,
            to: try XCTUnwrap(traces.snap(WorldVector(to), within: 50 * Double(metre))).place
        )))
        session.tapNetwork(at: way.point(at: way.length / 3).plan, reach: reach)
        session.tapNetwork(at: way.point(at: way.length * 2 / 3).plan, reach: reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.clearNetworkDraft()
        session.tapNetwork(at: from, reach: reach)
        session.tapNetwork(at: to, reach: reach)
        let start = try XCTUnwrap(session.networkStart), end = try XCTUnwrap(session.networkEnd)

        let plan = try XCTUnwrap(session.traceAlong(from: start, to: end))
        XCTAssertFalse(plan.existing.isEmpty, "it joins the track laid")
        XCTAssertGreaterThan(plan.buildable, 0)
        let traced = try XCTUnwrap(plan.built, "the pieces' copy")
        XCTAssertEqual(plan.builtEdges.count, plan.buildable)
        var again = session.world.trackPreviewCopy()
        _ = try session.apply(.buildTrackChain(Array(plan.stretches.prefix(plan.buildable))), to: &again)
        XCTAssertEqual(traced.network, again.network)
        XCTAssertEqual(traced.economy.balance, again.economy.balance)
        XCTAssertEqual(traced.placedBuildings, again.placedBuildings)
        let preview = try XCTUnwrap(session.tracePreview(from: start, to: end)?.0)
        XCTAssertEqual(preview.cost, Money(GameWorld.pricingBalance.amount - again.economy.balance.amount))
    }

    /// Decision 521's fourth sequel: a double trace (Luodong to Dongshan,
    /// decision 247) plans its second track on the copy the trace built
    /// the first on, and finds what it finds with the first built afresh.
    func testADoubleTracePlansOnTheTracedCopy() throws {
        let luodong = try BundledRealData.station("羅東", in: "tra_sched")
        let session = GameSession(world: GameWorld.newGame(anchor: try XCTUnwrap(luodong.anchor)), language: .english)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.tapNetwork(at: try BundledRealData.point(luodong.coordinate, in: session.world), reach: reach)
        session.tapNetwork(at: try BundledRealData.point(try BundledRealData.station("冬山", in: "tra_sched").coordinate, in: session.world), reach: reach)
        let start = try XCTUnwrap(session.networkStart), end = try XCTUnwrap(session.networkEnd)
        let plan = try XCTUnwrap(session.traceAlong(from: start, to: end))
        XCTAssertNotNil(plan.built)
        let built = Array(plan.stretches.prefix(plan.buildable))
        guard case .success(let reused) = session.tracedDoublePlan(built, from: start, to: end, reachesEnd: !plan.stopped, traced: plan),
              case .success(let afresh) = session.tracedDoublePlan(built, from: start, to: end, reachesEnd: !plan.stopped)
        else { return XCTFail("the second track is laid both ways") }
        XCTAssertEqual(reused.command, afresh.command)
        XCTAssertEqual(reused.built.network, afresh.built.network)
        XCTAssertEqual(reused.built.economy.balance, afresh.built.economy.balance)
        XCTAssertEqual(reused.built.placedBuildings, afresh.built.placedBuildings)
        XCTAssertEqual(reused.outcome, afresh.outcome)
        XCTAssertEqual(reused.crossoverPoints, afresh.crossoverPoints)
    }

    /// Decision 521's fourth sequel: the way's index gives each point the
    /// nearest place the way does, and passes over only edges no point of
    /// which comes within reach.
    func testTheWaysIndexGivesTheNearestPlaceTheWayDoes() throws {
        let taipei = try BundledRealData.station("臺北", in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(taipei.anchor))
        let session = GameSession(world: world, language: .english)
        session.railways = try BundledRealData.railways()
        let traces = try XCTUnwrap(session.realRailwayTraces)
        let from = try BundledRealData.point(taipei.coordinate, in: world)
        let to = try BundledRealData.point(try BundledRealData.station("板橋", in: "tra_sched").coordinate, in: world)
        let way = WorldPath(try XCTUnwrap(traces.path(
            from: try XCTUnwrap(traces.snap(WorldVector(from), within: 50 * Double(metre))).place,
            to: try XCTUnwrap(traces.snap(WorldVector(to), within: 50 * Double(metre))).place
        ))).smoothed()
        XCTAssertGreaterThan(way.points.count, TraceOverlap.Index.chunk * 4, "several pieces")
        let index = TraceOverlap.Index(way)
        // Points along the way, beside it, beyond its ends and far off.
        var points: [WorldVector] = []
        for step in 0...400 {
            let along = way.length * (Double(step) / 400 * 1.2 - 0.1)
            let base = way.point(at: along)
            for side in [-2_000.0, -300, -9, -8, 0, 3, 8, 50, 900] {
                points.append(WorldVector(x: base.x + side * Double(metre) * 0.6, y: base.y - side * Double(metre) * 0.8))
            }
        }
        for point in points {
            let a = index.nearest(point), b = way.nearest(point)
            XCTAssertEqual(a.along, b.along, "\(point)")
            XCTAssertEqual(a.away, b.away, "\(point)")
        }
        for (a, b) in zip(points, points.dropFirst()) where !index.comesWithin(TraceOverlap.reach, of: [a, b]) {
            XCTAssertGreaterThan(way.nearest(a).away, TraceOverlap.reach)
            XCTAssertGreaterThan(way.nearest(b).away, TraceOverlap.reach)
        }
    }

    /// The memo gives the blocks as the file does, in order, and keeps each
    /// frame apart.
    func testTheMemoGivesWhatTheRowsDo() throws {
        let heights = try XCTUnwrap(TRADemoTests.heights)
        let waiao = try BundledRealData.station("外澳", in: "tra_sched")
        let frame = try XCTUnwrap(RealWorldFrame(world: GameWorld.newGame(anchor: try XCTUnwrap(waiao.anchor))))
        let blocks = [LandBlock(row: 3, column: 17), LandBlock(row: 3, column: 16), LandBlock(row: 4, column: 16)]
        let worked = heights.workOutGround(of: blocks.sorted(), frame: frame)
        let before = heights.groundMemo.blocksWorkedOut
        XCTAssertEqual(heights.ground(of: blocks, frame: frame), worked)
        XCTAssertEqual(heights.ground(of: [blocks[1]], frame: frame), worked.filter { $0.block == blocks[1] })
        XCTAssertLessThanOrEqual(heights.groundMemo.blocksWorkedOut, before + blocks.count, "each worked out at most once")
        let taipei = try BundledRealData.station("臺北", in: "tra_sched")
        let other = try XCTUnwrap(RealWorldFrame(world: GameWorld.newGame(anchor: try XCTUnwrap(taipei.anchor))))
        XCTAssertEqual(heights.ground(of: blocks, frame: other), heights.workOutGround(of: blocks.sorted(), frame: other))
    }
}
