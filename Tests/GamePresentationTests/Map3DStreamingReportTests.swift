import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 358: how long the 3D map's scene takes to build, whole and a
/// block of chunks at a time, on a whole-Taiwan map with every file the
/// app passes, at Taipei, Taichung and along the High Speed Rail between
/// them. Only on request, and in release for numbers worth writing down:
/// `MAP3D_FRAME_REPORT=1 swift test -c release -Xswiftc -enable-testing --filter Map3DStreamingReportTests`.
final class Map3DStreamingReportTests: XCTestCase {
    func testTheBuildTimes() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let resources = Map3DRealTrainsTests.resources
        let world = GameWorld.newGame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds, land: [])
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        let tiles = try BaseMapTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let city = CityTileArea.areas(in: resources.appendingPathComponent("BaseMap/city"))
        let temples = try RealTemples(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_temples.json")))
        let railways = try XCTUnwrap(Map3DRealTrainsTests.railways)
        let skyline = CitySkyline(world: world)
        let snapshot = world.railwaySnapshot()
        let metre = Double(WorldCoordinate.unitsPerMetre)
        for (name, latitude, longitude) in [("Taipei Station", 25.0478, 121.5170), ("Taichung Station", 24.1372, 120.6869),
                                            ("THSR Taichung", 24.1121, 120.6158), ("THSR Miaoli", 24.6083, 120.8253),
                                            ("THSR Hsinchu-Miaoli line", 24.7300, 120.9300)] {
            let at = frame.worldPosition(latitude: latitude, longitude: longitude)
            let origin = (x: at.x.rounded(), y: at.y.rounded())
            let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: WorldRegion(bounds: world.bounds))
            func whole(coarse: Bool = false) -> (seconds: Double, scene: Map3DScene) {
                let half = Map3DScene.reach * metre
                let region = WorldRegion(minX: origin.x - half, minY: origin.y - half, maxX: origin.x + half, maxY: origin.y + half)
                let start = Date()
                let scene = Map3DScene(world: world, snapshot: snapshot, skyline: skyline, frame: (region, origin.x, origin.y), baseMap: tiles,
                                       cityTiles: coarse ? [] : city, heights: heights, lineBands: nil, railways: coarse ? nil : railways,
                                       temples: coarse ? nil : temples)
                return (Date().timeIntervalSince(start), scene)
            }
            /// The best of three builds of the `side` by `side` block whose
            /// north-west chunk is `first` columns east of the origin's.
            func block(_ side: Int, _ first: Int = 0) -> (seconds: Double, triangles: Int) {
                let keys = (0..<side).flatMap { row in (0..<side).map { Map3DStreaming.Key(column: first + $0, row: row) } }
                var best = (seconds: Double.infinity, triangles: 0)
                for _ in 0..<3 {
                    let start = Date()
                    let chunks = Map3DScene.chunks(keys, of: grid, world: world, snapshot: snapshot, skyline: skyline, baseMap: tiles,
                                                   cityTiles: city, heights: heights, railways: railways, temples: temples)
                    best = (min(best.seconds, Date().timeIntervalSince(start)), chunks.reduce(0) { $0 + $1.mesh.triangleCount })
                }
                return best
            }
            _ = block(1)
            let full = whole(), coarse = whole(coarse: true)
            let one = block(1), three = block(3), five = block(5)
            print(String(format: "%@: whole 12 km %.2f s (%d chunks, %d triangles), coarse %.2f s; 1 chunk %.3f s, 3×3 %.3f s (%.1f ms a chunk, %d triangles), 5×5 %.3f s (%.1f ms a chunk)",
                         name, full.seconds, full.scene.chunks.count, full.scene.triangleCount, coarse.seconds, one.seconds,
                         three.seconds, three.seconds * 1000 / 9, three.triangles, five.seconds, five.seconds * 1000 / 25))
        }
    }
}
