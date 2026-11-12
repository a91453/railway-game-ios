import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 707: the game's own houses along a real-world map's roads no
/// taller than the real buildings round them; none by a runway, on a
/// taxiway or an apron; no founded towns in the airports' screenshot maps.
final class Map3DLowRiseTests: XCTestCase {
    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Resources/")

    static let footprints = Result {
        try FootprintTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_buildings.pmtiles"), options: .alwaysMapped))
    }

    /// The caps of every fourth 64 m cell within `reach` metres (each way)
    /// of a new game's middle at (`latitude`, `longitude`), `nil`s as 0.
    static func caps(latitude: Double, longitude: Double, reach: Double) throws -> Set<Int> {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
        var lowRise = Map3DLowRise(tiles: try footprints.get(), frame: RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds))
        let cell = Double(Land.cellLength), middle = Land.rows(in: GameWorld.newGameBounds) / 2
        let cells = Int(reach * Double(WorldCoordinate.unitsPerMetre) / cell)
        var caps = Set<Int>()
        for row in stride(from: middle - cells, through: middle + cells, by: 4) {
            for column in stride(from: middle - cells, through: middle + cells, by: 4) {
                caps.insert(lowRise.cap(worldX: (Double(column) + 0.5) * cell, worldY: (Double(row) + 0.5) * cell) ?? 0)
            }
        }
        return caps
    }

    /// Qimei, Wang'an, Lanyu, Green Island and Xiaoliuqiu, by their
    /// airports or harbour: nothing real there is over four storeys, so no
    /// house of the game's is, and most of each is held to two or three.
    func testTheSmallIslandsHousesAreHeldToTheRealOnes() throws {
        for (name, latitude, longitude) in [("Qimei", 23.2131, 119.4175), ("Wang'an", 23.3674, 119.5028), ("Lanyu", 22.0270, 121.5350),
                                            ("Green Island", 22.6739, 121.4660), ("Xiaoliuqiu", 22.3400, 120.3720)] {
            let caps = try Self.caps(latitude: latitude, longitude: longitude, reach: 2_000)
            XCTAssertTrue(caps.isSubset(of: [0, 2, 3, 4]), "\(name): \(caps.sorted())")
            XCTAssertTrue(caps.contains(2), "\(name): \(caps.sorted())")
        }
        // Qimei and Lanyu have nothing over two storeys by their airports:
        // every place with buildings round it is held to two.
        for (latitude, longitude) in [(23.2131, 119.4175), (22.0270, 121.5350)] {
            XCTAssertEqual(try Self.caps(latitude: latitude, longitude: longitude, reach: 2_000), [0, 2])
        }
    }

    /// The main island's cities are as they were: round their main
    /// stations a real building of six storeys or more is always near, so
    /// no cell has a cap and every house is laid and drawn by the rule
    /// before this decision (a cap of `nil` changes nothing:
    /// ``testAHouseWithNoCapIsAsBefore``).
    func testTheMainIslandsCitiesHaveNoCap() throws {
        for (name, latitude, longitude) in [("Taipei", 25.0478, 121.5170), ("Banqiao", 25.0143, 121.4625), ("Zhongli", 24.9536, 121.2256),
                                            ("Hsinchu", 24.8016, 120.9716), ("Taichung", 24.1371, 120.6869), ("Tainan", 22.9971, 120.2126),
                                            ("Kaohsiung", 22.6394, 120.3024)] {
            XCTAssertEqual(try Self.caps(latitude: latitude, longitude: longitude, reach: 1_500), [0], name)
        }
    }

    /// Too few real buildings say nothing; six storeys or more is no cap;
    /// under that the tallest, and never under two.
    func testTheCapIsTheTallestRealBuildingNear() throws {
        // Lanyu's airport, then the open sea west of it.
        XCTAssertEqual(try Self.caps(latitude: 22.0270, longitude: 121.5350, reach: 100), [2])
        XCTAssertEqual(try Self.caps(latitude: 22.03, longitude: 121.30, reach: 500), [0])
        XCTAssertEqual(Map3DLowRise.tallestHouse, 6)
        XCTAssertEqual(Map3DLowRise.lowest, 2)
    }

    private static func house(flats: Bool, tallest: Int?, seed: Int32, far: Bool) -> Map3DMesh {
        var mesh = Map3DMesh(), close = Map3DMesh(), blades: [Map3DSign] = []
        let r = { (extra: Int32) in map3DRandom(seed, 7, salt: extra) }
        if far {
            Map3DScene.Builder.addFarTownHouse(&mesh, middle: Map3DPoint(0, 0, 0), front: Map3DPoint(0, 0, 1), width: 6, depth: 12, flats: flats,
                                               wall: 0xFFFF_FFFF, tallest: tallest, r: r)
        } else {
            Map3DScene.Builder.addTownHouse(&mesh, close: &close, blades: &blades, middle: Map3DPoint(0, 0, 0), front: Map3DPoint(0, 0, 1), width: 6,
                                            depth: 12, flats: flats, shops: false, wall: 0xFFFF_FFFF, far: false, tallest: tallest, r: r)
        }
        return mesh
    }

    func testAHouseWithNoCapIsAsBefore() {
        for seed: Int32 in 0..<40 {
            for flats in [false, true] {
                for far in [false, true] {
                    XCTAssertEqual(Self.house(flats: flats, tallest: nil, seed: seed, far: far).vertices,
                                   Self.house(flats: flats, tallest: 6, seed: seed, far: far).vertices)
                }
            }
        }
    }

    /// Two floors: a ground floor of at most 4.3 m, one above of at most
    /// 3.7 m, the parapet's 0.7 m, and on the full house a tank or a shed
    /// of at most 3.3 m on the roof.
    func testAHouseKeepsToItsCap() {
        var tallestUncapped: Float = 0
        for seed: Int32 in 0..<200 {
            for flats in [false, true] {
                let far = Self.house(flats: flats, tallest: 2, seed: seed, far: true).vertices.map(\.y).max() ?? 0
                let near = Self.house(flats: flats, tallest: 2, seed: seed, far: false).vertices.map(\.y).max() ?? 0
                XCTAssertLessThanOrEqual(far, 8.71)
                XCTAssertLessThanOrEqual(near, 12.1)
                tallestUncapped = max(tallestUncapped, Self.house(flats: flats, tallest: nil, seed: seed, far: true).vertices.map(\.y).max() ?? 0)
            }
        }
        XCTAssertGreaterThan(tallestUncapped, 18, "A block of flats of six floors, without a cap")
    }

    // MARK: - Airfields

    func testNoHouseStandsByARunwayOnATaxiwayOrAnApron() {
        typealias Clear = Map3DScene.Builder.AirfieldClear
        XCTAssertEqual(Clear.runwayStrip(length: 992), 75)
        XCTAssertEqual(Clear.runwayStrip(length: 3_660), 140)
        var field = Clear.Field()
        // A runway of 1,000 m east to west, a taxiway north from its
        // middle, an apron at the taxiway's end.
        field.add([Map3DBaseMap.Point(x: 0, z: 0), Map3DBaseMap.Point(x: 1_000, z: 0)], half: Clear.runwayStrip(length: 1_000))
        field.add([Map3DBaseMap.Point(x: 500, z: 0), Map3DBaseMap.Point(x: 500, z: -200)], half: 23 / 2 + Clear.taxiwayMargin)
        field.add(apron: [Map3DBaseMap.Point(x: 450, z: -200), Map3DBaseMap.Point(x: 450, z: -300), Map3DBaseMap.Point(x: 600, z: -300),
                          Map3DBaseMap.Point(x: 600, z: -200)])
        var clear = Clear()
        clear.fields.append(field)
        for (x, z, inside) in [(500, 0, true), (200, 74, true), (200, -74, true), (200, 76, false), (-60, 0, true), (-80, 0, false),
                               (520, -150, true), (530, -150, false), (590, -290, true), (610, -290, false), (5_000, 5_000, false)] as [(Float, Float, Bool)] {
            XCTAssertEqual(clear.contains(Map3DPoint(x, 0, z)), inside, "\(x), \(z)")
        }
        XCTAssertFalse(Clear().contains(Map3DPoint(0, 0, 0)))
    }

    // MARK: - The airports' screenshot maps

    /// The scene reads no real land: a new game with none founds a blank
    /// map's towns, towers and all, which stood on Qimei, Lanyu and Green
    /// Island (FOLLOW-AIR's report, decision 702).
    func testTheAirportsScreenshotMapsFoundNoTowns() {
        for scene in [ScreenshotScene.airportSongshan, .airportTaoyuanNight] {
            let world = scene.make(in: .traditionalChinese)
            XCTAssertTrue(CitySkyline(world: world).lots.isEmpty, scene.rawValue)
            XCTAssertFalse(world.airports.isEmpty, scene.rawValue)
        }
    }
}
