import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 385: on a real-world map, the low homes and shops along the
/// real streets (each house fronting its road, clear of it, its size from
/// a hash of where the road lies), none where no road comes near, and none
/// on the land OpenStreetMap has for airports, military land, cemeteries,
/// golf courses, railway land and ports (the owner's 85.1 report: houses
/// filled Kaohsiung's airport, in a grid).
final class Map3DFrontageTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let land: Result<RealNoBuildLand, Error> = Result {
        try RealNoBuildLand(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_no_build.json")))
    }

    // MARK: - The file

    func testTheAppsFileHasKaohsiungsAirportAndItsBuildings() throws {
        let land = try Self.land.get()
        for kind in RealNoBuildLand.Kind.allCases {
            XCTAssertTrue(land.areas.contains { $0.kind == kind }, "\(kind)")
        }
        // Xiaogang: the runways' middle lies in an airport, with its
        // terminal and hangars.
        let xiaogang = (latitude: 22.5771, longitude: 120.3500)
        func ring(_ points: [RealNoBuildLand.Point]) -> [(x: Float, z: Float)] {
            points.map { (Float($0.longitude - xiaogang.longitude) * 100_000, Float(xiaogang.latitude - $0.latitude) * 100_000) }
        }
        let airport = try XCTUnwrap(land.areas.first { $0.kind == .airport && Map3DScene.Builder.NoBuild.inside(0, 0, ring($0.ring)) })
        let inside = land.buildings.filter { building in
            let middle = building.ring.reduce((0.0, 0.0)) { ($0.0 + $1.latitude, $0.1 + $1.longitude) }
            let count = Double(building.ring.count)
            return Map3DScene.Builder.NoBuild.inside(Float(middle.1 / count - xiaogang.longitude) * 100_000,
                                                      Float(xiaogang.latitude - middle.0 / count) * 100_000, ring(airport.ring))
        }
        XCTAssertTrue(inside.contains { $0.use == .terminal })
        XCTAssertTrue(inside.contains { $0.use == .hangar })
        XCTAssertTrue(land.buildings.allSatisfy { $0.height >= 3 && $0.height <= 80 })
    }

