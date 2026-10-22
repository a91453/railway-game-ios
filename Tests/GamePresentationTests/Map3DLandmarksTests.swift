import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 331: the real temples as the civic kit's, close up only.
final class Map3DLandmarksTests: XCTestCase {
    static let templesFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan_temples.json")

    /// Taipei Main Station: the middle of the map, which nothing is built
    /// on, so of the scene.
    private let anchor = GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!

    private func builder(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    /// A temple `north` and `east` metres from the anchor.
    private func temple(north: Double, east: Double, _ size: RealTemples.Size) -> RealTemples.Temple {
        RealTemples.Temple(latitude: anchor.latitudeDegrees + north / 111_000,
                           longitude: anchor.longitudeDegrees + east / (111_320 * cos(anchor.latitudeDegrees * .pi / 180)), size: size)
    }

    private func triangles(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Int {
        meshes.values.reduce(0) { $0 + $1.indices.count / 3 }
    }

    /// The app's file: every temple in Taiwan, Penghu, Kinmen, Matsu and
    /// Pratas,
    /// each a size.
    func testTheBundledTemples() throws {
        let temples = try RealTemples(data: Data(contentsOf: Self.templesFile))
        XCTAssertEqual(temples.temples.count, 19_201)
        XCTAssertEqual(temples.temples.filter { $0.size == .large }.count, 276)
        XCTAssertEqual(temples.temples.filter { $0.size == .small }.count, 1_378)
        for temple in temples.temples {
            XCTAssertTrue((20.6...26.5).contains(temple.latitude) && (116.6...122.1).contains(temple.longitude), "\(temple)")
        }
    }

    func testAFileOutOfShapeThrows() {
        XCTAssertThrowsError(try RealTemples(data: Data(#"{"temples":[2504780,12151700]}"#.utf8)))
        XCTAssertThrowsError(try RealTemples(data: Data(#"{"temples":[2504780,12151700,3]}"#.utf8)))
        XCTAssertEqual(try RealTemples(data: Data(#"{"temples":[2504780,12151700,2]}"#.utf8)).temples,
                       [RealTemples.Temple(latitude: 25.0478, longitude: 121.517, size: .large)])
    }

    /// Each size is the civic kit's, a few thousand triangles at most.
    func testTheModels() throws {
        let large = try XCTUnwrap(Map3DScene.Builder.templeModels[.large])
        XCTAssertEqual(large.triangles, Map3DCivicKit.model(for: .templePlaza).triangleCount)
        let temple = try XCTUnwrap(Map3DScene.Builder.templeModels[.temple]), small = try XCTUnwrap(Map3DScene.Builder.templeModels[.small])
        XCTAssertLessThan(small.triangles, temple.triangles)
        XCTAssertLessThan(temple.triangles, large.triangles)
        XCTAssertLessThan(large.triangles, 5_000)
        for model in [large, temple, small] {
            let bounds = try XCTUnwrap(model.mesh.bounds)
            XCTAssertEqual(bounds.max.x - bounds.min.x, model.length, accuracy: 0.5)
            XCTAssertEqual(bounds.max.z - bounds.min.z, model.width, accuracy: 0.5)
            // The hall's walls stand on the 0.12 m square and its 0.35 m
            // platform, 3.4 m tall.
            XCTAssertLessThanOrEqual(Map3DScene.Builder.templeHallFloor + model.hall.height, 0.12 + 0.35 + 3.4, "the box under the hall's roof")
        }
    }

    /// A temple of each size where it stands: its model close up, a box
    /// inside its hall from farther, and its cells kept from the city.
    func testTemplesWhereTheyStand() throws {
        let world = GameWorld.newGame(anchor: anchor)
        var builder = builder(world)
        let temples = RealTemples(temples: [temple(north: 0, east: 0, .large), temple(north: 300, east: 0, .temple),
                                            temple(north: -300, east: 200, .small)])
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let taken = builder.addTemples(temples, frame: frame, clearOf: [])
        let models = Map3DScene.Builder.templeModels
        XCTAssertEqual(triangles(builder.closeMeshes), [RealTemples.Size.large, .temple, .small].reduce(0) { $0 + models[$1]!.triangles })
        XCTAssertEqual(triangles(builder.nearMeshes), 3 * 10)
        XCTAssertEqual(triangles(builder.farMeshes), 3 * 10)
        XCTAssertTrue(builder.meshes.isEmpty, "nothing drawn at every distance")
        XCTAssertGreaterThanOrEqual(taken.count, 3)
        // On a cell already taken, none.
        var again = self.builder(world)
        XCTAssertTrue(again.addTemples(temples, frame: frame, clearOf: taken).isEmpty)
        XCTAssertTrue(again.closeMeshes.isEmpty)
    }

    /// Past a chunk's triangles, only the temples nearest the middle; past
    /// the scene's, none.
    func testTheCaps() throws {
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        // One every 70 m over 1.4 km each way.
        var many: [RealTemples.Temple] = []
        for north in stride(from: -1_400.0, through: 1_400, by: 70) {
            for east in stride(from: -1_400.0, through: 1_400, by: 70) { many.append(temple(north: north, east: east, .temple)) }
        }
        var builder = builder(world)
        _ = builder.addTemples(RealTemples(temples: many), frame: frame, clearOf: [])
        XCTAssertLessThanOrEqual(triangles(builder.closeMeshes), Map3DScene.Builder.templeTriangles)
        XCTAssertGreaterThan(triangles(builder.closeMeshes), Map3DScene.Builder.templeTriangles - 2_000)
        for mesh in builder.closeMeshes.values { XCTAssertLessThanOrEqual(mesh.indices.count / 3, Map3DScene.Builder.templeChunkTriangles) }
        // The nearest kept: every one placed within 1 km of the middle.
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        for (key, _) in builder.closeMeshes {
            let corner = Map3DPoint(Float(key.column) * Map3DScene.chunkSize, 0, Float(key.row) * Map3DScene.chunkSize)
            XCTAssertLessThan((corner - middle).length, 1_500, "\(key)")
        }
    }

    /// A temple on the track turns or gives way.
    func testNotOnTheTrack() throws {
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        // Laid as the scene lays it, a point every few metres.
        builder.trackLines = [(stride(from: Float(-200), through: 200, by: 2).map { middle + Map3DPoint($0, 0, 0) }, .surface)]
        _ = builder.addTemples(RealTemples(temples: [temple(north: 0, east: 0, .temple)]), frame: frame, clearOf: [])
        XCTAssertTrue(builder.closeMeshes.isEmpty)
        // 13 m off it, it stands, turned along the track: facing south,
        // its 22 m would come within 4 m of it.
        var off = self.builder(world)
        off.trackLines = builder.trackLines
        _ = off.addTemples(RealTemples(temples: [temple(north: 13, east: 0, .temple)]), frame: frame, clearOf: [])
        let bounds = try XCTUnwrap(off.closeMeshes.values.first?.bounds)
        XCTAssertGreaterThan(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z, "its 22 m along the track")
    }

    /// The scene asks for them on a real-world map only.
    func testTheSceneTakesThem() throws {
        let temples = RealTemples(temples: [temple(north: 0, east: 0, .large)])
        let real = Map3DScene(world: GameWorld.newGame(anchor: anchor), temples: temples)
        let none = Map3DScene(world: GameWorld.newGame(anchor: anchor))
        func close(_ scene: Map3DScene) -> Int { scene.chunks.reduce(0) { $0 + $1.close.triangleCount } }
        XCTAssertGreaterThanOrEqual(close(real) - close(none), Map3DScene.Builder.templeModels[.large]!.triangles - 2_000)
    }

    /// The kits' scenes the city draws as they are (temples, parks, the
    /// shops before a station) are lit by their vertices' normals: each
    /// one a unit long and facing out of its triangle's front, never the
    /// zero that shaded them black.
    func testTheKitScenesAreLit() throws {
        let meshes = Map3DScene.Builder.templeModels.values.map(\.mesh)
            + Map3DScene.Builder.parkModels.values.map(\.mesh)
            + Map3DScene.Builder.commerceModels.map(\.model.mesh)
        for mesh in meshes {
            XCTAssertFalse(mesh.isEmpty)
            for start in stride(from: 0, to: mesh.indices.count, by: 3) {
                let corners = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])] }
                let points = corners.map(\.position)
                guard let face = (points[1] - points[0]).cross(points[2] - points[0]).normalized else { continue }
                for corner in corners {
                    let normal = Map3DPoint(corner.nx, corner.ny, corner.nz)
                    XCTAssertEqual(normal.length, 1, accuracy: 0.01)
                    XCTAssertGreaterThan(normal.dot(face), 0.99)
                }
            }
        }
    }
}
