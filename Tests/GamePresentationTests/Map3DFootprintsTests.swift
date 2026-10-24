import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 389: Overture's building footprints in the 3D map of a
/// real-world game, read from decision 386's tiles.
final class Map3DFootprintsTests: XCTestCase {
    /// A tile as the tool's `encode_tile` writes it: `footprints/2`.
    static func tile(_ buildings: [(attributes: Int, rings: [[(Int, Int)]])]) -> [UInt8] {
        var out: [UInt8] = []
        func varint(_ value: Int) {
            var value = value
            while value > 0x7F {
                out.append(UInt8(value & 0x7F) | 0x80)
                value >>= 7
            }
            out.append(UInt8(value))
        }
        varint(2)
        varint(buildings.count)
        var cursor = (0, 0)
        for building in buildings {
            varint(building.attributes)
            varint(building.rings.count)
            for ring in building.rings {
                varint(ring.count)
                for point in ring {
                    for step in [point.0 - cursor.0, point.1 - cursor.1] { varint(step << 1 ^ step >> 63) }
                    cursor = point
                }
            }
        }
        return out
    }

    func testATileReadsAsTheToolWritesIt() throws {
        // A seven-storey block from the city's map, residential, Shi et
        // al.'s; then a works of unknown storeys round a yard (a hole).
        let bytes = Self.tile([
            (7 << 8 | 2 << 5 | 11 << 1 | 1, [[(100, 100), (100, 300), (400, 300), (400, 100)]]),
            (0 << 8 | 0 << 5 | 6 << 1 | 0, [[(1000, 1000), (1000, 2000), (2000, 2000), (2000, 1000)],
                                            [(1200, 1200), (1800, 1200), (1800, 1800), (1200, 1800)]]),
        ])
        let buildings = try Map3DFootprints.decode(bytes)
        XCTAssertEqual(buildings.count, 2)
        XCTAssertEqual(buildings[0].storeys, 7)
        XCTAssertEqual(buildings[0].storeysFrom, .cityMap)
        XCTAssertEqual(buildings[0].use, 11)
        XCTAssertEqual(buildings[0].rings.map { $0.map(\.x) }, [[100, 100, 400, 400]])
        XCTAssertEqual(buildings[1].rings.count, 2)
        XCTAssertEqual(buildings[1].rings[1].map(\.y), [1200, 1200, 1800, 1800])
        XCTAssertEqual(buildings[1].storeys, 0)
        // Cut short, or of another version: refused.
        XCTAssertThrowsError(try Map3DFootprints.decode(Array(bytes.dropLast(3))))
        XCTAssertThrowsError(try Map3DFootprints.decode([1] + bytes.dropFirst()))
        XCTAssertThrowsError(try Map3DFootprints.decode(bytes + [0]))
    }

    func testWhatABuildingIsDrawnAs() {
        func kind(use: Int, storeys: Int) -> Map3DScene.Builder.RealKind {
            Map3DFootprints.Building(storeys: storeys, storeysFrom: .tags, use: use, rings: []).kind
        }
        XCTAssertEqual(kind(use: 11, storeys: 3), .house)
        XCTAssertEqual(kind(use: 0, storeys: 0), .house)
        XCTAssertEqual(kind(use: 11, storeys: 12), .flats)
        XCTAssertEqual(kind(use: 3, storeys: 4), .shophouse)
        XCTAssertEqual(kind(use: 3, storeys: 20), .office)
        XCTAssertEqual(kind(use: 6, storeys: 1), .industry)
        XCTAssertEqual(kind(use: 4, storeys: 5), .civic)
        XCTAssertEqual(kind(use: 10, storeys: 1), .temple)
        XCTAssertEqual(kind(use: 13, storeys: 2), .transport)
        XCTAssertEqual(Map3DFootprints.Building(storeys: 0, storeysFrom: .guess, use: 0, rings: []).drawnStoreys, 2)
    }

