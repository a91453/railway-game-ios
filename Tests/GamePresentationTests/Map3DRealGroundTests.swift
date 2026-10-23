import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 234: a real-world map's 3D ground from the app's
/// base map: the file read in Swift (PMTiles, gzip, vector tiles), its
/// polygons cut to the ground's triangles, its roads laid as strips, and
/// the city's lots kept off them.
final class Map3DRealGroundTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }

    // MARK: - Reading the file

    func testInflateReadsStoredAndFixedBlocks() throws {
        // A stored block: final, type 0, then the length and its complement.
        XCTAssertEqual(try Inflate.inflate([0x01, 0x03, 0x00, 0xFC, 0xFF, 0x61, 0x62, 0x63][...]), Array("abc".utf8))
        // Python's zlib, raw deflate at level 9: a fixed Huffman block
        // with a copy from back in the output.
        let packed: [UInt8] = [203, 72, 205, 201, 201, 87, 200, 64, 34, 139, 18, 51, 115, 202, 19, 43, 1]
        XCTAssertEqual(try Inflate.inflate(packed[...]), Array("hello hello hello railway".utf8))
        XCTAssertThrowsError(try Inflate.inflate(packed.dropLast(3)))
        XCTAssertThrowsError(try Inflate.gunzip([0x1F, 0x8B, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    }

    func testTileIDsFollowTheHilbertCurve() {
        // The PMTiles spec's numbering, as tools/basemap/build_basemap.py
        // writes it.
        XCTAssertEqual(PMTilesArchive.tileID(zoom: 0, x: 0, y: 0), 0)
        XCTAssertEqual([(0, 0), (0, 1), (1, 1), (1, 0)].map { PMTilesArchive.tileID(zoom: 1, x: $0.0, y: $0.1) }, [1, 2, 3, 4])
        XCTAssertEqual(PMTilesArchive.tileID(zoom: 2, x: 3, y: 0), 20)
        XCTAssertEqual(PMTilesArchive.tileID(zoom: 14, x: 13722, y: 7013), 305_278_258)
    }

    func testTheBaseMapReadsAsTheBuilderWroteIt() throws {
        let tiles = try Self.tiles.get()
        // Taipei Main Station's tile, its features counted by Python from
        // the same file.
        let bytes = try XCTUnwrap(try tiles.archive.tile(zoom: 14, x: 13722, y: 7013))
        XCTAssertEqual(bytes.count, 86_170)
        let tile = try VectorTile(bytes)
        XCTAssertEqual(tile.layers.mapValues(\.features.count),
                       ["water": 15, "landcover": 245, "park": 55, "boundary": 5, "transportation": 967, "transportation_name": 822, "place": 17])
        XCTAssertEqual(tile.layers["transportation"]?.extent, 4096)
        let classes = Set(tile.layers["transportation"]?.features.compactMap { $0.string("class") } ?? [])
        XCTAssertEqual(classes, ["trunk", "primary", "secondary", "tertiary", "minor", "service"])
        // Only the layers asked for, and nothing outside Taiwan's tiles.
        XCTAssertEqual(Set(try VectorTile(bytes, layers: ["park"]).layers.keys), ["park"])
        XCTAssertNil(try tiles.archive.tile(zoom: 14, x: 0, y: 0))
    }

    // MARK: - Cutting

    func testEarcutCoversAPolygonAndLeavesItsHole() {
        let outer: [(x: Double, y: Double)] = [(0, 0), (10, 0), (10, 10), (5, 4), (0, 10)]
        let hole: [(x: Double, y: Double)] = [(2, 1), (3, 1), (3, 2), (2, 2)]
        let points = outer + hole
        let triangles = Earcut.triangulate([outer, hole])
        var area = 0.0
        for at in stride(from: 0, to: triangles.count, by: 3) {
            let a = points[triangles[at]], b = points[triangles[at + 1]], c = points[triangles[at + 2]]
            area += abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
        }
        // 100, less the notch (10 × 6 / 2) and the hole (1).
        XCTAssertEqual(area, 100 - 30 - 1, accuracy: 1e-9)
    }

    private func builder() -> Map3DScene.Builder {
        let world = GameWorld.newGame()
        return Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
    }

    private func flatArea(_ meshes: [Map3DMesh], color: UInt32) -> Double {
        var area = 0.0
        for mesh in meshes {
            for at in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = mesh.vertices[Int(mesh.indices[at])], b = mesh.vertices[Int(mesh.indices[at + 1])], c = mesh.vertices[Int(mesh.indices[at + 2])]
                guard a.color == color else { continue }
                area += Double(abs((b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z))) / 2
            }
        }
        return area
    }

    func testACoverIsCutToTheGroundWithoutLosingAnyOfIt() {
        var builder = builder()
        typealias P = Map3DBaseMap.Point
        let outer = [P(x: 10, z: 10), P(x: 150, z: 10), P(x: 150, z: 140), P(x: 10, z: 140)]
        let hole = [P(x: 40, z: 40), P(x: 60, z: 40), P(x: 60, z: 60), P(x: 40, z: 60)]
        // Kept to a tile ending at x = 120.
        let bounds = Map3DBaseMap.Bounds(minX: -1000, minZ: -1000, maxX: 120, maxZ: 1000)
        var taken = Set<Map3DScene.ChunkKey>()
        builder.addArea(Map3DBaseMap.Area(cover: .park, rings: [outer, hole], bounds: bounds), taking: &taken)
        let meshes = Array(builder.meshes.values)
        XCTAssertEqual(flatArea(meshes, color: Map3DPalette.park), 110 * 130 - 400, accuracy: 0.5)
        // Every corner lies on the ground as drawn, the park's lift over it.
        for vertex in meshes.flatMap(\.vertices) {
            XCTAssertEqual(vertex.y, builder.drawnGround(x: vertex.x, z: vertex.z) + Map3DScene.Builder.lift(of: .park), accuracy: 0.001)
            XCTAssertGreaterThan(vertex.ny, 0.99, "faces up")
        }
        // The one cell it covers more than half of: (64…128, 64…128) but
        // for x past 120; the cell holding the hole is still half park.
        XCTAssertTrue(taken.contains(Map3DScene.ChunkKey(column: 1, row: 1)))
        XCTAssertTrue(taken.contains(Map3DScene.ChunkKey(column: 0, row: 0)))
        XCTAssertFalse(taken.contains(Map3DScene.ChunkKey(column: 2, row: 1)))
    }

    func testASeaWhoseHoleIsTheWholeTileLeavesNothing() {
        var builder = builder()
        typealias P = Map3DBaseMap.Point
        // The base map's sea over an inland tile: the tile, less the land,
        // which covers it all.
        let square = [P(x: -10, z: -10), P(x: 300, z: -10), P(x: 300, z: 300), P(x: -10, z: 300)]
        var taken = Set<Map3DScene.ChunkKey>()
        builder.addArea(Map3DBaseMap.Area(cover: .water, rings: [square, square.reversed()],
                                          bounds: Map3DBaseMap.Bounds(minX: 0, minZ: 0, maxX: 256, maxZ: 256)), taking: &taken)
        XCTAssertEqual(flatArea(Array(builder.meshes.values), color: Map3DPalette.water), 0)
        XCTAssertTrue(taken.isEmpty)
    }

    func testAStripBreaksWhereTheGroundsTrianglesMeet() {
        let builder = builder()
        typealias P = Map3DBaseMap.Point
        // 200 m east: across x = 64, 128 and 192, and the diagonals of the
        // three cells it runs through, at z = 10: x = 74, 138.
        let cuts = builder.splits(from: P(x: 0, z: 10), to: P(x: 200, z: 10)).map { $0 * 200 }
        for (cut, expected) in zip(cuts, [0, 10, 64, 74, 128, 138, 192, 200] as [Double]) {
            XCTAssertEqual(cut, expected, accuracy: 1e-6)
        }
        XCTAssertEqual(cuts.count, 8)
        XCTAssertNil(Map3DScene.Builder.clipSegment(P(x: -5, z: 0), P(x: -1, z: 0), to: Map3DBaseMap.Bounds(minX: 0, minZ: -1, maxX: 10, maxZ: 1)))
        let kept = Map3DScene.Builder.clipSegment(P(x: -5, z: 0), P(x: 15, z: 0), to: Map3DBaseMap.Bounds(minX: 0, minZ: -1, maxX: 10, maxZ: 1))
        XCTAssertEqual(kept?.0, P(x: 0, z: 0))
        XCTAssertEqual(kept?.1, P(x: 10, z: 0))
    }

    // MARK: - Room beside the roads (decision 345)

    /// The room `builder` finds in cell (0, 0), its middle and side in
    /// scene metres, with `roads` (middle line, half width) laid.
    private func room(_ roads: [(points: [Map3DPoint], half: Float)], side: Int = 40) -> (x: Double, z: Double, side: Int)? {
        var builder = builder()
        builder.roadLines = roads
        let key = Map3DScene.ChunkKey(column: 0, row: 0)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        return builder.roomBesideRoads(column: 0, row: 0, side: side, in: builder.roadPieces(near: [key])[key] ?? [])
            .map { ($0.x / metre, $0.y / metre, $0.side) }
    }

    /// Whether the square comes within half a metre of any road's strip,
    /// to a tenth of a metre, or out of its cell's metre from the edge.
    private func clear(_ room: (x: Double, z: Double, side: Int), of roads: [(points: [Map3DPoint], half: Float)]) -> Bool {
        let half = Double(room.side) / 2
        guard room.x - half >= 1, room.x + half <= 63, room.z - half >= 1, room.z + half <= 63 else { return false }
        for (points, width) in roads {
            for (a, b) in zip(points, points.dropFirst()) {
                let length = Double((b - a).length), steps = Int(length * 10)
                for step in 0...steps {
                    let t = Double(step) / Double(max(steps, 1))
                    let x = Double(a.x) + Double(b.x - a.x) * t, z = Double(a.z) + Double(b.z - a.z) * t
                    let dx = max(abs(x - room.x) - half, 0), dz = max(abs(z - room.z) - half, 0)
                    if (dx * dx + dz * dz).squareRoot() < Double(width) + 0.5 { return false }
                }
            }
        }
        return true
    }

    func testALotBesideALaneKeepsItsWholeSideClearOfIt() throws {
        // A lane 5 m wide down the cell's west side.
        let roads = [([Map3DPoint(8, 0, -40), Map3DPoint(8, 0, 120)], Float(2.5))]
        let room = try XCTUnwrap(room(roads))
        XCTAssertEqual(room.side, 40)
        XCTAssertTrue(clear(room, of: roads))
        // As near the middle as the lane lets it: its west side 11 m in.
        XCTAssertEqual(room.x - 20, 11, accuracy: 1)
        XCTAssertEqual(room.z, 32, accuracy: 1)
    }

    func testALotAMainRoadCrossesKeepsTheBiggestRoomBesideIt() throws {
        // A main road and its pavements, 15 m, through the middle, north
        // to south: some 22 m each side.
        let through = [([Map3DPoint(32, 0, -40), Map3DPoint(32, 0, 120)], Float(7.5))]
        let side = try XCTUnwrap(room(through))
        XCTAssertTrue(clear(side, of: through))
        XCTAssertEqual(side.side, 22)
        // A crossroads of two: a quarter's corner, smaller still.
        let crossroads = through + [([Map3DPoint(-40, 0, 32), Map3DPoint(120, 0, 32)], Float(7.5))]
        let quarter = try XCTUnwrap(room(crossroads))
        XCTAssertTrue(clear(quarter, of: crossroads))
        XCTAssertEqual(quarter.side, 22)
        // A slanting lane: still clear of it.
        let slant = [([Map3DPoint(-10, 0, 0), Map3DPoint(70, 0, 50)], Float(2.5))]
        XCTAssertTrue(clear(try XCTUnwrap(room(slant)), of: slant))
        // No lot bigger than its own side.
        XCTAssertEqual(room([], side: 28)?.side, 28)
        XCTAssertEqual(room([], side: 28)?.x ?? 0, 32, accuracy: 1)
    }

    func testALotWithTooLittleRoomHasNone() {
        // Lanes 14 m apart each way: nothing as wide as the smallest lot.
        var lanes: [(points: [Map3DPoint], half: Float)] = []
        for at in stride(from: Float(0), through: 64, by: 14) {
            lanes.append(([Map3DPoint(at, 0, -10), Map3DPoint(at, 0, 74)], 1.75))
            lanes.append(([Map3DPoint(-10, 0, at), Map3DPoint(74, 0, at)], 1.75))
        }
        XCTAssertNil(room(lanes))
        XCTAssertEqual(Map3DScene.Builder.smallestLot, 16)
    }

    // MARK: - The scene

    func testARealWorldSceneHasTheRealMapsRoadsWaterAndParks() throws {
        let tiles = try Self.tiles.get()
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170))
        let world = GameWorld.newGame(anchor: anchor)
        let plain = Map3DScene(world: world)
        let real = Map3DScene(world: world, baseMap: tiles)
        func colors(_ scene: Map3DScene) -> Set<UInt32> { Set(scene.chunks.flatMap(\.mesh.vertices).map(\.color)) }
        let painted = colors(real)
        for color in [Map3DPalette.road(.trunk), Map3DPalette.road(.primary), Map3DPalette.road(.minor), Map3DPalette.cover(.grass)] {
            XCTAssertTrue(painted.contains(color), String(color, radix: 16))
            // Decision 370: the grass the farms' atlas green too.
            guard color != Map3DPalette.farm else { continue }
            XCTAssertFalse(colors(plain).contains(color), String(color, radix: 16))
        }
        // Decision 241: paved sidewalks along the main roads, and the
        // yellow centre line down the two-way ones (not a lane's, not a
        // motorway's).
        XCTAssertTrue(painted.isSuperset(of: [Map3DPalette.sidewalk, Map3DPalette.centreLine]))
        XCTAssertEqual(Map3DScene.Builder.sidewalk(of: .primary), 3)
        XCTAssertEqual(Map3DScene.Builder.sidewalk(of: .minor), 0)
        XCTAssertTrue(Map3DScene.Builder.lift(of: .water) < Map3DScene.Builder.sidewalkLift)
        XCTAssertTrue(Map3DScene.Builder.sidewalkLift < Map3DScene.Builder.lift(of: .service))
        XCTAssertTrue(Map3DScene.Builder.lift(of: .motorway) < Map3DScene.Builder.centreLineLift)
        XCTAssertTrue(Map3DScene.Builder.centreLineLift < Map3DShadow.lift)
        // ...and all of them under the track's bed, which they would
        // otherwise paint over where track crosses a road or a park.
        XCTAssertLessThan(Map3DShadow.lift, Map3DScene.railLift - Map3DScene.Builder.bedDrop)
        // Parks and ponds the city's own open lots also have.
        XCTAssertTrue(painted.isSuperset(of: [Map3DPalette.cover(.park), Map3DPalette.cover(.water)]))
        // Decision 356: the water, and only the water, mirrors.
        let vertices = real.chunks.flatMap(\.mesh.vertices)
        XCTAssertTrue(vertices.contains(where: \.isWater))
        XCTAssertTrue(vertices.allSatisfy { $0.isWater == ($0.color == Map3DPalette.water) })
        // The real map's water and parks take some of the city's lots
        // round the station, and its streets leave the rest the room
        // beside them (decision 345; until then they took most):
        // a building never stands on a road.
        // (Their shadows, which are black; the street lights' pools,
        // decision 229 續, carry their light's colour.)
        func lots(_ scene: Map3DScene) -> Int {
            scene.chunks.reduce(0) { total, chunk in
                total + stride(from: 0, to: chunk.shadows.indices.count, by: 3)
                    .filter { chunk.shadows.vertices[Int(chunk.shadows.indices[$0])].color & 0x00FF_FFFF == 0 }.count
            }
        }
        XCTAssertLessThan(lots(real), lots(plain))
        XCTAssertGreaterThan(lots(real), lots(plain) * 3 / 4)
        // The same every time; and a blank map is as it was.
        XCTAssertEqual(Map3DScene(world: world, baseMap: tiles).chunks.map(\.mesh.vertices), real.chunks.map(\.mesh.vertices))
        let blank = GameWorld.newGame()
        XCTAssertEqual(Map3DScene(world: blank, baseMap: tiles).chunks.map(\.mesh.vertices), Map3DScene(world: blank).chunks.map(\.mesh.vertices))
    }
}