    func testAFileOutOfShapeThrows() throws {
        let kinds = #""kinds":["airport","military","cemetery","golf","railway","port"]"#
        let good = try RealNoBuildLand(data: Data(#"{\#(kinds),"areas":[[2,2257710,12035000,10,0,0,10]],"buildings":[[12,1,2257710,12035000,1,0,0,1]]}"#.utf8))
        XCTAssertEqual(good.areas.first?.kind, .cemetery)
        XCTAssertEqual(good.areas.first?.ring.map(\.latitude), [22.5771, 22.5772, 22.5772])
        XCTAssertEqual(good.areas.first?.ring.map(\.longitude), [120.35, 120.35, 120.3501])
        XCTAssertEqual(good.buildings.first?.use, .hangar)
        XCTAssertEqual(good.buildings.first?.height, 12)
        for bad in [
            #"{"kinds":["airport"],"areas":[],"buildings":[]}"#,
            #"{\#(kinds),"areas":[[9,1,1,1,1,1,1]],"buildings":[]}"#,
            #"{\#(kinds),"areas":[[0,1,1,1,1]],"buildings":[]}"#,
            #"{\#(kinds),"areas":[],"buildings":[[12,7,1,1,1,1,1,1]]}"#,
        ] {
            XCTAssertThrowsError(try RealNoBuildLand(data: Data(bad.utf8)), bad)
        }
    }

    // MARK: - Laying houses along a street

    /// A builder of a blank map, its scene's origin the world's, with
    /// `roads` (scene metres, half widths with the pavement) as a real
    /// map's, laying houses along them; and a cell in the map's middle.
    private func builder(roads: [(points: [Map3DPoint], half: Float, kind: Map3DBaseMap.RoadKind)])
        -> (builder: Map3DScene.Builder, cell: Map3DScene.ChunkKey, west: Float, north: Float) {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        let cell = Map3DScene.ChunkKey(column: Int(world.bounds.width / 2 / Land.cellLength),
                                       row: Int(world.bounds.height / 2 / Land.cellLength))
        let west = Float(builder.gridLine(cell.column, origin: 0)), north = Float(builder.gridLine(cell.row, origin: 0))
        for road in roads {
            builder.roadLines.append((road.points.map { $0 + Map3DPoint(west, 0, north) }, road.half))
            builder.roadKinds.append((road.kind, false))
        }
        builder.streetFrontage = true
        builder.prepareFrontage()
        return (builder, cell, west, north)
    }

    /// A lane slanting across the cell and a street along its south edge.
    private let roads: [(points: [Map3DPoint], half: Float, kind: Map3DBaseMap.RoadKind)] = [
        ([Map3DPoint(-40, 0, -6), Map3DPoint(110, 0, 50)], 2.5, .minor),
        ([Map3DPoint(-40, 0, 66), Map3DPoint(110, 0, 66)], 6.5, .secondary),
    ]

    func testEachHouseFrontsItsStreetClearOfEveryRoad() throws {
        var (builder, cell, west, north) = builder(roads: roads)
        let laid = builder.layFrontage(cell, density: 1, shops: false, blocked: [])
        let houses = laid.houses.map(\.house)
        XCTAssertGreaterThan(houses.count, 8)
        for (index, house) in houses.enumerated() {
            // In the cell.
            XCTAssertTrue((west..<west + 64).contains(house.middle.x) && (north..<north + 64).contains(house.middle.z), "\(index)")
            // Clear of both roads and their pavements.
            for line in builder.roadLines {
                XCTAssertGreaterThanOrEqual(house.distance(from: line.points[0], to: line.points[1]), line.half + 0.19, "\(index)")
            }
            // Along a road, facing it: the nearest road lies ahead.
            let nearest = try XCTUnwrap(builder.roadLines.min { a, b in
                house.distance(from: a.points[0], to: a.points[1]) - a.half < house.distance(from: b.points[0], to: b.points[1]) - b.half
            })
            let direction = try XCTUnwrap((nearest.points[1] - nearest.points[0]).normalized)
            XCTAssertEqual(abs(house.along.dot(direction)), 1, accuracy: 1e-4, "\(index)")
            func across(_ point: Map3DPoint) -> Float {
                let offset = point - nearest.points[0]
                return (offset - direction * offset.dot(direction)).length
            }
            XCTAssertLessThan(across(house.middle + house.front * (house.depth / 2)),
                              across(house.middle - house.front * (house.depth / 2)), "\(index)")
            for other in houses[(index + 1)...] {
                XCTAssertFalse(house.overlaps(other), "\(index)")
            }
        }
        // Not all alike, and not all one way: some face the lane, some the
        // street.
        XCTAssertGreaterThan(Set(houses.map { Int($0.width * 10) }).count, 4)
        XCTAssertGreaterThan(Set(houses.map { Int(($0.front.x * 10).rounded()) }).count, 1)
        // The same every time.
        var again = self.builder(roads: roads).builder
        XCTAssertEqual(again.layFrontage(cell, density: 1, shops: false, blocked: []).houses.map(\.house.middle), houses.map(\.middle))
    }

    func testNoHouseWhereNoRoadComesNear() {
        var (builder, cell, _, _) = builder(roads: [([Map3DPoint(-400, 0, -300), Map3DPoint(-300, 0, -300)], 2.5, .minor)])
        XCTAssertTrue(builder.layFrontage(cell, density: 2, shops: false, blocked: []).houses.isEmpty)
        // Nor along a motorway or a car park's aisle.
        var fast = self.builder(roads: [([Map3DPoint(-40, 0, 32), Map3DPoint(110, 0, 32)], 6.5, .motorway),
                                        ([Map3DPoint(32, 0, -40), Map3DPoint(32, 0, 110)], 1.75, .service)])
        XCTAssertTrue(fast.builder.layFrontage(fast.cell, density: 2, shops: false, blocked: []).houses.isEmpty)
    }

    func testNoHouseOnNoBuildLandNorOnABlockedCell() {
        var (builder, cell, west, north) = builder(roads: roads)
        // The cell's west half no-build land.
        builder.noBuild.rings = [[(west - 50, north - 50), (west + 32, north - 50), (west + 32, north + 120), (west - 50, north + 120)]]
        for row in cell.row - 2...cell.row + 2 {
            for column in cell.column - 2...cell.column + 2 {
                builder.noBuild.byCell[Map3DScene.ChunkKey(column: column, row: row), default: []].append(0)
            }
        }
        let houses = builder.layFrontage(cell, density: 1, shops: false, blocked: []).houses.map(\.house)
        XCTAssertFalse(houses.isEmpty)
        XCTAssertTrue(houses.allSatisfy { $0.corners.allSatisfy { $0.x >= west + 32 } })
        var blocked = self.builder(roads: roads)
        XCTAssertTrue(blocked.builder.layFrontage(blocked.cell, density: 1, shops: false, blocked: [blocked.cell]).houses.isEmpty)
    }

    func testTheShapesGeometry() {
        let house = Map3DScene.Builder.StreetHouse(middle: .zero, front: Map3DPoint(0, 0, 1), along: Map3DPoint(1, 0, 0), width: 6, depth: 10)
        XCTAssertEqual(house.distance(from: Map3DPoint(-10, 0, 8), to: Map3DPoint(10, 0, 8)), 3, accuracy: 1e-5)
        XCTAssertEqual(house.distance(from: Map3DPoint(-10, 0, 0), to: Map3DPoint(10, 0, 0)), 0)
        XCTAssertEqual(house.distance(from: Map3DPoint(7, 0, 9), to: Map3DPoint(7, 0, 20)), 4 * Float(2).squareRoot(), accuracy: 1e-5)
        let beside = Map3DScene.Builder.StreetHouse(middle: Map3DPoint(6, 0, 0), front: Map3DPoint(0, 0, 1), along: Map3DPoint(1, 0, 0),
                                                    width: 6, depth: 10)
        XCTAssertFalse(house.overlaps(beside), "a shared wall")
        let turned = Map3DScene.Builder.StreetHouse(middle: Map3DPoint(5, 0, 5), front: Map3DPoint(1, 0, 0), along: Map3DPoint(0, 0, -1),
                                                    width: 6, depth: 10)
        XCTAssertTrue(house.overlaps(turned))
        let square: [(x: Float, z: Float)] = [(0, 0), (10, 0), (10, 10), (0, 10)]
        XCTAssertTrue(Map3DScene.Builder.NoBuild.inside(5, 5, square))
        XCTAssertFalse(Map3DScene.Builder.NoBuild.inside(15, 5, square))
    }

    // MARK: - The scene

    /// A real-world map round Kaohsiung's airport: with the airport's
    /// land, nothing but its own buildings stands on it.
    func testNoTownOnTheAirport() throws {
        let tiles = try BaseMapTiles(data: Data(contentsOf: Self.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                                options: .alwaysMapped))
        let land = try Self.land.get()
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.5771, longitudeDegrees: 120.3500)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let airport = try XCTUnwrap(land.areas.first { $0.kind == .airport && abs($0.ring[0].latitude - 22.57) < 0.03 && $0.ring.count > 50 })
        let airportOnly = RealNoBuildLand(areas: [airport])
        func standing(_ noBuild: RealNoBuildLand?) -> Int {
            let scene = Map3DScene(world: world, baseMap: tiles, noBuild: noBuild)
            let ring = airport.ring.map { place -> (x: Float, z: Float) in
                let at = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
                let point = scene.point(worldX: at.x, worldY: at.y, height: 0)
                return (point.x, point.z)
            }
            return scene.chunks.flatMap { [$0.mesh, $0.far] }.reduce(0) { total, mesh in
                total + mesh.vertices.filter { $0.y > 2.5 && Map3DScene.Builder.NoBuild.inside($0.x, $0.z, ring) }.count
            }
        }
        // What stays on the bare airport is the base map's own buildings.
        let town = standing(nil), bare = standing(airportOnly), built = standing(land)
        XCTAssertGreaterThan(town, 20 * bare, "the city's lots on the airport without its land")
        XCTAssertGreaterThan(built, bare + 1_000, "its terminals and hangars")
        XCTAssertLessThan(built, town / 5)
    }
}
