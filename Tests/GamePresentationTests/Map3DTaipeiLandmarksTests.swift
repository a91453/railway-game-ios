import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 370 (step 2): Taipei 101 and Taipei Main Station in the model
/// look, where they stand.
final class Map3DTaipeiLandmarksTests: XCTestCase {
    /// Taipei Main Station: the middle of the map, so of the scene; 101 is
    /// 4.8 km off, outside a new game's scene.
    private let anchor = GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!

    private func builder(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    private func triangles(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Int {
        meshes.values.reduce(0) { $0 + $1.indices.count / 3 }
    }

    private static let wall = Map3DColor.rgb(0xF5F1E9)

    /// The two as OSM has their heights: 101 508 m to its spire, the
    /// station's roof 30 m; each within the ground it clears, lit by
    /// unit normals, drawn with the line patterns; from afar, fewer
    /// triangles.
    func testTheModels() {
        let layers: Set<Float> = [Map3DVertex.plain, Map3DVertex.curtainGlass, Map3DVertex.roofTiles, Map3DVertex.floorLines]
        for landmark in Map3DTaipeiLandmark.allCases {
            let full = landmark.model(full: true), far = landmark.model(full: false)
            XCTAssertLessThan(far.indices.count, full.indices.count * 2 / 3, "\(landmark)")
            for model in [full, far] {
                let top = model.vertices.map(\.z).max() ?? 0
                XCTAssertEqual(top, landmark == .taipei101 ? 508 : 30, accuracy: 0.01, "\(landmark)")
                XCTAssertEqual(model.vertices.map(\.z).min(), 0)
                for vertex in model.vertices {
                    XCTAssertLessThanOrEqual(abs(vertex.x), landmark.clearing.x)
                    XCTAssertLessThanOrEqual(abs(vertex.y), landmark.clearing.y)
                    XCTAssertEqual(Map3DPoint(vertex.nx, vertex.ny, vertex.nz).length, 1, accuracy: 0.001)
                    XCTAssertTrue(layers.contains(vertex.layer), "\(vertex.layer)")
                }
                XCTAssertTrue(model.indices.allSatisfy { Int($0) < model.vertices.count })
            }
            let used = Set(full.vertices.map(\.layer))
            XCTAssertTrue(used.isSuperset(of: landmark == .taipei101 ? [Map3DVertex.curtainGlass, Map3DVertex.floorLines]
                                                                   : [Map3DVertex.curtainGlass, Map3DVertex.roofTiles]), "\(landmark)")
        }
    }

    /// Stood where it is, the station is in full close by and simpler from
    /// afar, in its own colours, and clears the ground under it.
    func testWhereItStands() throws {
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let built = builder.addTaipeiLandmarks(frame: frame)
        let station = Map3DTaipeiLandmark.taipeiMainStation
        XCTAssertEqual(Set(built.keys), [station])
        let taken = try XCTUnwrap(built[station])
        XCTAssertEqual(triangles(builder.nearMeshes), station.model(full: true).indices.count / 3)
        XCTAssertEqual(triangles(builder.farMeshes), station.model(full: false).indices.count / 3)
        XCTAssertTrue(builder.closeMeshes.isEmpty)
        XCTAssertTrue(builder.keptColours.contains(Self.wall))
        // Its 184 m by 160 m of ground: three 64 m cells each way at least.
        XCTAssertGreaterThanOrEqual(taken.count, 9)
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        XCTAssertTrue(taken.contains(builder.chunk(of: middle)))
        let bounds = try XCTUnwrap(builder.nearMeshes.values.first?.bounds)
        XCTAssertEqual((bounds.min.x + bounds.max.x) / 2, middle.x, accuracy: 15)
        XCTAssertEqual((bounds.min.z + bounds.max.z) / 2, middle.z, accuracy: 15)
    }

    /// Track on the ground through it: not built. Under it, in a tunnel as
    /// the real station's: built.
    func testNotOnTheTrack() throws {
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        let line = stride(from: Float(-300), through: 300, by: 2).map { middle + Map3DPoint($0, 0, 30) }
        builder.trackLines = [(line, .surface)]
        XCTAssertTrue(builder.addTaipeiLandmarks(frame: frame).isEmpty)
        XCTAssertTrue(builder.nearMeshes.isEmpty)
        var under = self.builder(world)
        under.trackLines = [(line, .tunnel)]
        XCTAssertFalse(under.addTaipeiLandmarks(frame: frame).isEmpty)
        // 120 m off, clear of it.
        var beside = self.builder(world)
        beside.trackLines = [(line.map { $0 + Map3DPoint(0, 0, 90) }, .surface)]
        XCTAssertFalse(beside.addTaipeiLandmarks(frame: frame).isEmpty)
    }

    /// A station of the player's beside it is built as Taipei Main
    /// Station, so the station kit would draw its own Taipei there: where
    /// the landmark stands, it draws none.
    func testTheKitsTaipeiGivesWay() throws {
        let start = GameWorld.newGame(anchor: anchor)
        let empty = Map3DScene(world: start)
        let off = Int64(150 * WorldCoordinate.unitsPerMetre), across = Int64(3_000 * WorldCoordinate.unitsPerMetre)
        let y = Int64(empty.originY) - off, x = Int64(empty.originX)
        let world = try newGameLine(through: [PlanPoint(x: x - across, y: y), PlanPoint(x: x, y: y), PlanPoint(x: x + across, y: y)], in: start)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        // The kit's buildings: Taipei's, and the line's two other
        // stations' 3 km off.
        var kit = builder
        let all = kit.addStations(snapshot, frame: frame)
        XCTAssertEqual(Set(builder.addTaipeiLandmarks(frame: frame).keys), [.taipeiMainStation])
        let others = builder.addStations(snapshot, frame: frame, drawnElsewhere: [.taipei])
        XCTAssertTrue(others.isStrictSubset(of: all))
        let middle = builder.chunk(of: builder.point(x: frame.middleX, y: frame.middleY, height: 0))
        // Within 8 cells (512 m) of the middle's.
        func near(_ cells: Set<Map3DScene.ChunkKey>) -> Bool {
            cells.contains { abs($0.column - middle.column) <= 8 && abs($0.row - middle.row) <= 8 }
        }
        XCTAssertTrue(near(all), "the kit's Taipei, by the middle")
        XCTAssertFalse(near(others))
        // The scene: the landmark's walls, all of them.
        let station = Map3DTaipeiLandmark.taipeiMainStation
        let expected = (station.model(full: true).vertices + station.model(full: false).vertices).filter { $0.color == Self.wall }.count
        XCTAssertEqual(walls(Map3DScene(world: world)), expected)
    }

    private func walls(_ scene: Map3DScene) -> Int {
        scene.chunks.reduce(0) { $0 + ($1.mesh.vertices + $1.far.vertices).filter { $0.color == Self.wall }.count }
    }

    /// The scene draws it on a real-world map, its colours as they are
    /// (not paled), and none on a map of nowhere.
    func testTheSceneTakesIt() {
        let station = Map3DTaipeiLandmark.taipeiMainStation
        let expected = (station.model(full: true).vertices + station.model(full: false).vertices).filter { $0.color == Self.wall }.count
        XCTAssertGreaterThan(expected, 0)
        XCTAssertEqual(walls(Map3DScene(world: GameWorld.newGame(anchor: anchor))), expected)
        XCTAssertEqual(walls(Map3DScene(world: GameWorld.newGame())), 0)
    }
}
