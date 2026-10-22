import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 331: the park kit's scenes in a real-world map's parks, close up
/// only.
final class Map3DParksTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }

    private let anchor = GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!

    private func builder(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    private func triangles(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Int {
        meshes.values.reduce(0) { $0 + $1.indices.count / 3 }
    }

    /// A park whose outline is `ring` (scene metres, x and z), on one tile
    /// as big as the scene.
    private func park(_ ring: [(Double, Double)]) -> Map3DBaseMap.Area {
        Map3DBaseMap.Area(cover: .park, rings: [ring.map { Map3DBaseMap.Point(x: $0.0, z: $0.1) }],
                          bounds: Map3DBaseMap.Bounds(minX: -5_000, minZ: -5_000, maxX: 5_000, maxZ: 5_000))
    }

    /// A square park `side` metres across round (`x`, `z`) from the scene's
    /// middle.
    private func square(_ builder: Map3DScene.Builder, x: Double, z: Double, side: Double) -> Map3DBaseMap.Area {
        let middle = builder.point(x: (builder.region.minX + builder.region.maxX) / 2, y: (builder.region.minY + builder.region.maxY) / 2, height: 0)
        let cx = Double(middle.x) + x, cz = Double(middle.z) + z, h = side / 2
        return park([(cx - h, cz - h), (cx + h, cz - h), (cx + h, cz + h), (cx - h, cz + h)])
    }

    /// Each scene is the park kit's, its ground the size it says.
    func testTheModels() throws {
        for (example, model) in Map3DScene.Builder.parkModels {
            XCTAssertEqual(model.triangles, Map3DParkKit.model(for: example).triangleCount, "\(example)")
            XCTAssertLessThan(model.triangles, Map3DScene.Builder.parkChunkTriangles, "\(example)")
            let bounds = try XCTUnwrap(model.mesh.bounds)
            XCTAssertEqual(bounds.min.x, -model.length / 2, accuracy: 0.5, "\(example)")
            XCTAssertEqual(bounds.max.x, model.length / 2, accuracy: 0.5, "\(example)")
            XCTAssertEqual(bounds.min.z, -model.width / 2, accuracy: 0.5, "\(example)")
            XCTAssertEqual(bounds.max.z, model.width / 2, accuracy: 0.5, "\(example)")
        }
        XCTAssertEqual(Set(Map3DScene.Builder.parkModels.keys), Set(Map3DParkKit.Example.allCases))
    }

    /// A big park gets its pond or its sports ground, a middling one its
    /// playground, a small one its pocket garden; one too small, none.
    func testAParkOfEachSize() throws {
        let world = GameWorld.newGame(anchor: anchor)
        var builder = builder(world)
        let models = Map3DScene.Builder.parkModels
        let map = Map3DBaseMap(areas: [square(builder, x: 0, z: 0, side: 200), square(builder, x: 600, z: 0, side: 90),
                                       square(builder, x: 0, z: 600, side: 40), square(builder, x: 600, z: 600, side: 16)])
        builder.addParks(map, clearOf: [])
        let close = triangles(builder.closeMeshes)
        let small = models[.playground]!.triangles + models[.pocketPark]!.triangles
        XCTAssertTrue([models[.gardenWalk]!.triangles + small, models[.sportsGround]!.triangles + small].contains(close), "\(close)")
        XCTAssertTrue(builder.nearMeshes.isEmpty)
        XCTAssertTrue(builder.farMeshes.isEmpty)
        XCTAssertTrue(builder.meshes.isEmpty, "nothing drawn at every distance")
        // Its ground over the park's green.
        let lowest = builder.closeMeshes.values.compactMap(\.bounds).map(\.min.y).min()
        XCTAssertEqual(try XCTUnwrap(lowest), Map3DScene.Builder.lift(of: .park), accuracy: 0.01)
    }

    /// Not on a cell another thing holds, nor across the track.
    func testNotOnACellTakenNorTheTrack() throws {
        let world = GameWorld.newGame(anchor: anchor)
        var builder = builder(world)
        let map = Map3DBaseMap(areas: [square(builder, x: 0, z: 0, side: 60)])
        builder.addParks(map, clearOf: [])
        let mesh = try XCTUnwrap(builder.closeMeshes.values.first?.bounds)
        let corners = [Map3DPoint(mesh.min.x, 0, mesh.min.z), Map3DPoint(mesh.max.x, 0, mesh.max.z)]
        var taken = self.builder(world)
        taken.addParks(map, clearOf: taken.cells(under: corners))
        XCTAssertTrue(taken.closeMeshes.isEmpty)

        var track = self.builder(world)
        let middle = track.point(x: (track.region.minX + track.region.maxX) / 2, y: (track.region.minY + track.region.maxY) / 2, height: 0)
        track.trackLines = [(stride(from: Float(-200), through: 200, by: 2).map { middle + Map3DPoint($0, 0, 0) }, .surface)]
        track.addParks(map, clearOf: [])
        for bounds in track.closeMeshes.values.compactMap(\.bounds) {
            XCTAssertTrue(bounds.min.z > middle.z + 4 || bounds.max.z < middle.z - 4, "4 m from the track")
        }
    }

    /// An L-shaped park, its outline's middle outside it: the scene stands
    /// inside, in one of its arms.
    func testInsideItsOutline() throws {
        let world = GameWorld.newGame(anchor: anchor)
        var builder = builder(world)
        let middle = builder.point(x: (builder.region.minX + builder.region.maxX) / 2, y: (builder.region.minY + builder.region.maxY) / 2, height: 0)
        let x = Double(middle.x), z = Double(middle.z)
        let outline = [(x, z), (x + 120, z), (x + 120, z + 30), (x + 30, z + 30), (x + 30, z + 120), (x, z + 120)]
        builder.addParks(Map3DBaseMap(areas: [park(outline)]), clearOf: [])
        let bounds = try XCTUnwrap(builder.closeMeshes.values.first?.bounds)
        let polygon = [outline.map { Map3DPoint(Float($0.0), 0, Float($0.1)) }]
        for corner in [Map3DPoint(bounds.min.x, 0, bounds.min.z), Map3DPoint(bounds.max.x, 0, bounds.min.z),
                       Map3DPoint(bounds.max.x, 0, bounds.max.z), Map3DPoint(bounds.min.x, 0, bounds.max.z)] {
            XCTAssertTrue(Map3DScene.Builder.inside(corner, polygon), "\(corner)")
        }
    }

    /// Two parks nearer than the spacing (or one park's two tiles) get one
    /// scene; past the scene's triangles and a chunk's, none.
    func testTheSpacingAndTheCaps() throws {
        let world = GameWorld.newGame(anchor: anchor)
        var two = builder(world)
        two.addParks(Map3DBaseMap(areas: [square(two, x: 0, z: 0, side: 40), square(two, x: 80, z: 0, side: 40)]), clearOf: [])
        XCTAssertEqual(triangles(two.closeMeshes), Map3DScene.Builder.parkModels[.pocketPark]!.triangles)

        var many = builder(world)
        var areas: [Map3DBaseMap.Area] = []
        for north in stride(from: -2_400.0, through: 2_400, by: 160) {
            for east in stride(from: -2_400.0, through: 2_400, by: 160) { areas.append(square(many, x: east, z: north, side: 200)) }
        }
        many.addParks(Map3DBaseMap(areas: areas), clearOf: [])
        XCTAssertLessThanOrEqual(triangles(many.closeMeshes), Map3DScene.Builder.parkTriangles)
        XCTAssertGreaterThan(triangles(many.closeMeshes), Map3DScene.Builder.parkTriangles - 6_000)
        for mesh in many.closeMeshes.values { XCTAssertLessThanOrEqual(mesh.indices.count / 3, Map3DScene.Builder.parkChunkTriangles) }
    }

    /// Round Taipei Main Station, the base map's parks (228 Peace Park
    /// among them) get their scenes; a map not of the real world, none.
    func testTheSceneTakesThem() throws {
        let tiles = try Self.tiles.get()
        let world = GameWorld.newGame(anchor: anchor)
        var builder = builder(world)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let map = Map3DBaseMap(tiles: tiles, frame: frame, region: builder.region, originX: builder.originX, originY: builder.originY)
        XCTAssertFalse(map.areas.filter { $0.cover == .park }.isEmpty)
        builder.addParks(map, clearOf: [])
        let placed = triangles(builder.closeMeshes)
        XCTAssertGreaterThan(placed, 10_000)
        XCTAssertLessThanOrEqual(placed, Map3DScene.Builder.parkTriangles)

        func close(_ scene: Map3DScene) -> Int { scene.chunks.reduce(0) { $0 + $1.close.triangleCount } }
        let real = Map3DScene(world: world, baseMap: tiles)
        XCTAssertGreaterThan(close(real), placed / 2)
    }
}
