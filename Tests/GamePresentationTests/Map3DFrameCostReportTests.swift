import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Measures, on Linux, the 3D map's per-frame work that GamePresentation
/// does for the Metal view (`Map3DMetalView.draw`): which chunks are in
/// view and in how much detail, the trains' frame and the street life,
/// on the real-world Taipei map seen whole from far out, where the owner's
/// iPhone 17 Pro spent 16.6 ms of CPU a frame (2026-10-21,
/// PLAYER_FEEDBACK 72.1). Only on request: `MAP3D_FRAME_REPORT=1`.
final class Map3DFrameCostReportTests: XCTestCase {
    static let baseMap = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Resources/BaseMap")

    func testTheFarTaipeiFrame() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!)
        let tiles = try BaseMapTiles(data: Data(contentsOf: Self.baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let empty = Map3DScene(world: world, baseMap: tiles, cityTiles: [])
        // A line 10 km across the city, so the scene reaches its widest
        // (``Map3DScene/reach``), as the owner's whole-Taipei game did.
        let across = Int64(5_000 * WorldCoordinate.unitsPerMetre)
        let middle = (x: Int64(empty.originX), y: Int64(empty.originY))
        let line = try LineBuilder.line(through: [PlanPoint(x: middle.x - across, y: middle.y - across / 2),
                                                  PlanPoint(x: middle.x, y: middle.y),
                                                  PlanPoint(x: middle.x + across, y: middle.y + across / 2)], in: world)
        let built = Date()
        let scene = Map3DScene(world: line, baseMap: tiles, cityTiles: CityTileArea.areas(in: Self.baseMap.appendingPathComponent("city")))
        print("scene: \(scene.chunks.count) chunks, \(scene.triangleCount) triangles, built in \(String(format: "%.1f", Date().timeIntervalSince(built))) s")
        let width = Float((scene.region.maxX - scene.region.minX) / Double(WorldCoordinate.unitsPerMetre))
        let height = Float((scene.region.maxY - scene.region.minY) / Double(WorldCoordinate.unitsPerMetre))
        for (name, camera) in [
            ("far (the 3D button)", Map3DCamera(target: .zero, distance: max(width, height) * 0.9, viewport: (402, 874))),
            ("near (handed over)", Map3DCamera(target: .zero, distance: 280, viewport: (402, 874))),
        ] {
            report(name, camera: camera, scene: scene)
        }
    }

    /// Why Taipei's middle looks bare in 3D (2026-10-21, the owner's
    /// screenshot): of the city's lots round Taipei Main Station, how many
    /// stand, and how many the real map's roads, water and parks take
    /// (decision 234), with no real buildings there (decision 239 has only
    /// Kaohsiung and Taichung).
    func testTaipeiLots() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!)
        let tiles = try BaseMapTiles(data: Data(contentsOf: Self.baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let real = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: originX, originY: originY)
        builder.addGround(water: false)
        let taken = builder.addBaseMap(real)
        let lots = CitySkyline(world: world).lots(in: region)
        let built = lots.filter { !$0.isOpenGround }
        let free = built.filter { !taken.contains(Map3DScene.ChunkKey(column: $0.column, row: $0.row)) }
        let areas = CityTileArea.areas(in: Self.baseMap.appendingPathComponent("city")).map(\.id)
        print("Taipei: cell \(Land.cellLength / WorldCoordinate.unitsPerMetre) m; \(lots.count) lots in the scene, \(built.count) with buildings, "
            + "\(free.count) left once the real roads, water and parks take theirs (\(taken.count) cells taken); real building areas: \(areas)")
        var byDensity: [Int: (all: Int, left: Int)] = [:]
        for lot in built {
            let left = taken.contains(Map3DScene.ChunkKey(column: lot.column, row: lot.row)) ? 0 : 1
            byDensity[lot.density, default: (0, 0)].all += 1
            byDensity[lot.density, default: (0, 0)].left += left
        }
        for density in byDensity.keys.sorted() { print("  density \(density): \(byDensity[density]!.all) lots, \(byDensity[density]!.left) left") }
    }

    private func report(_ name: String, camera: Map3DCamera, scene: Map3DScene) {
        let frames = 300
        var detailed = [Bool](repeating: false, count: scene.chunks.count)
        var closeUp = detailed
        var visible = 0, drawn = 0
        let culling = time(frames) {
            let matrix = camera.viewProjection
            visible = 0
            drawn = 0
            for index in scene.chunks.indices {
                let chunk = scene.chunks[index]
                detailed[index] = camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: detailed[index])
                closeUp[index] = detailed[index] && camera.wantsClose(minimum: chunk.minimum, maximum: chunk.maximum, wasClose: closeUp[index])
                if Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: matrix) {
                    visible += 1
                    drawn += (detailed[index] ? chunk.mesh.triangleCount : chunk.baseIndexCount / 3 + chunk.far.triangleCount)
                }
            }
        }
        // The same with `sees` as it was (arrays for each corner).
        let before = time(frames) {
            let matrix = camera.viewProjection
            for index in scene.chunks.indices {
                let chunk = scene.chunks[index]
                _ = camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: detailed[index])
                _ = Self.seesAsBefore(chunk.minimum, chunk.maximum, matrix)
            }
        }
        var people = 0
        let life = time(frames) {
            people = scene.streetLife.frame(target: camera.target, distance: camera.distance, time: 1_000, lights: 1, detail: .full,
                                            activity: Map3DStreetLife.Activity()).instances.count
        }
        let models = Map3DModelPack.standard
        let trains = time(frames) {
            _ = Map3DTrains.frame(TrainMotion(), progress: 1, heights: Map3DTrains.Heights(), in: scene, models: models, eye: camera.eye)
        }
        print("\(name): distance \(Int(camera.distance)) m, \(visible) of \(scene.chunks.count) chunks in view, \(drawn) triangles, \(people) street instances")
        print("  per frame: culling \(ms(culling)) ms (with sees as before \(ms(before)) ms), street life \(ms(life)) ms, trains \(ms(trains)) ms")
    }

    static func seesAsBefore(_ minimum: Map3DPoint, _ maximum: Map3DPoint, _ matrix: Map3DMatrix) -> Bool {
        var outside = [true, true, true, true, true, true]
        for corner in 0..<8 {
            let p = [corner & 1 == 0 ? minimum.x : maximum.x, corner & 2 == 0 ? minimum.y : maximum.y, corner & 4 == 0 ? minimum.z : maximum.z, 1]
            var c = [Float](repeating: 0, count: 4)
            for row in 0..<4 {
                for k in 0..<4 { c[row] += matrix[row, k] * p[k] }
            }
            let (x, y, z, w) = (c[0], c[1], c[2], c[3])
            let sides = [x < -w, x > w, y < -w, y > w, z < 0, z > w]
            for side in 0..<6 where !sides[side] { outside[side] = false }
        }
        return !outside.contains(true)
    }

    private func time(_ frames: Int, _ body: () -> Void) -> Double {
        body()
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<frames { body() }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(frames) / 1e6
    }

    private func ms(_ value: Double) -> String { String(format: "%.3f", value) }
}
