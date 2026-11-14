import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Decision 712: Hong Kong's 3D map had no buildings (screenshot run
/// 43388165195): the 3D map raises them from the footprint tiles, and
/// Taiwan's file has none of Hong Kong. The pack has its own
/// (`MapPacks/hongkong/buildings.pmtiles`, made by
/// `tools/hk-map/build_hk_buildings.py` in the format of Taiwan's), read
/// where Taiwan's has no tile. Decision 729: its outlines and heights are
/// the Lands Department's, its uses OpenStreetMap's.
final class HongKongBuildingsTests: XCTestCase {
    static let taiwan = Map3DRealTrainsTests.resources.appendingPathComponent("BaseMap/taiwan_buildings.pmtiles")

    /// Taiwan's footprints with Hong Kong's, as the app reads them.
    static func tiles() throws -> FootprintTiles {
        let file = try XCTUnwrap(XCTUnwrap(HongKongRailwaysTests.pack(.hongKong)).buildingsFile, "the pack's buildings")
        return try FootprintTiles(data: Data(contentsOf: taiwan, options: .alwaysMapped), cities: [Data(contentsOf: file, options: .alwaysMapped)])
    }

    /// The buildings `tiles` has with their middles within `reach` metres
    /// of a place on Hong Kong's map.
    static func buildings(_ tiles: FootprintTiles, latitude: Double, longitude: Double, reach: Double) throws -> [Map3DFootprints.Building] {
        let world = GameWorld.newOverseasGame(try HongKongBaseMapTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let place = frame.worldPosition(latitude: latitude, longitude: longitude)
        let region = WorldRegion(minX: place.x - reach * metre, minY: place.y - reach * metre, maxX: place.x + reach * metre, maxY: place.y + reach * metre)
        return Map3DFootprints(tiles: tiles, frame: frame, region: region).buildings.filter { building in
            guard let ring = building.rings.first, !ring.isEmpty else { return false }
            let x = ring.reduce(0) { $0 + $1.x } / Double(ring.count), y = ring.reduce(0) { $0 + $1.y } / Double(ring.count)
            return abs(x - place.x) <= reach * metre && abs(y - place.y) <= reach * metre
        }
    }

    /// What the bare streets came from: Taiwan's file alone has no
    /// building at Central.
    func testTaiwanFootprintsHaveNothingOfHongKong() throws {
        let taiwan = try FootprintTiles(data: Data(contentsOf: Self.taiwan, options: .alwaysMapped))
        XCTAssertTrue(try Self.buildings(taiwan, latitude: 22.2819, longitude: 114.1582, reach: 800).isEmpty)
    }

    /// Central is towers: over two thousand buildings within 800 m, a
    /// quarter of them fourteen storeys and more (the median is 7: the
    /// old tenements of Sheung Wan and the Mid-Levels, and the covered
    /// walkways and kiosks, are counted too), Two International Finance
    /// Centre (412 m, drawn 126 storeys of 3.2 m) the tallest, and the
    /// heights of 95 % and more measured (decision 729).
    func testCentralIsTowers() throws {
        let found = try Self.buildings(Self.tiles(), latitude: 22.2819, longitude: 114.1582, reach: 800)
        XCTAssertGreaterThan(found.count, 2_000)
        let storeys = found.map(\.drawnStoreys).sorted()
        XCTAssertGreaterThanOrEqual(storeys[storeys.count * 3 / 4], 14, "the upper quartile of \(storeys.count), the median \(storeys[storeys.count / 2])")
        XCTAssertTrue(found.contains { $0.storeys == 126 && $0.storeysFrom == .landsd }, "the tallest is \(storeys.last ?? 0)")
        XCTAssertEqual(storeys.last, 126)
        let measured = found.filter { $0.storeysFrom == .landsd }.count
        XCTAssertGreaterThanOrEqual(Double(measured) / Double(found.count), 0.95, "\(measured) of \(found.count) measured")
        XCTAssertTrue(found.allSatisfy { $0.storeys >= 1 }, "every building has its storeys")
    }

    /// The towers of 150 m and more (47 storeys of 3.2 m) round Central and
    /// Kowloon Station, as many as the Lands Department's heights give
    /// (`hk_buildings.json`'s run of the tool; OpenStreetMap's tags had
    /// 11 round Central).
    func testTheTallTowersAreThere() throws {
        let central = try Self.buildings(Self.tiles(), latitude: 22.2819, longitude: 114.1582, reach: 600)
        XCTAssertEqual(central.filter { $0.storeys >= 47 }.count, 26)
        let kowloon = try Self.buildings(Self.tiles(), latitude: 22.3034, longitude: 114.1602, reach: 600)
        XCTAssertEqual(kowloon.filter { $0.storeys >= 47 }.count, 16)
    }

    /// Kowloon Station's tower, the International Commerce Centre, is the
    /// city's tallest: 490 m above Principal Datum on its podium's ground
    /// 29.4 m lower than its own base, 485 m drawn as 152 storeys (it is
    /// 484 m); a slip in an OpenStreetMap tag (123 levels on an 18 m
    /// building) does not make a taller one anywhere near.
    func testTheTallestIsAtKowloonStation() throws {
        let found = try Self.buildings(Self.tiles(), latitude: 22.3034, longitude: 114.1602, reach: 400)
        XCTAssertEqual(found.map(\.storeys).max(), 152)
        XCTAssertTrue(found.contains { $0.storeys == 152 && $0.storeysFrom == .landsd })
        let slip = try Self.buildings(Self.tiles(), latitude: 22.3311, longitude: 114.1535, reach: 150)
        XCTAssertLessThan(slip.map(\.storeys).max() ?? 0, 60)
    }

    /// A New Territories village is houses of three storeys: no tower
    /// among them.
    func testAVillageIsLow() throws {
        // Kam Tin's villages, west of Kam Sheung Road Station.
        let found = try Self.buildings(Self.tiles(), latitude: 22.4420, longitude: 114.0600, reach: 500)
        XCTAssertGreaterThan(found.count, 200)
        let storeys = found.map(\.drawnStoreys).sorted()
        XCTAssertLessThanOrEqual(storeys[storeys.count * 9 / 10], 4, "nine in ten of \(storeys.count)")
    }

    /// Taiwan's buildings are read as before: the same ones round Taipei
    /// Main Station with Hong Kong's file and without.
    func testTaiwanIsReadAsBefore() throws {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let region = WorldRegion(bounds: world.bounds)
        let alone = Map3DFootprints(tiles: try FootprintTiles(data: Data(contentsOf: Self.taiwan, options: .alwaysMapped)), frame: frame, region: region)
        let both = Map3DFootprints(tiles: try Self.tiles(), frame: frame, region: region)
        XCTAssertGreaterThan(alone.buildings.count, 1_000)
        XCTAssertEqual(alone.buildings.count, both.buildings.count)
        XCTAssertEqual(alone.buildings.map(\.storeys), both.buildings.map(\.storeys))
    }

    /// The 3D scene of a new game on Hong Kong's map, looking at Central:
    /// streets only without the pack's buildings, a city with them.
    func testTheSceneAtCentralHasItsBuildings() throws {
        let world = GameWorld.newOverseasGame(try HongKongBaseMapTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let focus = frame.worldPosition(latitude: 22.2819, longitude: 114.1582)
        let baseMap = try HongKongBaseMapTests.tiles()
        let bare = Map3DScene(world: world, focus: focus, baseMap: baseMap,
                              footprints: try FootprintTiles(data: Data(contentsOf: Self.taiwan, options: .alwaysMapped)))
        let scene = Map3DScene(world: world, focus: focus, baseMap: baseMap, footprints: try Self.tiles())
        XCTAssertGreaterThan(scene.triangleCount, bare.triangleCount + 100_000, "bare \(bare.triangleCount), with the buildings \(scene.triangleCount)")
    }

    /// The pack lists the file and where it comes from.
    func testThePackListsItsBuildings() throws {
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.hongKong))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: pack.file("pack", "json")) as? [String: Any])
        let files = try XCTUnwrap(manifest["files"] as? [String: Any])
        let entry = try XCTUnwrap(files["buildings.pmtiles"] as? [String: Any])
        let size = try XCTUnwrap(pack.buildingsFile.map { try Data(contentsOf: $0).count })
        XCTAssertEqual(entry["bytes"] as? Int, size)
        XCTAssertLessThan(size, 6_000_000)
    }
}
