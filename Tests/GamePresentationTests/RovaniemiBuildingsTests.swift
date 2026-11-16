import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Decision 799: Rovaniemi's buildings (`MapPacks/rovaniemi/buildings.pmtiles`,
/// made by `tools/rovaniemi-map/build_rovaniemi_buildings.py` in the format
/// of Taiwan's and Hong Kong's): OpenStreetMap's outlines and uses, its
/// storeys where tagged and a guess from the tagged ones elsewhere.
final class RovaniemiBuildingsTests: XCTestCase {
    /// Taiwan's footprints with Rovaniemi's, as the app reads them.
    static func tiles() throws -> FootprintTiles {
        let file = try XCTUnwrap(XCTUnwrap(HongKongRailwaysTests.pack(.rovaniemi)).buildingsFile, "the pack's buildings")
        return try FootprintTiles(data: Data(contentsOf: HongKongBuildingsTests.taiwan, options: .alwaysMapped),
                                  cities: [Data(contentsOf: file, options: .alwaysMapped)])
    }

    /// The buildings with their middles within `reach` metres of a place
    /// on Rovaniemi's map.
    static func buildings(latitude: Double, longitude: Double, reach: Double) throws -> [Map3DFootprints.Building] {
        let world = GameWorld.newOverseasGame(try RovaniemiRailwaysTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let place = frame.worldPosition(latitude: latitude, longitude: longitude)
        let region = WorldRegion(minX: place.x - reach * metre, minY: place.y - reach * metre, maxX: place.x + reach * metre, maxY: place.y + reach * metre)
        return Map3DFootprints(tiles: try tiles(), frame: frame, region: region).buildings.filter { building in
            guard let ring = building.rings.first, !ring.isEmpty else { return false }
            let x = ring.reduce(0) { $0 + $1.x } / Double(ring.count), y = ring.reduce(0) { $0 + $1.y } / Double(ring.count)
            return abs(x - place.x) <= reach * metre && abs(y - place.y) <= reach * metre
        }
    }

    /// The town centre (Lordi's Square): several hundred buildings, flats
    /// and shops of three storeys and more among them, none a tower (the
    /// town's tallest are eight storeys).
    func testTheCentreIsALowTown() throws {
        let found = try Self.buildings(latitude: 66.5028, longitude: 25.7285, reach: 800)
        XCTAssertGreaterThan(found.count, 300)
        let storeys = found.map(\.drawnStoreys).sorted()
        XCTAssertGreaterThan(found.filter { $0.drawnStoreys >= 3 }.count, 50)
        XCTAssertLessThanOrEqual(storeys.last ?? 0, 8)
        XCTAssertTrue(found.allSatisfy { $0.storeys >= 1 }, "every building has its storeys")
        XCTAssertTrue(found.contains { $0.storeysFrom == .tags })
    }

    /// The Santa Claus village on the Arctic Circle and Kemijärvi at the
    /// line's far end have their buildings; a village's are of one or two
    /// storeys (the tool's own fallback, Taiwan's two to four, is not
    /// used here).
    func testTheVillagesAreLow() throws {
        let village = try Self.buildings(latitude: 66.5436, longitude: 25.8473, reach: 400)
        XCTAssertGreaterThan(village.count, 20)
        let kemijarvi = try Self.buildings(latitude: 66.7131, longitude: 27.4306, reach: 800)
        XCTAssertGreaterThan(kemijarvi.count, 200)
        // Muurola, the village at the map's south-western end.
        let muurola = try Self.buildings(latitude: 66.3722, longitude: 25.3722, reach: 600)
        XCTAssertGreaterThan(muurola.count, 50)
        let storeys = muurola.map(\.drawnStoreys).sorted()
        XCTAssertLessThanOrEqual(storeys[storeys.count * 9 / 10], 2, "nine in ten of \(storeys.count)")
    }

    /// The 3D scene of a new game on Rovaniemi's map, looking at the town
    /// centre: streets only without the pack's buildings, a town with them.
    func testTheSceneAtTheCentreHasItsBuildings() throws {
        let ground = try RovaniemiRailwaysTests.ground()
        let world = GameWorld.newOverseasGame(ground)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let focus = frame.worldPosition(latitude: 66.5028, longitude: 25.7285)
        let baseMap = try BaseMapTiles(data: Data(contentsOf: HongKongBaseMapTests.taiwan, options: .alwaysMapped), cities: [XCTUnwrap(ground.baseMap, "the pack's base map")])
        let bare = Map3DScene(world: world, focus: focus, baseMap: baseMap,
                              footprints: try FootprintTiles(data: Data(contentsOf: HongKongBuildingsTests.taiwan, options: .alwaysMapped)))
        let scene = Map3DScene(world: world, focus: focus, baseMap: baseMap, footprints: try Self.tiles())
        XCTAssertGreaterThan(scene.triangleCount, bare.triangleCount + 10_000, "bare \(bare.triangleCount), with the buildings \(scene.triangleCount)")
    }

    /// The pack lists the file and where it comes from, and the credits
    /// name it once the map is open.
    func testThePackListsItsBuildings() throws {
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.rovaniemi))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: pack.file("pack", "json")) as? [String: Any])
        let files = try XCTUnwrap(manifest["files"] as? [String: Any])
        let entry = try XCTUnwrap(files["buildings.pmtiles"] as? [String: Any])
        let size = try XCTUnwrap(pack.buildingsFile.map { try Data(contentsOf: $0).count })
        XCTAssertEqual(entry["bytes"] as? Int, size)
        XCTAssertLessThan(size, 1_500_000)
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let section = try XCTUnwrap(DataSourceCredits.sections(in: language, overseas: [.rovaniemi]).first { $0.id == "rovaniemiRailways" })
            XCTAssertTrue(section.credits.contains { $0.id == "rovaniemiBuildings" && $0.notice.contains("ODbL") })
        }
    }
}
