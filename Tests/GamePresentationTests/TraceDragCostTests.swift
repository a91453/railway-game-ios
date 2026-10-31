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
