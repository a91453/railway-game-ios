import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 213: the network tool traces Taiwan's real railway, on a
/// real-world map at Taipei Main Station with the bundled lines.
@MainActor
final class RealRailwayTracingTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A real-world game at Taipei Main Station with the network tool
    /// laying track, tracing on, and the world points of two TRA stations.
    private func taipei(in language: DisplayLanguage = .traditionalChinese) throws -> (session: GameSession, taipei: PlanPoint, banqiao: PlanPoint) {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        let session = GameSession(world: world, language: language)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        let banqiao = try BundledRealData.station("板橋", in: "tra_sched")
        return (session, try BundledRealData.point(tra.coordinate, in: world), try BundledRealData.point(banqiao.coordinate, in: world))
    }

    /// How far `point` is from the nearest real line.
    private func distanceToRealLine(_ point: PlanPoint, in session: GameSession) throws -> Double {
        let traces = try XCTUnwrap(session.realRailwayTraces)
        return try XCTUnwrap(traces.snap(WorldVector(point), within: 1_000 * metre)).distance
    }

    func testATraceFollowsTheRealLineAndIsBuiltAsOneCommand() throws {
        let (session, taipei, banqiao) = try taipei()
        // Taps a little off the line land on it.
        session.tapNetwork(at: PlanPoint(x: taipei.x, y: taipei.y + 640), reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        for anchor in [session.networkStart, session.networkEnd] {
            guard case .point(let point)? = anchor else { return XCTFail("a new point on the line") }
            XCTAssertLessThan(try distanceToRealLine(point, in: session), 1 * metre)
        }
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem)
        XCTAssertNil(preview.traceNote)
        let edges = try XCTUnwrap(preview.traced)
        XCTAssertGreaterThan(edges, 10, "many edges, not one curve")
        // The real Western Trunk Line is 7.2 km from Taipei to Banqiao.
        XCTAssertEqual(Double(preview.length) / metre, 7_200, accuracy: 250)
        // The track keeps to the real line all the way.
        for point in stride(from: 0, to: preview.points.count, by: 8).map({ preview.points[$0] }) {
            XCTAssertLessThan(try distanceToRealLine(point.plan, in: session), 12 * metre)
        }
        XCTAssertFalse(session.networkTracedWay.isEmpty, "the real line lights up under it")
        XCTAssertFalse(session.traceableRealLines.isEmpty)

        let before = session.world
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, edges)
        XCTAssertEqual(session.world.economy.balance.amount, before.economy.balance.amount - (preview.cost?.amount ?? 0))
        // Joined end to end: every node but the two ends has two edges.
        let ends = session.world.network.nodes.map(\.ends.count)
        XCTAssertEqual(ends.filter { $0 == 1 }.count, 2)
        XCTAssertEqual(ends.filter { $0 == 2 }.count, edges - 1)
        // One command, logged as itself, and one undo takes it all back.
        guard case .command(.buildTrackChain(let stretches))? = session.commandLog.entries.last?.action else {
            return XCTFail("logged as a chain")
        }
        XCTAssertEqual(stretches.count, edges)
        if case .node? = session.networkStart {} else { XCTFail("the next stretch starts at its end") }
        session.undo()
        XCTAssertEqual(session.world, before)
    }

    /// The message after a trace says how far and for how much, in words
    /// a player reads: no track-graph terms.
    func testTheTracedMessageSaysHowFarAndForHowMuch() throws {
        let (session, taipei, banqiao) = try taipei(in: .english)
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let pieces = try XCTUnwrap(session.networkPreview?.traced)
        session.buildNetworkTrack()
        let text = try XCTUnwrap(session.message?.text)
        XCTAssertTrue(text.hasPrefix("Traced the real railway for "), text)
        XCTAssertTrue(text.contains("(\(pieces) pieces of track)"), text)
        XCTAssertFalse(text.contains("edge"), text)
    }

    func testTheChainCodesAsItIs() throws {
        let (session, taipei, banqiao) = try taipei()
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let plan = try XCTUnwrap(session.tracePlan(from: try XCTUnwrap(session.networkStart), to: try XCTUnwrap(session.networkEnd)))
        let command = PlayerCommand.buildTrackChain(plan.stretches)
        let data = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: data), command)
        XCTAssertThrowsError(try JSONDecoder().decode(PlayerCommand.self, from: Data(#"{"kind":"buildTrackChain"}"#.utf8)))
    }

    /// Where GameCore refuses an edge, the trace stops before it, says
    /// why, and what comes before can be built.
    func testATraceStopsWhereGameCoreRefusesAndSaysWhy() throws {
        let (session, taipei, banqiao) = try taipei()
        // A track across the real line about halfway, laid by hand.
        let traces = try XCTUnwrap(session.realRailwayTraces)
        let way = try XCTUnwrap(traces.path(
            from: try XCTUnwrap(traces.snap(WorldVector(taipei), within: 50 * metre)).place,
            to: try XCTUnwrap(traces.snap(WorldVector(banqiao), within: 50 * metre)).place
        ))
        let path = WorldPath(way)
        let middle = path.point(at: path.length / 2), across = path.tangent(at: path.length / 2).normal * (150 * metre)
        session.networkTracesRealRailway = false
        session.tapNetwork(at: (middle - across).plan, reach: 1)
        session.tapNetwork(at: (middle + across).plan, reach: 1)
        session.buildNetworkTrack()
        XCTAssertEqual(session.world.network.edges.count, 1, session.message?.text ?? "")
        session.clearNetworkDraft()
        session.networkTracesRealRailway = true

        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem, "what comes before can be built")
        let note = try XCTUnwrap(preview.traceNote)
        XCTAssertTrue(note.hasPrefix("描到 "), note)
        XCTAssertFalse(preview.unbuilt.isEmpty)
        XCTAssertEqual(Double(preview.length), path.length / 2, accuracy: 600 * metre)
        XCTAssertFalse(session.networkOverlay?.unbuilt.isEmpty ?? true)

        let built = try XCTUnwrap(preview.traced)
        session.buildNetworkTrack()
        XCTAssertEqual(session.world.network.edges.count, 1 + built)
        XCTAssertTrue(session.message?.text.contains("停下") ?? false, session.message?.text ?? "")
    }

    func testOffTheOptionOrTheMapThereIsOneStretch() throws {
        let (session, taipei, banqiao) = try taipei()
        session.networkTracesRealRailway = false
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        XCTAssertNil(session.networkPreview?.traced)
        XCTAssertTrue(session.traceableRealLines.isEmpty)
        XCTAssertTrue(session.networkTracedWay.isEmpty)
        // A blank map has no real railway to trace.
        let blank = GameSession(world: .newGame(), language: .english)
        blank.railways = try BundledRealData.railways()
        XCTAssertFalse(blank.canTraceRealRailway)
        XCTAssertTrue(session.canTraceRealRailway)
    }

    /// Tracing, a drag that starts on a real line draws track rather than
    /// moving the map; off, it moves the map as before.
    func testADragFromARealLineDrawsWhileTracing() throws {
        let (session, taipei, banqiao) = try taipei()
        XCTAssertTrue(session.networkDragDraws(from: taipei, reach: reach))
        session.dragNetwork(from: taipei, to: banqiao, reach: reach)
        XCTAssertNotNil(session.networkPreview?.traced)
        session.endNetworkDrag(from: taipei, to: banqiao, reach: reach)
        session.clearNetworkDraft()
        session.networkTracesRealRailway = false
        XCTAssertFalse(session.networkDragDraws(from: taipei, reach: reach))
    }

    /// Handoff §7.1 (PR526_626 §5, U7): the map reads the traced way at
    /// every redraw, and each read ran a shortest path along the real
    /// lines. It is worked out once for each pair of points.
    func testTheTracedWayIsWorkedOutOnceForEachPairOfPoints() throws {
        let (session, taipei, banqiao) = try taipei()
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let way = session.networkTracedWay
        XCTAssertFalse(way.isEmpty)
        XCTAssertEqual(session.networkTracedWay, way)
        XCTAssertEqual(session.networkOverlay?.tracedWay ?? way, way)
        XCTAssertEqual(session.tracedWaysWorkedOut, 1, "read three times, worked out once")

        session.clearNetworkDraft()
        session.tapNetwork(at: taipei, reach: reach)
        let halfway = PlanPoint(x: (taipei.x + banqiao.x) / 2, y: (taipei.y + banqiao.y) / 2)
        session.dragNetwork(from: taipei, to: halfway, reach: reach)
        _ = session.networkTracedWay
        XCTAssertEqual(session.tracedWaysWorkedOut, 2, "the finger is a new end")
    }

    func testTheTightestRadiusOfAnEdge() {
        func stretch(_ curve: TrackCurve, to: PlanPoint) -> PlayerCommand.TrackStretch {
            PlayerCommand.TrackStretch(
                start: .point(PlanPoint(x: 0, y: 0)), end: .point(to), from: WorldCoordinate(x: 0, y: 0, z: 0),
                to: WorldCoordinate(x: to.x, y: to.y, z: 0), curve: curve, profile: .uniform, structure: .surface, ground: []
            )
        }
        XCTAssertNil(GameSession.tightestRadius(of: stretch(.straight, to: PlanPoint(x: 6_400, y: 0))))
        // A quarter circle of radius 100 m as a cubic (handles 0.5523 r).
        let r = 6_400.0, k = 0.5523 * r
        let quarter = stretch(.cubic(PlanPoint(x: Int64(k), y: 0), PlanPoint(x: Int64(r), y: Int64(r - k))), to: PlanPoint(x: Int64(r), y: Int64(r)))
        XCTAssertEqual(GameSession.tightestRadius(of: quarter) ?? 0, r, accuracy: r * 0.03)
    }
}
