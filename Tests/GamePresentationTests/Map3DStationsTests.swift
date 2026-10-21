import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 321: the 3D map's stations from the station kit.
final class Map3DStationsTests: XCTestCase {
    private static let station = StationID(rawValue: 7)

    /// A builder with one platform 120 m long along x, on the right (+z)
    /// of its track at z 0, and the other `tracks` (their z), each laid
    /// as `structure` carries it.
    private func builder(_ structure: TrackStructure = .surface, tracks: [Float] = []) -> Map3DScene.Builder {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                         world: GameWorld.newGame())
        func line(_ z: Float) -> [Map3DPoint] { stride(from: Float(-60), through: 60, by: 2).map { Map3DPoint($0, Map3DScene.railLift, z) } }
        builder.laidPlatforms = [Map3DScene.Builder.LaidPlatform(station: Self.station, line: line(0), offset: 3.5, width: 3.2, structure: structure)]
        builder.trackLines = ([0] + tracks).map { (line($0), TrackSectionKind.surface) }
        return builder
    }

    private func stations(_ builder: inout Map3DScene.Builder) -> Set<Map3DScene.ChunkKey> {
        builder.addStations(GameWorld.newGame().railwaySnapshot(), frame: nil)
    }

    /// The far box's walls stand on the ground; the canopy is far above.
    private func house(_ builder: Map3DScene.Builder) -> [Map3DVertex] {
        builder.farMeshes.values.flatMap(\.vertices).filter { $0.y < 0.5 }
    }

    func testAStationsBuildingStandsBesideItsPlatformAwayFromOtherTrack() {
        // A through track on the left: the building on the platform's
        // side, a metre past its edge (3.5 + 1.6), its back to it.
        var b = builder(tracks: [-5])
        let cells = stations(&b)
        let walls = house(b)
        XCTAssertFalse(walls.isEmpty)
        XCTAssertEqual(walls.map(\.z).min() ?? 0, 6.1, accuracy: 0.01)
        XCTAssertFalse(cells.isEmpty, "the building's cells become a plaza")
        // Close up the kit's building there too, with its shadow.
        let near = b.nearMeshes.values.flatMap(\.vertices).filter { $0.color != Map3DPalette.canopy && $0.y < 1 }
        XCTAssertGreaterThanOrEqual(near.map(\.z).min() ?? 0, 6.1 - 0.01)
        XCTAssertFalse(b.shadows.isEmpty)
    }

    func testABuildingStandsPastAThroughTrackBesideThePlatformNotFacingBareTrack() {
        // Nothing on the left but the platform's own track; on the right
        // a through track past the platform: the building opens onto the
        // platform, past that track (8 + 2.5 + 1).
        var b = builder(tracks: [8])
        _ = stations(&b)
        XCTAssertEqual(house(b).map(\.z).min() ?? 0, 11.5, accuracy: 0.01)
    }

    func testAViaductStationHasStairEntrancesAndNoBuilding() {
        var b = builder(.elevated)
        XCTAssertTrue(stations(&b).isEmpty)
        XCTAssertTrue(house(b).isEmpty)
        // Two stair heads on the ground, either side of the viaduct.
        let stairs = b.nearMeshes.values.flatMap(\.vertices).filter { $0.y < 0.5 }
        XCTAssertLessThan(stairs.map(\.z).min() ?? 0, -5)
        XCTAssertGreaterThan(stairs.map(\.z).max() ?? 0, 5)
    }

    func testTheCanopyStandsOnThePlatformOverItsMiddle() {
        var b = builder(tracks: [-5])
        _ = stations(&b)
        let canopy = b.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.canopy && $0.z < 6 }
        // The platform's top 1.15 m over the rails, the roof 3.2 m over
        // it, rising 0.6 m in the middle, 0.22 m thick.
        let top = Map3DScene.railLift + Map3DScene.Builder.platformHeight + 3.2
        XCTAssertEqual(canopy.map(\.y).min() ?? 0, top - 0.22, accuracy: 0.01)
        XCTAssertEqual(canopy.map(\.y).max() ?? 0, top + 0.6, accuracy: 0.01)
        // Over the middle three fifths (36 m each way), across the platform.
        XCTAssertEqual(canopy.map(\.x).min() ?? 0, -36, accuracy: 0.5)
        XCTAssertEqual(canopy.map(\.x).max() ?? 0, 36, accuracy: 0.5)
        XCTAssertEqual(canopy.map(\.z).min() ?? 0, 3.5 - 1.75, accuracy: 0.01)
        XCTAssertEqual(canopy.map(\.z).max() ?? 0, 3.5 + 1.75, accuracy: 0.01)
        // Far off the flat canopy, not the kit's.
        let far = b.farMeshes.values.flatMap(\.vertices)
        XCTAssertTrue(far.contains { $0.color == Map3DPalette.canopy })
    }

    func testFarOffAStationIsAFewBoxes() {
        var b = builder(tracks: [-5])
        _ = stations(&b)
        let near = b.nearMeshes.values.map(\.indices.count).reduce(0, +), far = b.farMeshes.values.map(\.indices.count).reduce(0, +)
        XCTAssertGreaterThan(near, 0)
        XCTAssertLessThan(far * 4, near, "far \(far / 3), near \(near / 3) triangles")
    }

    func testTheSameStationIsBuiltTheSameEveryTime() {
        var a = builder(tracks: [-5]), b = builder(tracks: [-5])
        XCTAssertEqual(stations(&a), stations(&b))
        XCTAssertEqual(a.nearMeshes.keys.sorted { ($0.row, $0.column) < ($1.row, $1.column) },
                       b.nearMeshes.keys.sorted { ($0.row, $0.column) < ($1.row, $1.column) })
        for (key, mesh) in a.nearMeshes {
            XCTAssertEqual(mesh.vertices, b.nearMeshes[key]?.vertices)
            XCTAssertEqual(mesh.indices, b.nearMeshes[key]?.indices)
        }
    }

    // MARK: - Recipes

    func testAStationOfTheGameByARealStationIsBuiltAsIt() throws {
        let taipei = try XCTUnwrap(RealWorldFrame(world: GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))))
        let main = taipei.worldPosition(latitude: 25.048042, longitude: 121.517027), metre = Double(WorldCoordinate.unitsPerMetre)
        let near = Map3DStationKit.recipe(for: Self.station, at: (main.x + 200 * metre, main.y), layout: .surface(platforms: 4, longest: 300), frame: taipei)
        XCTAssertEqual(near.name, "臺北")
        XCTAssertEqual(near.profile, .taipei)
        let away = Map3DStationKit.recipe(for: Self.station, at: (main.x + 2_000 * metre, main.y + 2_000 * metre),
                                          layout: .surface(platforms: 4, longest: 300), frame: taipei)
        XCTAssertEqual(away.profile, .regional)
        XCTAssertEqual(away.tier, 0)
        XCTAssertEqual(away.id, "game-7")

        // 美麗島's glass entrances only over a tunnel.
        let kaohsiung = try XCTUnwrap(RealWorldFrame(world: GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.6314, longitudeDegrees: 120.3020)))))
        let formosa = kaohsiung.worldPosition(latitude: 22.631365, longitude: 120.301992)
        XCTAssertEqual(Map3DStationKit.recipe(for: Self.station, at: formosa, layout: .underground, frame: kaohsiung).profile, .formosa)
        XCTAssertNotEqual(Map3DStationKit.recipe(for: Self.station, at: formosa, layout: .surface(platforms: 2, longest: 150), frame: kaohsiung).profile, .formosa)
    }

    func testAGeneralStationsTypeFollowsItsPlatforms() {
        func recipe(_ layout: Map3DStationKit.Layout) -> Map3DStationKit.Station {
            Map3DStationKit.recipe(for: Self.station, at: (0, 0), layout: layout, frame: nil)
        }
        XCTAssertEqual(recipe(.surface(platforms: 1, longest: 60)).profile, .halt)
        XCTAssertEqual(recipe(.surface(platforms: 1, longest: 160)).profile, .regional)
        XCTAssertEqual(recipe(.surface(platforms: 2, longest: 160)).tier, 2)
        XCTAssertEqual(recipe(.elevated).profile, .elevated)
        XCTAssertEqual(recipe(.underground).profile, .underground)
        XCTAssertFalse(Map3DStationKit.hasHouse(.underground))
        XCTAssertFalse(Map3DStationKit.hasHouse(.elevated))
        XCTAssertTrue(Map3DStationKit.hasHouse(.halt))
        XCTAssertEqual(recipe(.elevated).seed, recipe(.elevated).seed)
        XCTAssertNotEqual(recipe(.elevated).seed, Map3DStationKit.recipe(for: StationID(rawValue: 8), at: (0, 0), layout: .elevated, frame: nil).seed)
    }

    /// The demo's stations have the kit's canopies.
    func testTheDemosStationsAreBuilt() {
        let scene = Map3DScene(world: DemoWorld.make(in: .english))
        XCTAssertTrue(scene.chunks.contains { $0.mesh.vertices.contains { $0.color == Map3DPalette.canopy } })
    }
}
