import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 368 (the owner's iPhone 17 Pro, 83.1: following a train into
/// the 3D map killed the app for memory, a per-process limit of 3.4 GB).
/// A class of its own, as it builds a whole scene (about a minute on CI)
/// besides opening the high-speed demo.
final class Map3DSceneMemoryTests: XCTestCase {
    /// The scene round Banqiao, the demo's busiest city, as the app builds
    /// it, is under 1 GB of meshes (on the GPU once more). All of it with
    /// the city in full, it was 1.8 GB.
    func testThe3DMapRoundBanqiaoFitsAPhone() throws {
        let world = try HighSpeedDemoTests.opened.get()
        let banqiao = try Map3DOpenHereTests.point(25.0133, 121.4637, in: world)
        let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot(), focus: banqiao,
                               heights: HighSpeedDemoTests.heights, railways: try HighSpeedDemoTests.railways())
        var bytes = 0
        for chunk in scene.chunks {
            for mesh in [chunk.mesh, chunk.far, chunk.close, chunk.shadows] {
                bytes += mesh.vertices.count * MemoryLayout<Map3DVertex>.stride + mesh.indices.count * MemoryLayout<UInt32>.stride
            }
        }
        XCTAssertLessThan(bytes, 1_000_000_000)
        let coarse = scene.chunks.filter { $0.coarse }
        XCTAssertGreaterThan(coarse.count, scene.chunks.count / 2, "the city in full round the middle only")
        XCTAssertFalse(coarse.contains { Map3DStreaming.distance(of: Map3DStreaming.Key(column: $0.column, row: $0.row), to: .zero) == 0 })
    }

    /// Decision 389: with the base map, the real footprints round Banqiao
    /// in place of the game's own houses cost no more, near or far, than
    /// those houses did (decision 386's budget), and the scene stays under
    /// 1 GB. It builds the scene twice with the base map (nearly five
    /// minutes), so only on request: `MAP3D_FOOTPRINT_REPORT=1`.
    func testRealFootprintsRoundBanqiaoCostNoMoreThanTheGamesHouses() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FOOTPRINT_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FOOTPRINT_REPORT=1.") }
        let world = try HighSpeedDemoTests.opened.get()
        let banqiao = try Map3DOpenHereTests.point(25.0133, 121.4637, in: world)
        let baseMap = Map3DFrameCostReportTests.baseMap
        let tiles = try BaseMapTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_buildings.pmtiles"), options: .alwaysMapped))
        func cost(_ footprints: FootprintTiles?) -> (near: Int, far: Int, bytes: Int) {
            let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot(), focus: banqiao, baseMap: tiles,
                                   footprints: footprints, heights: HighSpeedDemoTests.heights,
                                   railways: try? HighSpeedDemoTests.railways())
            var near = 0, far = 0, bytes = 0
            for chunk in scene.chunks {
                near += chunk.mesh.triangleCount
                far += chunk.far.triangleCount
                for mesh in [chunk.mesh, chunk.far, chunk.close, chunk.shadows] {
                    bytes += mesh.vertices.count * MemoryLayout<Map3DVertex>.stride + mesh.indices.count * MemoryLayout<UInt32>.stride
                }
            }
            return (near, far, bytes)
        }
        let houses = cost(nil), real = cost(footprints)
        print("Banqiao, the game's houses: near \(houses.near), far \(houses.far) triangles, \(houses.bytes / 1_000) KB")
        print("Banqiao, real footprints:   near \(real.near), far \(real.far) triangles, \(real.bytes / 1_000) KB")
        XCTAssertLessThanOrEqual(real.near, houses.near)
        XCTAssertLessThanOrEqual(real.far, houses.far)
        XCTAssertLessThan(real.bytes, 1_000_000_000)
    }
}
