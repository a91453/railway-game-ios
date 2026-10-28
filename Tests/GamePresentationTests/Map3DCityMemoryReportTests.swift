import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 455: what the 3D scene's city costs, by layer, round Banqiao
/// and Taipei on the high-speed demo: as `Map3DSceneMemoryTests` builds it
/// (the demo, its heights and real railways), and as the app builds it
/// (with the base map, its city tiles, the real footprints and temples).
/// Bytes as the GPU holds them (vertices 40, indices 4); triangles; and
/// what a frame draws of the city from three distances. Only on request:
/// `MAP3D_FRAME_REPORT=1 swift test --filter Map3DCityMemoryReportTests`.
final class Map3DCityMemoryReportTests: XCTestCase {
    struct Layer {
        var vertices = 0
        var indices = 0
        var bytes: Int { vertices * MemoryLayout<Map3DVertex>.stride + indices * MemoryLayout<UInt32>.stride }
    }

    static func report(_ name: String, _ scene: Map3DScene) {
        var base = Layer(), near = Layer(), far = Layer(), close = Layer(), standIn = Layer(), shadows = Layer()
        var props = 0, signs = 0, boxes = 0, boxTriangles = 0
        for chunk in scene.chunks {
            // The base's vertices: those its indices use (the city's follow).
            let baseVertices = chunk.mesh.indices.prefix(chunk.baseIndexCount).max().map { Int($0) + 1 } ?? 0
            base.vertices += baseVertices
            base.indices += chunk.baseIndexCount
            near.vertices += chunk.mesh.vertices.count - baseVertices
            near.indices += chunk.mesh.indices.count - chunk.baseIndexCount
            far.vertices += chunk.far.vertices.count
            far.indices += chunk.far.indices.count
            close.vertices += chunk.close.vertices.count
            close.indices += chunk.close.indices.count
            standIn.vertices += chunk.standIn.vertices.count
            standIn.indices += chunk.standIn.indices.count
            shadows.vertices += chunk.shadows.vertices.count
            shadows.indices += chunk.shadows.indices.count
            boxes += chunk.farBoxes.count
            boxTriangles += chunk.farBoxes.reduce(0) { $0 + $1.triangleCount }
            props += chunk.props.count
            signs += chunk.signs.count
        }
        func mb(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_000_000) }
        let boxBytes = boxes * MemoryLayout<Map3DBoxInstance>.stride
        let total = [base, near, far, close, standIn, shadows].reduce(0) { $0 + $1.bytes } + boxBytes
        print("\(name): \(scene.chunks.count) chunks (\(scene.chunks.filter(\.coarse).count) coarse), meshes \(mb(total))")
        for (label, layer) in [("base (ground, track, roads)", base), ("city in full (.near)", near), ("city simplified (.far)", far),
                               ("close", close), ("stand-ins", standIn), ("shadows", shadows)] {
            print("  \(label): \(layer.vertices) vertices, \(layer.indices / 3) triangles, \(mb(layer.bytes))")
        }
        print("  city simplified's boxes (decision 455): \(boxes) instances, \(boxTriangles) triangles, \(mb(boxBytes))")
        print("  props \(props) instances (\(mb(props * 80))), signs \(signs)")
        frame(scene)
    }

    /// The city a frame draws from three distances over the scene's middle
    /// (the Metal view's rule: in full near the camera, simplified afar),
    /// and the sun's shadow map drawn for the same camera
    /// (``Map3DSunShadow/region(target:distance:sun:size:)``).
    static func frame(_ scene: Map3DScene) {
        for distance: Float in [280, 1_400, 5_000] {
            let camera = Map3DCamera(target: .zero, distance: distance, viewport: (402, 874))
            let matrix = camera.viewProjection
            var draws = 0, triangles = 0, cityTriangles = 0, farTriangles = 0
            for chunk in scene.chunks where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: matrix) {
                let detailed = !chunk.coarse && camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: false)
                let count = detailed ? chunk.mesh.indices.count : chunk.baseIndexCount
                if count > 0 { draws += 1; triangles += count / 3 }
                if detailed { cityTriangles += (chunk.mesh.indices.count - chunk.baseIndexCount) / 3 }
                if !detailed, !chunk.farIsEmpty { draws += 1; triangles += chunk.farTriangleCount; farTriangles += chunk.farTriangleCount }
            }
            var sun = "no sun map"
            let lighting = Map3DLighting(minute: 10 * 60)
            if let region = Map3DSunShadow.region(target: camera.target, distance: camera.distance, sun: lighting.sunDirection, size: 2048) {
                var sunDraws = 0, sunTriangles = 0, sunCity = 0
                for chunk in scene.chunks where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: region.matrix) {
                    let detailed = !chunk.coarse && camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: false)
                    let count = detailed ? chunk.mesh.indices.count : chunk.baseIndexCount
                    if count > 0 { sunDraws += 1; sunTriangles += count / 3 }
                    if detailed { sunCity += (chunk.mesh.indices.count - chunk.baseIndexCount) / 3 }
                    if !detailed, !chunk.farIsEmpty { sunDraws += 1; sunTriangles += chunk.farTriangleCount; sunCity += chunk.farTriangleCount }
                }
                sun = "sun map \(sunDraws) draws, \(sunTriangles) triangles (city \(sunCity))"
            }
            print("  frame at \(Int(distance)) m: \(draws) chunk draws, \(triangles) triangles (city in full \(cityTriangles), simplified \(farTriangles)); \(sun)")
        }
    }

    func testTheCitysMemory() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let world = try HighSpeedDemoTests.opened.get()
        let railways = try HighSpeedDemoTests.railways()
        let baseMap = Map3DFrameCostReportTests.baseMap
        let tiles = try BaseMapTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_buildings.pmtiles"), options: .alwaysMapped))
        let city = CityTileArea.areas(in: baseMap.appendingPathComponent("city"))
        let temples = try RealTemples(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_temples.json")))
        for (name, latitude, longitude) in [("Banqiao", 25.0133, 121.4637), ("Taipei", 25.0478, 121.5170)] {
            let focus = try Map3DOpenHereTests.point(latitude, longitude, in: world)
            var start = Date()
            let demo = Map3DScene(world: world, snapshot: world.railwaySnapshot(), focus: focus, heights: HighSpeedDemoTests.heights,
                                  railways: railways)
            Self.report("\(name), as Map3DSceneMemoryTests builds it (\(String(format: "%.1f", Date().timeIntervalSince(start))) s)", demo)
            start = Date()
            let app = Map3DScene(world: world, snapshot: world.railwaySnapshot(), focus: focus, baseMap: tiles, cityTiles: city,
                                 footprints: footprints, heights: HighSpeedDemoTests.heights, railways: railways, temples: temples)
            Self.report("\(name), with the app's files (\(String(format: "%.1f", Date().timeIntervalSince(start))) s)", app)
        }
    }
}
