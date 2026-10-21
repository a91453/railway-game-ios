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

    /// What the GPU is given to draw (2026-10-21, the owner's second
    /// screenshots: GPU 10–12 ms on Taipei from near and far), by layer:
    /// triangles, and how many times over each layer covers the screen
    /// (each triangle clipped to the view, its area in pixels of an iPhone
    /// 17 Pro's 3× screen, summed, over the screen's). Opaque layers cost
    /// little when covered twice (Apple's GPUs shade only the nearest
    /// opaque surface of a pixel); the shadows and street lights' pools,
    /// blended over them, are shaded every time.
    func testTheGPUBudget() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let scene = try Self.taipeiScene()
        let width = Float((scene.region.maxX - scene.region.minX) / Double(WorldCoordinate.unitsPerMetre))
        let height = Float((scene.region.maxY - scene.region.minY) / Double(WorldCoordinate.unitsPerMetre))
        let models = Map3DModelPack.standard
        for (name, distance) in [("far", max(width, height) * 0.9), ("middle", 1_400), ("middle", 800), ("near", 280)] as [(String, Float)] {
            let camera = Map3DCamera(target: .zero, distance: distance, viewport: (402, 874))
            let matrix = camera.viewProjection
            let screen = Double(402 * 3) * Double(874 * 3)
            var layers: [(name: String, triangles: Int, pixels: Double, draws: Int)] = []
            func add(_ name: String, _ triangles: Int, _ pixels: Double, _ draws: Int) {
                if let at = layers.firstIndex(where: { $0.name == name }) {
                    layers[at].triangles += triangles
                    layers[at].pixels += pixels
                    layers[at].draws += draws
                } else {
                    layers.append((name, triangles, pixels, draws))
                }
            }
            var propTriangles: [String: Int] = [:]
            for chunk in scene.chunks where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: matrix) {
                let detailed = camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: false)
                let closeUp = detailed && camera.wantsClose(minimum: chunk.minimum, maximum: chunk.maximum, wasClose: false)
                let base = Self.pixels(chunk.mesh, upTo: chunk.baseIndexCount, through: matrix)
                add("ground, track, roads", chunk.baseIndexCount / 3, base, 0)
                if detailed {
                    let all = Self.pixels(chunk.mesh, upTo: chunk.mesh.indices.count, through: matrix)
                    add("city (full)", chunk.mesh.triangleCount - chunk.baseIndexCount / 3, all - base, 1)
                } else {
                    add("city (far)", chunk.far.triangleCount, Self.pixels(chunk.far, upTo: chunk.far.indices.count, through: matrix), 1)
                }
                if closeUp {
                    add("close-up things", chunk.close.triangleCount, Self.pixels(chunk.close, upTo: chunk.close.indices.count, through: matrix), 1)
                }
                if detailed {
                    var drawn = Set<Int>()
                    for prop in chunk.props where models.models.indices.contains(prop.model) {
                        let model = models.models[prop.model]
                        drawn.insert(prop.model)
                        propTriangles[model.name, default: 0] += model.triangleCount
                        add("street furniture", model.triangleCount, Self.pixels(model.vertices, prop.transform, through: matrix), 0)
                    }
                    add("street furniture", 0, 0, drawn.count)
                }
                if !chunk.shadows.isEmpty {
                    add("shadows and light pools (blended)", chunk.shadows.triangleCount,
                        Self.pixels(chunk.shadows, upTo: chunk.shadows.indices.count, through: matrix), 1)
                }
            }
            let life = scene.streetLife.frame(target: camera.target, distance: camera.distance, time: 1_000, lights: 1, detail: .full,
                                              activity: Map3DStreetLife.Activity())
            var lifeModels = Set<Int>()
            for instance in life.instances where models.models.indices.contains(instance.model) {
                lifeModels.insert(instance.model)
                add("people and vehicles", models.models[instance.model].triangleCount,
                    Self.pixels(models.models[instance.model].vertices, instance.transform, through: matrix), 0)
            }
            add("people and vehicles", 0, 0, lifeModels.count)
            let triangles = layers.reduce(0) { $0 + $1.triangles }
            let draws = layers.reduce(0) { $0 + $1.draws }
            print("\(name) \(Int(distance)) m (tilt \(String(format: "%.0f", camera.tilt * 180 / .pi))°): \(triangles) triangles, about \(draws) draws")
            for layer in layers {
                print("  \(layer.name): \(layer.triangles) triangles, covers the screen \(String(format: "%.2f", layer.pixels / screen))×, \(layer.draws) draws")
            }
            let heaviest = propTriangles.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key) \($0.value)" }
            if !heaviest.isEmpty { print("  heaviest furniture: \(heaviest.joined(separator: ", "))") }
        }
    }

    /// Decision 314: with its line's colour bands, as the app builds it,
    /// unless `bands` is false.
    static func taipeiScene(bands: Bool = true) throws -> Map3DScene {
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!)
        let tiles = try BaseMapTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let empty = Map3DScene(world: world, baseMap: tiles, cityTiles: [])
        let across = Int64(5_000 * WorldCoordinate.unitsPerMetre)
        let middle = (x: Int64(empty.originX), y: Int64(empty.originY))
        let line = try LineBuilder.line(through: [PlanPoint(x: middle.x - across, y: middle.y - across / 2),
                                                  PlanPoint(x: middle.x, y: middle.y),
                                                  PlanPoint(x: middle.x + across, y: middle.y + across / 2)], in: world)
        return Map3DScene(world: line, baseMap: tiles, cityTiles: CityTileArea.areas(in: baseMap.appendingPathComponent("city")),
                          lineBands: bands ? Map3DLineBands(world: line, palette: .standard) : nil)
    }

    /// Decision 314: what the line's colour bands add, in the near meshes
    /// only (no draw call of their own); the trains' labels are a few
    /// SwiftUI views over the map and add no triangles.
    func testTheLineBandsCost() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let plain = try Self.taipeiScene(bands: false), banded = try Self.taipeiScene()
        func near(_ scene: Map3DScene) -> Int { scene.chunks.reduce(0) { $0 + $1.mesh.triangleCount - $1.baseIndexCount / 3 } }
        func far(_ scene: Map3DScene) -> Int { scene.chunks.reduce(0) { $0 + $1.baseIndexCount / 3 + $1.far.triangleCount } }
        print("bands: near \(near(plain)) → \(near(banded)) triangles (+\(near(banded) - near(plain))), far \(far(plain)) → \(far(banded))")
        XCTAssertEqual(far(plain), far(banded))
    }

    /// The pixels the first `count` indices' triangles of `mesh` cover on a
    /// 3× 402 × 874 screen, each clipped to the view.
    static func pixels(_ mesh: Map3DMesh, upTo count: Int, through matrix: Map3DMatrix) -> Double {
        var total = 0.0
        let vertices = mesh.vertices, indices = mesh.indices
        var at = 0
        while at + 2 < count {
            let a = vertices[Int(indices[at])], b = vertices[Int(indices[at + 1])], c = vertices[Int(indices[at + 2])]
            total += area(clip(a.x, a.y, a.z, matrix), clip(b.x, b.y, b.z, matrix), clip(c.x, c.y, c.z, matrix))
            at += 3
        }
        return total
    }

    /// The same for a model's triangles placed by `transform` (column by
    /// column).
    static func pixels(_ vertices: [Map3DVertex], _ t: [Float], through matrix: Map3DMatrix) -> Double {
        var total = 0.0
        var at = 0
        func placed(_ v: Map3DVertex) -> SIMD4<Float> {
            clip(t[0] * v.x + t[4] * v.y + t[8] * v.z + t[12], t[1] * v.x + t[5] * v.y + t[9] * v.z + t[13],
                 t[2] * v.x + t[6] * v.y + t[10] * v.z + t[14], matrix)
        }
        while at + 2 < vertices.count {
            total += area(placed(vertices[at]), placed(vertices[at + 1]), placed(vertices[at + 2]))
            at += 3
        }
        return total
    }

    static func clip(_ x: Float, _ y: Float, _ z: Float, _ matrix: Map3DMatrix) -> SIMD4<Float> {
        let m = matrix.columns
        return SIMD4(m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13],
                     m[2] * x + m[6] * y + m[10] * z + m[14], m[3] * x + m[7] * y + m[11] * z + m[15])
    }

    /// The triangle's area on screen in pixels, clipped (Sutherland–Hodgman)
    /// to the view's four sides and near plane; either facing counts.
    static func area(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ c: SIMD4<Float>) -> Double {
        var polygon = [a, b, c]
        let planes: [(SIMD4<Float>) -> Float] = [{ $0.w + $0.x }, { $0.w - $0.x }, { $0.w + $0.y }, { $0.w - $0.y }, { $0.z }, { $0.w - $0.z }]
        for side in planes {
            var kept: [SIMD4<Float>] = []
            for index in polygon.indices {
                let p = polygon[index], q = polygon[(index + 1) % polygon.count]
                let dp = side(p), dq = side(q)
                if dp >= 0 { kept.append(p) }
                if (dp >= 0) != (dq >= 0) { kept.append(p + (q - p) * (dp / (dp - dq))) }
            }
            polygon = kept
            if polygon.count < 3 { return 0 }
        }
        let width = 402.0 * 3, height = 874.0 * 3
        var sum = 0.0
        for index in polygon.indices {
            let p = polygon[index], q = polygon[(index + 1) % polygon.count]
            let px = Double(p.x / p.w) * width / 2, py = Double(p.y / p.w) * height / 2
            let qx = Double(q.x / q.w) * width / 2, qy = Double(q.y / q.w) * height / 2
            sum += px * qy - qx * py
        }
        return abs(sum) / 2
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
