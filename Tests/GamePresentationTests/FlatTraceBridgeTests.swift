import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 974: on flat ground (decision 198), a trace along the real
/// railway still crosses the map's water on a bridge, and is level
/// everywhere else.
@MainActor
final class FlatTraceBridgeTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    private static let water = Result {
        try WaterGrid(data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_water.json")))
    }

    /// Yilan to Erjie on the Yilan Line, over the Lanyang River, traced
    /// on a flat real-world game at Yilan with the app's water, one track,
    /// with the network tool's `structure`; the world it built.
    private func lanyang(structure: TrackStructure = .automatic) throws -> GameWorld {
        let yilan = try BundledRealData.station("宜蘭", in: "tra_sched")
        let anchor = try XCTUnwrap(yilan.anchor)
        let bounds = GameWorld.newGameBounds
        let water = try Self.water.get().cells(frame: RealWorldFrame(anchor: anchor, bounds: bounds), bounds: bounds)
        let world = GameWorld.newGame(anchor: anchor, water: water)
        XCTAssertFalse(world.ground.isMapped, "flat ground")
        let session = GameSession(world: world, language: .english)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = false
        session.networkStructure = structure
        let erjie = try BundledRealData.station("二結", in: "tra_sched")
        session.tapNetwork(at: try BundledRealData.point(yilan.coordinate, in: world), reach: reach)
        session.tapNetwork(at: try BundledRealData.point(erjie.coordinate, in: world), reach: reach)
        XCTAssertNil(try XCTUnwrap(session.networkPreview).problem)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        return session.world
    }

    /// Each point along the built track every 16 m: its height, whether
    /// it is over water, and what carries it.
    private func samples(of world: GameWorld) throws -> [(z: Int64, wet: Bool, kind: TrackSectionKind)] {
        var found: [(z: Int64, wet: Bool, kind: TrackSectionKind)] = []
        for edge in world.network.edges {
            let geometry = try XCTUnwrap(world.trackGeometry(of: edge.id))
            for span in edge.sectionSpans where span.end > span.start {
                for distance in stride(from: span.start, to: span.end, by: Int(ConstructionCosts.trackPricingLength)).map({ Int64($0) }) {
                    let point = geometry.location(at: distance).position
                    let wet = world.terrain.isWater(row: Int(point.y / Land.cellLength), column: Int(point.x / Land.cellLength))
                    found.append((point.z, wet, span.kind))
                }
            }
        }
        return found
    }

    /// The real Yilan Line crosses the Lanyang River on a bridge of 3.78
    /// km (`rail_structures.json`, OSM way 371345105), of which the map's
    /// water marks only the channel: the track is on a bridge along the
    /// whole of it, up to it on a short embankment, and level beyond.
    func testATraceOverARiverOnFlatGroundIsABridge() throws {
        let world = try lanyang()
        let samples = try samples(of: world)
        let wet = samples.filter(\.wet)
        XCTAssertFalse(wet.isEmpty, "the map's water crosses the line")
        // Over the water: on a bridge, at least 4 m over it.
        for sample in wet {
            XCTAssertEqual(sample.kind, .bridge)
            XCTAssertGreaterThanOrEqual(sample.z, TrackSectionRules.waterClearance)
        }
        // The real bridge's length, and little more.
        let bridged = Double(samples.filter { $0.kind == .bridge }.count) * 16
        XCTAssertEqual(bridged, 3_781, accuracy: 600)
        XCTAssertTrue(samples.filter { $0.kind == .bridge }.allSatisfy { $0.z > 0 })
        // No tunnel or viaduct, nothing under the ground, and level on it
        // beyond the bridge's approaches.
        XCTAssertTrue(samples.allSatisfy { $0.kind != .tunnel && $0.kind != .viaduct && $0.z >= 0 })
        XCTAssertTrue(samples.filter { $0.kind == .surface }.allSatisfy { $0.z <= TrackSectionRules.level })
        XCTAssertLessThan(Double(samples.filter { $0.kind == .embankment }.count) * 16, 400, "short approaches")
        XCTAssertGreaterThan(samples.filter { $0.z == 0 }.count, 0)
        // Both ends where the tool put them, on the ground.
        let ends = world.network.nodes.filter { $0.ends.count == 1 }
        XCTAssertEqual(ends.count, 2)
        XCTAssertTrue(ends.allSatisfy { $0.position.z == 0 })
    }

    /// The player's own structure wins, level over the water as before.
    func testAStructureThePlayerChoseStaysLevel() throws {
        let world = try lanyang(structure: .surface)
        let samples = try samples(of: world)
        XCTAssertTrue(samples.contains(where: \.wet))
        XCTAssertTrue(samples.allSatisfy { $0.z == 0 && $0.kind == .surface })
    }
}