    func testFootprintsKeepOffTheTrackAndWhatStandsBeforeThem() {
        let world = GameWorld.newGame()
        let m = Double(WorldCoordinate.unitsPerMetre), cell = Double(Land.cellLength)
        let region = WorldRegion(bounds: world.bounds)
        let middle = (x: (region.minX + region.maxX) / 2, y: (region.minY + region.maxY) / 2)
        // Three 10 × 12 m houses in three cells side by side.
        func house(_ index: Int) -> Map3DFootprints.Building {
            let x = (middle.x / cell).rounded(.down) * cell + Double(index) * cell + 20 * m, y = (middle.y / cell).rounded(.down) * cell + 20 * m
            return Map3DFootprints.Building(storeys: 3, storeysFrom: .guess, use: 11,
                                            rings: [[(x, y), (x, y + 12 * m), (x + 10 * m, y + 12 * m), (x + 10 * m, y)]])
        }
        let footprints = Map3DFootprints(buildings: [house(0), house(1), house(2)])
        func key(_ index: Int) -> Map3DScene.ChunkKey {
            Map3DScene.ChunkKey(column: Int((middle.x / cell).rounded(.down)) + index, row: Int((middle.y / cell).rounded(.down)))
        }
        var builder = Map3DScene.Builder(originX: middle.x, originY: middle.y, region: region, world: world)
        builder.target = .near
        let standing = builder.addFootprints(footprints, clearOf: [key(1)], takenBy: [key(2)])
        // The first stands; the second is on the track's cell, the third on
        // a cell taken before.
        XCTAssertEqual(standing, [key(0)])
        let all = Map3DScene.Builder(originX: middle.x, originY: middle.y, region: region, world: world)
        var every = all
        every.target = .near
        XCTAssertEqual(every.addFootprints(footprints, clearOf: [], takenBy: []), [key(0), key(1), key(2)])
        XCTAssertGreaterThan(every.nearMeshes.values.reduce(0) { $0 + $1.triangleCount },
                             builder.nearMeshes.values.reduce(0) { $0 + $1.triangleCount })
        // A seven-storey one stands 22.4 m.
        var tall = all
        tall.target = .near
        let high = Map3DFootprints.Building(storeys: 7, storeysFrom: .tags, use: 11, rings: house(0).rings)
        tall.addFootprints(Map3DFootprints(buildings: [high]), clearOf: [], takenBy: [])
        let top = tall.nearMeshes.values.flatMap(\.vertices).map(\.y).max() ?? 0
        XCTAssertEqual(top, Float(7) * 3.2 + tall.ground(x: middle.x, y: middle.y), accuracy: 3)
    }

    /// As in the A-Train, a building the player puts up clears the real
    /// ones it reaches: none of them is drawn, near or far, while one
    /// beside it that it does not reach still is.
    func testAPlacedBuildingClearsTheFootprintsItReaches() {
        var world = GameWorld.newGame()
        let m = Double(WorldCoordinate.unitsPerMetre), cell = Double(Land.cellLength)
        let region = WorldRegion(bounds: world.bounds)
        let middle = (x: (region.minX + region.maxX) / 2, y: (region.minY + region.maxY) / 2)
        let x0 = (middle.x / cell).rounded(.down) * cell + 20 * m, y0 = (middle.y / cell).rounded(.down) * cell + 20 * m
        // Two 10 × 12 m houses 14 m apart.
        func house(_ x: Double) -> Map3DFootprints.Building {
            Map3DFootprints.Building(storeys: 3, storeysFrom: .guess, use: 11,
                                     rings: [[(x, y0), (x, y0 + 12 * m), (x + 10 * m, y0 + 12 * m), (x + 10 * m, y0)]])
        }
        let footprints = Map3DFootprints(buildings: [house(x0), house(x0 + 24 * m)])
        // A 16 m house of the player's over the first one's east half.
        world.placedBuildings.append(PlacedBuilding(id: PlacedBuildingID(rawValue: 1), kind: .house,
                                                    centre: PlanPoint(x: Int64(x0 + 2 * m), y: Int64(y0 + 6 * m))))
        func triangles(_ world: GameWorld, _ target: Map3DScene.Builder.Target) -> Int {
            var builder = Map3DScene.Builder(originX: middle.x, originY: middle.y, region: region, world: world)
            builder.target = target
            let standing = builder.addFootprints(footprints, clearOf: [], takenBy: [])
            // Its cell keeps no city lot either way.
            XCTAssertFalse(standing.isEmpty)
            return (target == .near ? builder.nearMeshes : builder.farMeshes).values.reduce(0) { $0 + $1.triangleCount }
        }
        var bare = world
        bare.placedBuildings = []
        var one = world
        one.placedBuildings = [PlacedBuilding(id: PlacedBuildingID(rawValue: 1), kind: .house,
                                              centre: PlanPoint(x: Int64(x0 + 50 * m), y: Int64(y0 + 6 * m)))]
        for target in [Map3DScene.Builder.Target.near, .far] {
            let both = triangles(bare, target), cleared = triangles(world, target)
            XCTAssertGreaterThan(cleared, 0, "the house beside it still stands")
            XCTAssertLessThan(cleared, both, "the house under it is gone")
            // A placed building that reaches neither leaves both.
            XCTAssertEqual(triangles(one, target), both)
        }
    }

