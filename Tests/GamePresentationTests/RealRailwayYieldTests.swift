import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 468: the real lines and real trains make way for the player's
/// track and stations on a real-world map.
@MainActor
final class RealRailwayYieldTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A real-world game at Taipei Main Station with the player's single
    /// track traced from Taipei to Banqiao.
    private func traced() throws -> (session: GameSession, frame: RealWorldFrame, railways: RealRailways) {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        let session = GameSession(world: world, language: .traditionalChinese)
        let railways = try BundledRealData.railways()
        session.railways = railways
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = false
        session.networkDoubleChosen = true
        session.tapNetwork(at: try BundledRealData.point(tra.coordinate, in: world), reach: reach)
        session.tapNetwork(at: try BundledRealData.point(try BundledRealData.station("板橋", in: "tra_sched").coordinate, in: world), reach: reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        return (session, try XCTUnwrap(RealWorldFrame(world: session.world)), railways)
    }

    /// The length of `points` in metres.
    private func metres(_ points: [RealRailways.Coordinate]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + RealStationTransfers.distanceMetres($1.0, $1.1) }
    }

    func testTheRealLineUnderThePlayersTrackIsNotDrawn() throws {
        let (session, frame, railways) = try traced()
        let yield = RealRailwayYield(railways: railways, operations: nil, world: session.world, frame: frame)
        XCTAssertFalse(yield.pieces.isEmpty)
        // About 7 km of the TRA's line between Taipei and Banqiao is gone.
        var gone = 0.0
        for (id, pieces) in yield.pieces {
            let line = try XCTUnwrap(railways.lines.first { $0.id == id })
            gone += metres(line.points) - pieces.map(metres).reduce(0, +)
        }
        XCTAssertGreaterThan(gone, 6_000)
        let tra = yield.pieces.keys.compactMap { id in railways.lines.first { $0.id == id } }.filter { $0.system.id == "tra_sched" }
        XCTAssertFalse(tra.isEmpty, "the TRA's own line")
        // A line it does not cover is drawn whole.
        let other = try XCTUnwrap(railways.lines(near: frame.anchor, within: 5_000).first { yield.pieces[$0.id] == nil })
        XCTAssertEqual(yield.drawnPieces(of: other).count, 1)
        XCTAssertEqual(yield.drawnPieces(of: other).first?.count, other.points.count)

        // Taking the track away draws it again.
        var bare = session.world
        for edge in bare.network.edges { try bare.removeTrackEdge(edge.id) }
        XCTAssertEqual(RealRailwayYield(railways: railways, operations: nil, world: bare, frame: frame), .none)
    }

    func testTrackAcrossARealLineDoesNotCutIt() throws {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        let session = GameSession(world: world, language: .traditionalChinese)
        let railways = try BundledRealData.railways()
        session.railways = railways
        session.selectTool(.network)
        session.setNetworkMode(.build)
        let traces = try XCTUnwrap(session.realRailwayTraces)
        let banqiao = try BundledRealData.point(try BundledRealData.station("板橋", in: "tra_sched").coordinate, in: world)
        let way = WorldPath(try XCTUnwrap(traces.path(
            from: try XCTUnwrap(traces.snap(WorldVector(try BundledRealData.point(tra.coordinate, in: world)), within: 50 * metre)).place,
            to: try XCTUnwrap(traces.snap(WorldVector(banqiao), within: 50 * metre)).place
        )))
        let middle = way.point(at: way.length / 2), across = way.tangent(at: way.length / 2).normal * (150 * metre)
        session.tapNetwork(at: (middle - across).plan, reach: 1)
        session.tapNetwork(at: (middle + across).plan, reach: 1)
        session.buildNetworkTrack()
        XCTAssertEqual(session.world.network.edges.count, 1, session.message?.text ?? "")
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        XCTAssertEqual(RealRailwayYield(railways: railways, operations: nil, world: session.world, frame: frame), .none)
    }

    func testARealTrainIsNotDrawnOnTheCoveredStretchOnly() throws {
        let (session, frame, railways) = try traced()
        let yield = RealRailwayYield(railways: railways, operations: nil, world: session.world, frame: frame)
        // On the player's track, running along it, and beside it across it
        // or far from it.
        let edge = try XCTUnwrap(session.world.network.edges.dropFirst(3).first)
        let points = try XCTUnwrap(session.world.trackGeometry(of: edge.id)?.points)
        let a = points[points.count / 2], b = points[points.count / 2 + 1]
        func dot(_ x: Double, _ y: Double, _ dx: Double, _ dy: Double) -> RealTrainDot {
            RealTrainDot(id: "t", x: x, y: y, headingX: dx, headingY: dy, color: RealRailways.RGB(red: 0, green: 0, blue: 0))
        }
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        XCTAssertTrue(yield.hidesTrain(dot(Double(a.x), Double(a.y), dx, dy)))
        XCTAssertTrue(yield.hidesTrain(dot(Double(a.x), Double(a.y), -dx, -dy)), "either way")
        XCTAssertFalse(yield.hidesTrain(dot(Double(a.x), Double(a.y), -dy, dx)), "across it")
        XCTAssertFalse(yield.hidesTrain(dot(Double(a.x) + 500 * metre, Double(a.y) + 500 * metre, dx, dy)), "elsewhere")
        _ = frame
    }

    func testALineMostOfWhoseStationsAreThePlayersRunsNoRealTrains() throws {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        let railways = try BundledRealData.railways()
        let operations = try XCTUnwrap(railways.operations)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let system = try XCTUnwrap(operations.orderedSystems.first { $0.id == "trtc" })
        let bannan = try XCTUnwrap(system.lines.first { $0.name.contains("板南") }, "\(system.lines.map(\.name))")
        let region = WorldRegion(bounds: world.bounds)
        let onMap = bannan.stations.filter { station in
            let point = frame.worldPosition(latitude: station.latitude, longitude: station.longitude)
            return point.x >= region.minX && point.x <= region.maxX && point.y >= region.minY && point.y <= region.maxY
        }
        XCTAssertGreaterThan(onMap.count, 4)
        func yield(stations count: Int) throws -> RealRailwayYield {
            var built = world
            for station in onMap.prefix(count) {
                let point = frame.worldPosition(latitude: station.latitude, longitude: station.longitude)
                _ = try built.buildStation(named: station.name, at: PlanPoint(x: Int64(point.x.rounded()), y: Int64(point.y.rounded())))
            }
            return RealRailwayYield(railways: railways, operations: operations, world: built, frame: frame)
        }
        let key = "trtc:\(bannan.id)"
        XCTAssertTrue(try yield(stations: onMap.count / 2 + 1).quietLines.contains(key))
        XCTAssertFalse(try yield(stations: 2).quietLines.contains(key), "a couple of stations do not")
        XCTAssertTrue(try yield(stations: 0).quietLines.isEmpty)
    }
}
