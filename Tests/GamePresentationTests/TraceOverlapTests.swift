import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 468: a trace along a real line takes the track already laid on
/// that line as laid: it skips it, joins both its ends and traces on.
@MainActor
final class TraceOverlapTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    // MARK: - Which track lies along the way

    /// A straight way 1 km east, and an edge of points given in metres.
    private var way: WorldPath { WorldPath([WorldVector(x: 0, y: 0), WorldVector(x: 1_000 * metre, y: 0)]) }

    private func edge(_ number: Int, _ from: Int, _ to: Int, _ points: [(Double, Double)]) -> TraceOverlap.Edge {
        TraceOverlap.Edge(
            id: TrackEdgeID.edge(number), from: TrackNodeID.node(from), to: TrackNodeID.node(to),
            points: points.map { WorldVector(x: $0.0 * metre, y: $0.1 * metre) }
        )
    }

    func testTrackAlongTheWayIsOneRunFromItsFirstNodeToItsLast() throws {
        // Two edges end to end, the second drawn backward, 3 m off the way.
        let runs = TraceOverlap.runs(along: way, edges: [
            edge(1, 1, 2, [(300, 3), (400, 3), (500, 3)]),
            edge(2, 3, 2, [(700, 2), (600, 2), (500, 3)]),
        ])
        XCTAssertEqual(runs.count, 1)
        let run = try XCTUnwrap(runs.first)
        XCTAssertEqual(run.entry, TrackNodeID.node(1))
        XCTAssertEqual(run.exit, TrackNodeID.node(3))
        XCTAssertEqual(run.edges, [TrackEdgeID.edge(1), TrackEdgeID.edge(2)])
        XCTAssertEqual(run.range.lowerBound / metre, 300, accuracy: 0.5)
        XCTAssertEqual(run.range.upperBound / metre, 700, accuracy: 0.5)
        XCTAssertEqual(run.points.first?.x ?? 0, 300 * metre, accuracy: 1)
        XCTAssertEqual(run.points.last?.x ?? 0, 700 * metre, accuracy: 1)
    }

    func testTrackAcrossTheWayOrFarBesideItIsNotTheSameLine() {
        XCTAssertTrue(TraceOverlap.runs(along: way, edges: [
            // Across it.
            edge(1, 1, 2, [(500, -150), (500, 0), (500, 150)]),
            // Across it, short enough to lie within reach.
            edge(2, 3, 4, [(600, -6), (600, 6)]),
            // Beside it, 20 m off: another line.
            edge(3, 5, 6, [(100, 20), (400, 20)]),
            // Along it, then off it.
            edge(4, 7, 8, [(700, 0), (800, 0), (900, 60)]),
        ]).isEmpty)
    }

    func testOfADoubleTrackTheNearerIsTakenOnce() throws {
        let runs = TraceOverlap.runs(along: way, edges: [
            edge(1, 1, 2, [(200, 5.5), (600, 5.5)]),
            edge(2, 3, 4, [(200, 0.5), (600, 0.5)]),
        ])
        XCTAssertEqual(runs.map(\.edges), [[TrackEdgeID.edge(2)]])
    }

    func testAnEdgeReachingPastTheWaysEndCounts() throws {
        // The trace starts partway along it.
        let runs = TraceOverlap.runs(along: way, edges: [edge(1, 1, 2, [(-200, 0), (0, 0), (300, 0)])])
        XCTAssertEqual(runs.map(\.exit), [TrackNodeID.node(2)])
        XCTAssertEqual(runs.first?.range.lowerBound ?? -1, 0)
        // A track behind the start, leaving it backward, does not.
        XCTAssertTrue(TraceOverlap.runs(along: way, edges: [edge(1, 1, 2, [(-300, 0), (0, 0)])]).isEmpty)
    }

    // MARK: - Tracing on a real-world map

    /// A real-world game at Taipei Main Station tracing single track, and
    /// the real way to Banqiao.
    private func taipei() throws -> (session: GameSession, taipei: PlanPoint, banqiao: PlanPoint, way: WorldPath) {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = false
        session.networkDoubleChosen = true
        let banqiao = try BundledRealData.point(try BundledRealData.station("板橋", in: "tra_sched").coordinate, in: world)
        let taipei = try BundledRealData.point(tra.coordinate, in: world)
        let traces = try XCTUnwrap(session.realRailwayTraces)
        let way = try XCTUnwrap(traces.path(
            from: try XCTUnwrap(traces.snap(WorldVector(taipei), within: 50 * metre)).place,
            to: try XCTUnwrap(traces.snap(WorldVector(banqiao), within: 50 * metre)).place
        ))
        return (session, taipei, banqiao, WorldPath(way))
    }

    func testATraceOverTrackAlreadyLaidOnTheLineSkipsItAndGoesOn() throws {
        let (session, taipei, banqiao, way) = try taipei()
        // B: the middle third, traced first.
        session.tapNetwork(at: way.point(at: way.length / 3).plan, reach: reach)
        session.tapNetwork(at: way.point(at: way.length * 2 / 3).plan, reach: reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let middle = session.world.network.edges.count
        XCTAssertGreaterThan(middle, 2)
        session.clearNetworkDraft()

        // A to C over it.
        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem)
        XCTAssertTrue(preview.unbuilt.isEmpty, "it does not stop")
        XCTAssertEqual(preview.existing.count, 1)
        XCTAssertEqual(preview.newPieces.count, 2, "before it and after it")
        let note = try XCTUnwrap(preview.traceNote)
        XCTAssertTrue(note.hasPrefix("接上已經鋪好的軌道"), note)
        XCTAssertFalse(note.contains("停下"), note)
        // The new track is two thirds of the way, at the price of that.
        XCTAssertEqual(Double(preview.length), way.length * 2 / 3, accuracy: 400 * metre)
        XCTAssertEqual(session.networkOverlay?.existing.count, 1)

        let before = session.world
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.contains("接上已經鋪好的軌道") ?? false, session.message?.text ?? "")
        XCTAssertEqual(session.world.economy.balance.amount, before.economy.balance.amount - (preview.cost?.amount ?? 0))
        let built = try XCTUnwrap(preview.traced)
        XCTAssertEqual(session.world.network.edges.count, middle + built)
        // One line end to end from Taipei to Banqiao: two ends, no
        // junction.
        let ends = session.world.network.nodes.map(\.ends.count)
        XCTAssertEqual(ends.filter { $0 == 1 }.count, 2)
        XCTAssertTrue(ends.allSatisfy { $0 <= 2 }, "\(ends)")
        // One command.
        guard case .command(.buildTrackChain(let stretches))? = session.commandLog.entries.last?.action else {
            return XCTFail("logged as one chain")
        }
        XCTAssertEqual(stretches.count, built)
        session.undo()
        XCTAssertEqual(session.world, before)
    }

    func testTrackAcrossTheLineStillStopsTheTrace() throws {
        let (session, taipei, banqiao, way) = try taipei()
        let middle = way.point(at: way.length / 2), across = way.tangent(at: way.length / 2).normal * (150 * metre)
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
        XCTAssertTrue(preview.existing.isEmpty)
        let note = try XCTUnwrap(preview.traceNote)
        XCTAssertTrue(note.hasPrefix("描到 "), note)
        XCTAssertFalse(preview.unbuilt.isEmpty)
    }

    func testABoughtLineIsTracedOnFromItsEnd() throws {
        // The Shen'ao Line, bought, traced on from partway along it, past
        // its end at Ruifang toward Houtong (where the bundled lines' join
        // there crosses the bought track at grade, GameCore stops it, as
        // before: what matters is that it leaves from the bought line).
        let network = "SHENAO", first = "海科館", second = "猴硐"
        let railways = try BundledRealData.railways()
        let runs = try XCTUnwrap(railways.branchRuns[network])
        let stations = try runs.stops.map { try BundledRealData.station($0, in: "tra_sched") }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        let world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 20, height: 1 << 20), balance: Money(100_000_000_000))
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = railways
        let pingxi = try XCTUnwrap(session.buyableRealLines.first { $0.network == network })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: pingxi)), session.message?.text ?? "")
        let bought = session.world.network.edges.count
        // Its trains taken off, so none stands on the track joined.
        for train in session.world.trains {
            _ = try? session.performCommand(.edit(.unassignTrain(train.id)))
            _ = try? session.performCommand(.edit(.stopTrainService(train.id)))
            _ = try? session.performCommand(.edit(.unplaceTrain(train.id)))
            try session.performCommand(.edit(.sellTrain(train.id)))
        }
        XCTAssertTrue(session.world.trains.isEmpty)

        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = false
        session.networkDoubleChosen = true
        let dahua = try BundledRealData.point(try BundledRealData.station(first, in: "tra_sched").coordinate, in: session.world)
        let houtong = try BundledRealData.point(try BundledRealData.station(second, in: "tra_sched").coordinate, in: session.world)
        session.tapNetwork(at: dahua, reach: reach)
        session.tapNetwork(at: houtong, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem, preview.traceNote ?? "")
        XCTAssertFalse(preview.existing.isEmpty, "the bought line is taken as laid")
        XCTAssertTrue(preview.traceNote?.hasPrefix("接上已經鋪好的軌道") ?? false, preview.traceNote ?? "")
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let built = try XCTUnwrap(preview.traced)
        XCTAssertEqual(session.world.network.edges.count, bought + built)
        // The new track leaves from a node of the bought line.
        guard case .command(.buildTrackChain(let stretches))? = session.commandLog.entries.last?.action,
              case .node(let node)? = stretches.first?.start else { return XCTFail("one chain from a node") }
        XCTAssertNotNil(world.network.node(node) ?? session.world.network.node(node))
        XCTAssertGreaterThanOrEqual(session.world.network.node(node)?.ends.count ?? 0, 2)
    }

    func testAChainStretchStartingAtANodeOfItsOwnStartsThere() {
        let point = WorldCoordinate(x: 0, y: 0, z: 0)
        func stretch(_ start: NetworkAnchor) -> PlayerCommand.TrackStretch {
            PlayerCommand.TrackStretch(start: start, end: .point(point.plan), from: point, to: point, curve: .straight, profile: .uniform, structure: .automatic, ground: [])
        }
        XCTAssertEqual(stretch(.point(point.plan)).starting(at: TrackNodeID.node(4)).start, .node(TrackNodeID.node(4)))
        XCTAssertEqual(stretch(.node(TrackNodeID.node(9))).starting(at: TrackNodeID.node(4)).start, .node(TrackNodeID.node(9)))
    }
}
