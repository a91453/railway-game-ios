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
    private func builder(_ structure: TrackStructure = .surface, tracks: [Float] = [], world: GameWorld = .newGame(),
                         station: StationID = station) -> Map3DScene.Builder {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                         world: world)
        func line(_ z: Float) -> [Map3DPoint] { stride(from: Float(-60), through: 60, by: 2).map { Map3DPoint($0, Map3DScene.railLift, z) } }
        builder.laidPlatforms = [Map3DScene.Builder.LaidPlatform(station: station, line: line(0), offset: 3.5, width: 3.2, structure: structure)]
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

    // MARK: - Expanded stations (decision 506, later)

    /// A new game's first line, its first station expanded to `level`
    /// (written into the saved world, as GameCore keeps the field to its
    /// own command), and that station.
    private func expandedWorld(_ level: StationExpansion?) throws -> (GameWorld, StationID) {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let id = try XCTUnwrap(world.stations.first { !$0.isDepot }?.id)
        guard let level else { return (world, id) }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var stations = try XCTUnwrap(json["stations"] as? [[String: Any]])
        let index = try XCTUnwrap(stations.firstIndex { ($0["id"] as? Int) == id.rawValue })
        stations[index]["expansion"] = level.rawValue
        json["stations"] = stations
        let expanded = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(expanded.station(id: id)?.expansion, level)
        return (expanded, id)
    }

    /// Each level's builder after its stations are laid.
    private func expandedBuilders(_ structure: TrackStructure = .surface) throws -> [Map3DScene.Builder] {
        try [nil, StationExpansion.concourse, .hall].map { level in
            let (world, id) = try expandedWorld(level)
            var b = builder(structure, tracks: [-5], world: world, station: id)
            _ = stations(&b)
            return b
        }
    }

    func testAnExpandedStationsCanopyCoversMoreOfThePlatform() throws {
        // The 120 m platform: three fifths, four fifths, then all but
        // three metres at each end.
        let reaches = try expandedBuilders().map { b in
            b.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Map3DPalette.canopy && $0.z < 6 }.map(\.x).max() ?? 0
        }
        XCTAssertEqual(reaches[0], 36, accuracy: 0.5)
        XCTAssertEqual(reaches[1], 48, accuracy: 0.5)
        XCTAssertEqual(reaches[2], 57, accuracy: 0.5)
    }

    func testAnExpandedStationsBuildingGrowsAlongItsPlatforms() throws {
        // The building's recipe alone: along the platforms (z) and up.
        for station in [
            Map3DStationKit.recipe(for: Self.station, at: (0, 0), layout: .surface(platforms: 2, longest: 160), frame: nil),
            Map3DStationKit.recipe(for: Self.station, at: (0, 0), layout: .surface(platforms: 1, longest: 60), frame: nil),
        ] + Map3DStationKit.stations.filter({ [.taipei, .hsinchu, .banqiao].contains($0.profile) }).prefix(3) {
            let built = [nil, StationExpansion.concourse, .hall].map { level -> (bounds: (min: Map3DPoint, max: Map3DPoint), triangles: Int) in
                var kit = StationKitBuilder()
                kit.house(station, expansion: level)
                return (kit.mesh.bounds!, kit.mesh.indices.count / 3)
            }
            let lengths = built.map { $0.bounds.max.z - $0.bounds.min.z }
            XCTAssertGreaterThanOrEqual(lengths[1], lengths[0] + 20, "\(station.profile): a concourse wing at each end")
            XCTAssertEqual(lengths[2], lengths[1], accuracy: 1, "\(station.profile): the hall builds up and out front")
            XCTAssertGreaterThan(built[2].bounds.max.x, built[1].bounds.max.x - 0.01, "\(station.profile): its front canopy")
            XCTAssertLessThan(built[0].triangles, built[1].triangles)
            XCTAssertLessThan(built[1].triangles, built[2].triangles)
            // Its back stays where the platforms are.
            XCTAssertEqual(built[1].bounds.min.x, built[0].bounds.min.x, accuracy: 0.01)
        }
        // In the scene too: more drawn close up.
        let near = try expandedBuilders().map { $0.nearMeshes.values.map(\.indices.count).reduce(0, +) }
        XCTAssertLessThan(near[0], near[1])
        XCTAssertLessThan(near[1], near[2])
    }

    func testAnExpandedViaductStationHasMoreStairs() throws {
        let reaches = try expandedBuilders(.elevated).map { b in
            b.nearMeshes.values.flatMap(\.vertices).filter { $0.y < 0.5 }.map { abs($0.x) }.max() ?? 0
        }
        XCTAssertLessThan(reaches[0], 20, "a stair each way, 12 m from the middle")
        XCTAssertGreaterThan(reaches[1], 30, "and a pair 36 m out")
        XCTAssertGreaterThan(reaches[2], 55, "and a pair 60 m out")
    }

    func testTheSceneIsBuiltAgainWhenAStationIsExpanded() throws {
        let signatures = try [nil, StationExpansion.concourse, .hall].map { Map3DStationKit.expansionSignature(of: try expandedWorld($0).0) }
        XCTAssertEqual(signatures, [0, 1, 2])
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
