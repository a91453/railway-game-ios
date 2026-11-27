import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1031: where the bundled buildings have none, the houses the
/// real-price registry has sold stand along the roads as they are: a sold
/// house's storeys and kind, not the hash's.
final class RegistryHousesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let houses: Result<RegistryHouses, Error> = Result {
        try RegistryHouses(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_registry_houses.dat")))
    }

    private static func file(_ houses: [(lon: Int32, lat: Int32, storeys: UInt8, kind: UInt8)], version: UInt32 = 1) -> Data {
        var data = Data("TWRH".utf8)
        func word(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        word(version)
        word(UInt32(houses.count))
        for house in houses {
            word(UInt32(bitPattern: house.lon))
            word(UInt32(bitPattern: house.lat))
            data.append(house.storeys)
            data.append(house.kind)
        }
        return data
    }

    // MARK: - The file

    func testAFileReadsAndOneOutOfShapeThrows() throws {
        let read = try RegistryHouses(data: Self.file([(121_217_000, 25_013_000, 24, 3), (120_301_500, 22_639_400, 4, 0)]))
        XCTAssertEqual(read.houses, [
            RegistryHouses.House(latitude: 22.6394, longitude: 120.3015, storeys: 4, kind: .terrace),
            RegistryHouses.House(latitude: 25.013, longitude: 121.217, storeys: 24, kind: .tower),
        ])
        XCTAssertEqual(read.houses(south: 25, north: 25.1, west: 121, east: 122).map(\.storeys), [24])
        XCTAssertTrue(read.houses(south: 23, north: 24, west: 120, east: 122).isEmpty)
        for bad in [
            Self.file([], version: 2),
            Self.file([(1, 1, 0, 0)]),
            Self.file([(1, 1, 3, 4)]),
            Self.file([(1, 1, 3, 0)]).dropLast(),
            Data("TWLP".utf8) + Self.file([]).dropFirst(4),
        ] {
            XCTAssertThrowsError(try RegistryHouses(data: Data(bad)))
        }
    }

    /// The app's file: houses of every kind, each kind's storeys in its
    /// range, and the towers round Taoyuan's high-speed station (青埔),
    /// which Overture misses.
    func testTheAppsFileHasTheNewTownsTowers() throws {
        let houses = try Self.houses.get().houses
        XCTAssertGreaterThan(houses.count, 20_000)
        for kind in RegistryHouses.Kind.allCases {
            XCTAssertTrue(houses.contains { $0.kind == kind }, "\(kind)")
        }
        XCTAssertTrue(houses.allSatisfy { house in
            switch house.kind {
            case .terrace: (1...6).contains(house.storeys)
            case .walkUp: (2...6).contains(house.storeys)
            case .midRise: (4...12).contains(house.storeys)
            case .tower: (8...60).contains(house.storeys)
            }
        })
        let qingpu = try Self.houses.get().houses(south: 25.005, north: 25.025, west: 121.205, east: 121.23)
        XCTAssertGreaterThan(qingpu.filter { $0.kind == .tower }.count, 20)
    }

    // MARK: - Along the roads

    /// A builder of a blank map, its scene's origin the world's, with a
    /// street along the south edge of a cell in the map's middle.
    private func builder() -> (builder: Map3DScene.Builder, cell: Map3DScene.ChunkKey, west: Float, north: Float) {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        let cell = Map3DScene.ChunkKey(column: Int(world.bounds.width / 2 / Land.cellLength),
                                       row: Int(world.bounds.height / 2 / Land.cellLength))
        let west = Float(builder.gridLine(cell.column, origin: 0)), north = Float(builder.gridLine(cell.row, origin: 0))
        builder.state.baseMap.roadLines.append(([Map3DPoint(west - 40, 0, north + 66), Map3DPoint(west + 110, 0, north + 66)], 6.5))
        builder.state.baseMap.roadKinds.append((.secondary, false))
        builder.state.roadside.streetFrontage = true
        builder.prepareFrontage()
        return (builder, cell, west, north)
    }

    func testAHouseBySoldDoorsTakesTheirStoreysAndKind() throws {
        var (builder, cell, west, north) = builder()
        let plain = builder.layFrontage(cell, density: 0, shops: false, blocked: [])
        XCTAssertTrue(plain.houses.allSatisfy { $0.floors == nil }, "none sold: the hash's")
        // A tower's door and a 透天厝's on the street's north side.
        (builder, cell, west, north) = self.builder()
        builder.state.roadside.registry[cell] = [
            .init(x: west + 12, z: north + 57, storeys: 24, kind: .tower),
            .init(x: west + 50, z: north + 57, storeys: 4, kind: .terrace),
        ]
        let laid = builder.layFrontage(cell, density: 0, shops: false, blocked: [])
        let tower = try XCTUnwrap(laid.houses.first { $0.floors == 24 })
        XCTAssertTrue(tower.flats)
        XCTAssertGreaterThanOrEqual(tower.house.depth, 18, "a tower is deeper than a block")
        XCTAssertLessThanOrEqual(abs(tower.house.middle.x - (west + 12)), tower.house.width / 2 + Map3DScene.Builder.registryReach)
        let terrace = try XCTUnwrap(laid.houses.first { $0.floors == 4 })
        XCTAssertFalse(terrace.flats)
        // Each sold house is one house.
        XCTAssertEqual(laid.houses.filter { $0.floors == 24 }.count, 1)
        XCTAssertEqual(laid.houses.filter { $0.floors == 4 }.count, 1)
        // The same every time.
        var again = self.builder().builder
        again.state.roadside.registry[cell] = builder.state.roadside.registry[cell]
        XCTAssertEqual(again.layFrontage(cell, density: 0, shops: false, blocked: []).houses.map(\.house.middle), laid.houses.map(\.house.middle))
    }

    /// A tower's storeys stand as sold, above the cap the real buildings
    /// round it would set.
    func testASoldHouseStandsAsTallAsItIs() {
        var mesh = Map3DMesh(), close = Map3DMesh()
        var blades: [Map3DSign] = []
        Map3DScene.Builder.addTownHouse(&mesh, close: &close, blades: &blades, middle: Map3DPoint(0, 0, 0), front: Map3DPoint(0, 0, 1),
                                        width: 16, depth: 18, flats: true, shops: false, wall: 0xFFFFFF, far: false, tallest: 3, floors: 24,
                                        r: { _ in 0.5 })
        var low = Map3DMesh()
        Map3DScene.Builder.addTownHouse(&low, close: &close, blades: &blades, middle: Map3DPoint(0, 0, 0), front: Map3DPoint(0, 0, 1),
                                        width: 16, depth: 18, flats: true, shops: false, wall: 0xFFFFFF, far: false, tallest: 3, r: { _ in 0.5 })
        func top(_ mesh: Map3DMesh) -> Float { mesh.positions.map(\.y).max() ?? 0 }
        XCTAssertGreaterThan(top(mesh), 24 * 3)
        XCTAssertLessThan(top(low), 4 * 4)
    }
}
