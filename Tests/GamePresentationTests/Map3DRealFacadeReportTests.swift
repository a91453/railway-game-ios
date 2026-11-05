import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 610: what the real buildings' street fronts cost, measured on
/// decision 391's two scenes of the high-speed demo with the app's files
/// (base map, city tiles, footprints, temples): round Banqiao as the app
/// opens it, and the 16 chunks south of Miaoli (decision 375's origin,
/// −2…1 × −2…1). Bytes as the GPU holds them (vertices 40, indices 4),
/// triangles and the time to build. Only on request:
/// `MAP3D_FACADE_REPORT=1 swift test --filter Map3DRealFacadeReportTests`.
final class Map3DRealFacadeReportTests: XCTestCase {
    private struct Count {
        var bytes = 0, triangles = 0, closeTriangles = 0, facadeBytes = 0, facadeTriangles = 0, busiestFacade = 0, busiestClose = 0
    }

    private static func count(_ chunks: [Map3DScene.Chunk]) -> Count {
        var count = Count()
        for chunk in chunks {
            for mesh in [chunk.mesh, chunk.far, chunk.close, chunk.standIn, chunk.shadows, chunk.facade] {
                count.bytes += mesh.vertices.count * MemoryLayout<Map3DVertex>.stride + mesh.indices.count * MemoryLayout<UInt32>.stride
                count.triangles += mesh.triangleCount
            }
            count.bytes += chunk.farBoxes.count * MemoryLayout<Map3DBoxInstance>.stride
            count.triangles += chunk.farBoxes.reduce(0) { $0 + $1.triangleCount }
            count.closeTriangles += chunk.close.triangleCount
            count.busiestClose = max(count.busiestClose, chunk.close.triangleCount)
            count.facadeBytes += chunk.facade.vertices.count * MemoryLayout<Map3DVertex>.stride + chunk.facade.indices.count * MemoryLayout<UInt32>.stride
            count.facadeTriangles += chunk.facade.triangleCount
            count.busiestFacade = max(count.busiestFacade, chunk.facade.triangleCount)
        }
        return count
    }

    private static func print(_ name: String, _ count: Count, seconds: Double) {
        Swift.print("\(name): \(count.bytes) bytes, \(count.triangles) triangles, built in \(String(format: "%.1f", seconds)) s; "
                    + "close \(count.closeTriangles) triangles (busiest chunk \(count.busiestClose)); "
                    + "street fronts \(count.facadeBytes) bytes, \(count.facadeTriangles) triangles (busiest chunk \(count.busiestFacade))")
    }

    func testWhatTheStreetFrontsCost() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FACADE_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FACADE_REPORT=1.") }
        let world = try HighSpeedDemoTests.opened.get()
        let railways = try HighSpeedDemoTests.railways()
        let baseMap = Map3DFrameCostReportTests.baseMap
        let tiles = try BaseMapTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_buildings.pmtiles"), options: .alwaysMapped))
        let city = CityTileArea.areas(in: baseMap.appendingPathComponent("city"))
        let temples = try RealTemples(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_temples.json")))
        let banqiao = try Map3DOpenHereTests.point(25.0133, 121.4637, in: world)
        var start = Date()
        let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot(), focus: banqiao, baseMap: tiles, cityTiles: city,
                               footprints: footprints, heights: HighSpeedDemoTests.heights, railways: railways, temples: temples)
        Self.print("Banqiao", Self.count(scene.chunks), seconds: Date().timeIntervalSince(start))
        let snapshot = world.railwaySnapshot()
        let origin = (x: 179_006 * Map3DScene.Builder.metre, y: 68_767 * Map3DScene.Builder.metre)
        let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: WorldRegion(bounds: world.bounds))
        let keys = (-2...1).flatMap { row in (-2...1).map { Map3DStreaming.Key(column: $0, row: row) } }
        start = Date()
        let chunks = Map3DScene.chunks(keys, of: grid, world: world, snapshot: snapshot, baseMap: tiles, cityTiles: city, footprints: footprints,
                                       heights: HighSpeedDemoTests.heights, railways: railways, temples: temples)
        Self.print("Miaoli south, 16 chunks", Self.count(chunks), seconds: Date().timeIntervalSince(start))
    }
}
