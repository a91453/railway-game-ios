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
}
