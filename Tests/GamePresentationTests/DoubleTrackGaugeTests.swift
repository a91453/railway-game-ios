import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// REVIEW-L35 P2-1 (decision 970): with the network tool's gauge on
/// automatic, a double track laid from high-speed track, a traced one of a
/// standard-gauge line, and the select tool's "make double" on high-speed
/// track lay the second track and its crossovers at the first track's
/// gauge, not at the default 1,067 mm.
@MainActor
final class DoubleTrackGaugeTests: XCTestCase {
    private let metre = WorldCoordinate.unitsPerMetre

    /// A 1,435 mm high-speed track along y 8,192 from x 1,024 to 5,120.
    private func highSpeedTrack(width: Int64 = 40_960) throws -> (world: GameWorld, edge: TrackEdgeID) {
        var world = try makeWorld(width: width, height: 16_384, balance: Money(100_000_000), speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 5_120, y: 8_192))
        let edge = try world.buildTrackEdge(from: west, to: east, gauge: .shinkansen)
        return (world, edge)
    }

    private func gauges(_ world: GameWorld) -> [String] {
        world.network.edges.map { "\($0.id) \($0.gauge.name(in: .english))" }
    }

    func testADoubleTrackFromHighSpeedTrackIsHighSpeedOnAutomatic() throws {
        let session = GameSession(world: try highSpeedTrack().world, language: .english)
        session.selectTool(.network)
        XCTAssertNil(session.networkGauge, "automatic")
        session.networkBuildsDouble = true
        session.networkDoubleSide = .left
        session.tapNetwork(at: PlanPoint(x: 5_120, y: 8_192), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 8_192), reach: 16)
        let draft = try XCTUnwrap(session.networkDraftPreview)
        XCTAssertNil(draft.preview.problem, draft.preview.problem ?? "")
        XCTAssertEqual(draft.preview.crossovers.count, 1, "a crossover joins the second track to the high-speed track")
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let world = session.world
        XCTAssertGreaterThan(world.network.edges.count, 3, "the first track, the second and a crossover")
        XCTAssertTrue(world.network.edges.allSatisfy { $0.gauge == .shinkansen }, "\(gauges(world))")
        guard case .command(.buildDoubleTrack(_, let parallel, _))? = session.commandLog.entries.last?.action else {
            return XCTFail("one double-track command")
        }
        XCTAssertEqual(parallel.gauge, .shinkansen, "written into the command")
    }

    func testAChosenGaugeStillLaysBothTracks() throws {
        let session = GameSession(world: try highSpeedTrack().world, language: .english)
        session.selectTool(.network)
        session.chooseNetworkGauge(.cape)
        session.networkBuildsDouble = true
        session.networkDoubleSide = .left
        session.tapNetwork(at: PlanPoint(x: 12_288, y: 4_096), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 24_576, y: 4_096), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let laid = session.world.network.edges.filter { $0.gauge != .shinkansen }
        XCTAssertEqual(laid.count, 2)
        XCTAssertTrue(laid.allSatisfy { $0.gauge == .cape })
    }

    func testOnTrackJoiningNothingBothTracksAreTheDefault() throws {
        let session = GameSession(world: try makeWorld(width: 40_960, height: 16_384, balance: Money(100_000_000), speed: .paused), language: .english)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: 4_096, y: 8_192), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, 2)
        XCTAssertTrue(session.world.network.edges.allSatisfy { $0.gauge == .default })
    }

    func testMakingHighSpeedTrackDoubleKeepsItsGauge() throws {
        var (world, _) = try highSpeedTrack(width: 65_536)
        // A longer high-speed track on to x 33,024, so there is room for the
        // crossovers.
        let east = try XCTUnwrap(world.network.nodes.first { $0.position.plan == PlanPoint(x: 5_120, y: 8_192) }).id
        let far = try world.buildTrackNode(at: WorldCoordinate(x: 33_024, y: 8_192))
        let picked = try world.buildTrackEdge(from: east, to: far, gauge: .shinkansen)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.select)
        session.tapMap(at: PlanPoint(x: 20_480, y: 8_192), reach: 16)
        XCTAssertEqual(session.selectedTrackEdge, picked)
        session.trackUpgradeSide = .left
        session.beginTrackUpgrade(.doubleTrack)
        let preview = try XCTUnwrap(session.trackUpgradePreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        session.buildTrackUpgrade()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let built = session.world
        XCTAssertGreaterThan(built.network.edges.count, 4)
        XCTAssertTrue(built.network.edges.allSatisfy { $0.gauge == .shinkansen }, "\(gauges(built))")
    }

    /// A made-up 2 km line of the Taipei metro (1,435 mm) at 25° N 121.5° E.
    private static func fakeMetro() throws -> RealRailways {
        let lines = #"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"sys":"mrt","name":"測試線","sortKey":0,"lineKey":"mrt|BL"},"geometry":{"type":"LineString","coordinates":[[121.490,25.000],[121.500,25.000],[121.510,25.002]]}}]}"#
        return try RealRailways(
            lines: Data(lines.utf8), stations: Data(#"{"type":"FeatureCollection","features":[]}"#.utf8), names: Data(#"{"systems":{}}"#.utf8)
        )
    }

    func testATracedDoubleTrackOfAStandardGaugeLineIsStandardGauge() throws {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0, longitudeDegrees: 121.5)))
        let session = GameSession(world: world, language: .english)
        session.railways = try Self.fakeMetro()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = true
        let west = try BundledRealData.point(RealRailways.Coordinate(latitude: 25.0, longitude: 121.4905), in: world)
        let east = try BundledRealData.point(RealRailways.Coordinate(latitude: 25.0019, longitude: 121.5095), in: world)
        session.tapNetwork(at: west, reach: 24 * metre)
        session.tapNetwork(at: east, reach: 24 * metre)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let built = session.world
        let laid = Set(built.network.edges.map(\.gauge))
        XCTAssertEqual(laid.count, 1, "both tracks at one gauge: \(gauges(built))")
    }
}
