import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Decision 712: Hong Kong's 3D map was bare ground (screenshot run
/// 43369272845): the 3D map lays its ground from the base map's tiles, and
/// Taiwan's file has none of Hong Kong. The pack has its own
/// (`MapPacks/hongkong/basemap.pmtiles`, `tools/hk-map/build_hk_basemap.py`),
/// read where Taiwan's has no tile.
final class HongKongBaseMapTests: XCTestCase {
    static let taiwan = Map3DRealTrainsTests.resources.appendingPathComponent("BaseMap/taiwan.pmtiles")

    static func ground() throws -> OverseasGround {
        try OverseasGround(city: .hongKong, pack: XCTUnwrap(HongKongRailwaysTests.pack(.hongKong)))
    }

    /// Taiwan's tiles with Hong Kong's, as the app reads them.
    static func tiles() throws -> BaseMapTiles {
        try BaseMapTiles(data: Data(contentsOf: taiwan, options: .alwaysMapped), cities: [XCTUnwrap(ground().baseMap, "the pack's base map")])
    }

    /// The base map `tiles` has within `reach` metres of a place on Hong
    /// Kong's map, and the place in its metres.
    static func baseMap(_ tiles: BaseMapTiles, latitude: Double, longitude: Double, reach: Double = 1_200) throws -> (map: Map3DBaseMap, at: Map3DBaseMap.Point) {
        let world = GameWorld.newOverseasGame(try ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let place = frame.worldPosition(latitude: latitude, longitude: longitude)
        let region = WorldRegion(minX: place.x - reach * metre, minY: place.y - reach * metre, maxX: place.x + reach * metre, maxY: place.y + reach * metre)
        let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: frame.middleX, originY: frame.middleY)
        return (map, Map3DBaseMap.Point(x: (place.x - frame.middleX) / metre, z: (place.y - frame.middleY) / metre))
    }

    static func holds(_ ring: [Map3DBaseMap.Point], _ point: Map3DBaseMap.Point) -> Bool {
        var inside = false
        for index in ring.indices {
            let a = ring[index], b = ring[(index + 1) % ring.count]
            if (a.z > point.z) != (b.z > point.z), point.x < (b.x - a.x) * (point.z - a.z) / (b.z - a.z) + a.x { inside.toggle() }
        }
        return inside
    }

    /// Whether the place is on the base map's water: in an area's outer
    /// ring and in none of its holes.
    static func isWater(_ found: (map: Map3DBaseMap, at: Map3DBaseMap.Point)) -> Bool {
        found.map.areas.contains { area in
            area.cover == .water && area.rings.first.map { holds($0, found.at) } == true && !area.rings.dropFirst().contains { holds($0, found.at) }
        }
    }

    /// What the bare 3D map came from: Taiwan's file alone has no ground
    /// at Central.
    func testTaiwanTilesHaveNothingOfHongKong() throws {
        let taiwan = try BaseMapTiles(data: Data(contentsOf: Self.taiwan, options: .alwaysMapped))
        let found = try Self.baseMap(taiwan, latitude: 22.2819, longitude: 114.1582)
        XCTAssertTrue(found.map.areas.isEmpty)
        XCTAssertTrue(found.map.roads.isEmpty)
    }

    /// The pack's ground brings its base map, and the 3D map's ground at
    /// Central has roads, the harbour and a park or a wood.
    func testThePackBaseMapLaysCentralsGround() throws {
        let found = try Self.baseMap(Self.tiles(), latitude: 22.2819, longitude: 114.1582)
        XCTAssertGreaterThan(found.map.roads.count, 100)
        XCTAssertTrue(found.map.roads.contains { $0.kind == .primary || $0.kind == .trunk })
        XCTAssertTrue(found.map.areas.contains { $0.cover == .water })
        XCTAssertTrue(found.map.areas.contains { $0.cover == .park || $0.cover == .wood })
    }

    /// The sea is sea and the land is land: the harbour, the open sea and
    /// a reservoir are water; the island, Kowloon, the New Territories
    /// (whose shore the extract cuts open, closed round the north by the
    /// tool), Lantau and the airport's island are not.
    func testTheSeaAndTheLand() throws {
        let tiles = try Self.tiles()
        let water: [(String, Double, Double)] = [
            ("Victoria Harbour", 22.2905, 114.1700), ("East Lamma Channel", 22.2300, 114.1400), ("Tolo Harbour", 22.4400, 114.2200),
            ("Deep Bay", 22.4700, 113.9500), ("Plover Cove Reservoir", 22.4700, 114.2600),
        ]
        let land: [(String, Double, Double)] = [
            ("Central", 22.2819, 114.1582), ("Mong Kok", 22.3193, 114.1694), ("Sha Tin", 22.3830, 114.1880), ("Yuen Long", 22.4450, 114.0220),
            ("Sheung Shui", 22.5010, 114.1280), ("Tai Mo Shan", 22.4100, 114.1240), ("Tung Chung", 22.2890, 113.9410),
            ("the airport", 22.3080, 113.9180), ("Tseung Kwan O", 22.3070, 114.2600),
        ]
        for (name, latitude, longitude) in water {
            XCTAssertTrue(Self.isWater(try Self.baseMap(tiles, latitude: latitude, longitude: longitude, reach: 300)), "\(name) is water")
        }
        for (name, latitude, longitude) in land {
            XCTAssertFalse(Self.isWater(try Self.baseMap(tiles, latitude: latitude, longitude: longitude, reach: 300)), "\(name) is land")
        }
    }

    /// The 3D scene of a new game on Hong Kong's map, looking at Central:
    /// bare without the pack's base map, with ground and roads with it.
    func testTheSceneAtCentralHasItsGround() throws {
        let world = GameWorld.newOverseasGame(try Self.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let focus = frame.worldPosition(latitude: 22.2819, longitude: 114.1582)
        let bare = Map3DScene(world: world, focus: focus, baseMap: try BaseMapTiles(data: Data(contentsOf: Self.taiwan, options: .alwaysMapped)))
        let scene = Map3DScene(world: world, focus: focus, baseMap: try Self.tiles())
        XCTAssertGreaterThan(scene.triangleCount, bare.triangleCount + 10_000, "bare \(bare.triangleCount), with the base map \(scene.triangleCount)")
    }

    /// The box a city's map covers holds its own middle and not Taipei.
    func testTheExtentHoldsItsMap() throws {
        let extent = try XCTUnwrap(HongKongRailwaysTests.pack(.hongKong)).extent()
        let anchor = try XCTUnwrap(extent.anchor)
        XCTAssertTrue(extent.holds(latitude: anchor.latitudeDegrees, longitude: anchor.longitudeDegrees))
        XCTAssertFalse(extent.holds(latitude: 25.0478, longitude: 121.5170))
    }
}