    /// What reaches a placed building's ground: an outline crossing its
    /// square, or round it; not one beside it, past the clearance.
    func testWhatReachesAPlacedBuildingsGround() {
        var world = GameWorld.newGame()
        let region = WorldRegion(bounds: world.bounds)
        let middle = (x: (region.minX + region.maxX) / 2, y: (region.minY + region.maxY) / 2)
        let m = Double(WorldCoordinate.unitsPerMetre)
        world.placedBuildings.append(PlacedBuilding(id: PlacedBuildingID(rawValue: 1), kind: .house,
                                                    centre: PlanPoint(x: Int64(middle.x), y: Int64(middle.y))))
        let builder = Map3DScene.Builder(originX: middle.x, originY: middle.y, region: region, world: world)
        // The 16 m square, grown by the 2 m clearance: ±10 m.
        XCTAssertEqual(builder.placedGround.first?.maxX ?? 0, Float(PlacedBuildingKind.house.side / 2 + PlacedBuildingRules.clearance) / Float(m),
                       accuracy: 0.01)
        func square(_ x: Float, _ z: Float, _ half: Float) -> [Map3DPoint] {
            [Map3DPoint(x - half, 0, z - half), Map3DPoint(x - half, 0, z + half), Map3DPoint(x + half, 0, z + half), Map3DPoint(x + half, 0, z - half)]
        }
        XCTAssertTrue(builder.onPlacedGround(square(0, 0, 3)), "inside")
        XCTAssertTrue(builder.onPlacedGround(square(0, 0, 40)), "round it")
        XCTAssertTrue(builder.onPlacedGround(square(12, 0, 4)), "over its edge")
        // A long thin one across it, no corner inside.
        XCTAssertTrue(builder.onPlacedGround([Map3DPoint(-30, 0, -1), Map3DPoint(-30, 0, 1), Map3DPoint(30, 0, 1), Map3DPoint(30, 0, -1)]))
        XCTAssertFalse(builder.onPlacedGround(square(16, 0, 4)), "beside it")
        XCTAssertFalse(Map3DScene.Builder(originX: middle.x, originY: middle.y, region: region, world: GameWorld.newGame())
            .onPlacedGround(square(0, 0, 3)), "no building of the player's")
    }

    /// The app's file, read where it is: Taipei 101 stands where it is, as
    /// tall as OpenStreetMap says, among buildings that all have storeys.
    func testTheAppsFileHasTaipei101() throws {
        let file = Map3DFrameCostReportTests.baseMap.appendingPathComponent("taiwan_buildings.pmtiles")
        let tiles = try FootprintTiles(data: Data(contentsOf: file, options: .alwaysMapped))
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 25.0340, longitudeDegrees: 121.5645)!)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let m = Double(WorldCoordinate.unitsPerMetre)
        let region = WorldRegion(minX: frame.middleX - 150 * m, minY: frame.middleY - 150 * m,
                                 maxX: frame.middleX + 150 * m, maxY: frame.middleY + 150 * m)
        let buildings = Map3DFootprints(tiles: tiles, frame: frame, region: region).buildings
        XCTAssertGreaterThan(buildings.count, 100)
        XCTAssertFalse(buildings.contains { $0.storeys == 0 })
        let tallest = try XCTUnwrap(buildings.max { $0.storeys < $1.storeys })
        XCTAssertGreaterThanOrEqual(tallest.storeys, 100)
        XCTAssertEqual(tallest.storeysFrom, .tags)
        let outline = try XCTUnwrap(tallest.rings.first)
        let middle = (x: outline.reduce(0) { $0 + $1.x } / Double(outline.count), y: outline.reduce(0) { $0 + $1.y } / Double(outline.count))
        XCTAssertLessThan(hypot(middle.x - frame.middleX, middle.y - frame.middleY) / m, 60)
    }
}
