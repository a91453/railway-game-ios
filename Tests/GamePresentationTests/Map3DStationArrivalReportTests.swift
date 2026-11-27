import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// WURI-FPS (2026-11-27): what a block of chunks hands the main thread
/// when the streaming places it (`Map3DMetalView.makeChunk`: the props
/// sorted into runs, every instance's floats, the buffers' bytes), round
/// THSR Taichung (Wuri), where the owner's iPhone dropped to 9–13 fps with
/// the main thread busy 76–129 ms a frame and stalls of 250–520 ms, and on
/// open track south of Miaoli. Only on request, in release (with the
/// owner's save as `ARRIVAL_SAVE=<save>`, or the high-speed demo):
/// `MAP3D_ARRIVAL_REPORT=1 swift test -c release -Xswiftc -enable-testing --filter Map3DStationArrivalReportTests`.
final class Map3DStationArrivalReportTests: XCTestCase {
    @MainActor
    func testWhatABlockHandsTheMainThread() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_ARRIVAL_REPORT"] != nil else { throw XCTSkip("Set MAP3D_ARRIVAL_REPORT=1.") }
        // The owner's save (`ARRIVAL_SAVE=<save>`, its real lines as laid),
        // or the high-speed demo.
        let world = try ProcessInfo.processInfo.environment["ARRIVAL_SAVE"].map {
            try HeadlessGame.load(Data(contentsOf: URL(fileURLWithPath: $0))).session.world
        } ?? HighSpeedDemoTests.opened.get()
        let railways = try HighSpeedDemoTests.railways()
        let baseMap = Map3DFrameCostReportTests.baseMap
        let tiles = try BaseMapTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_buildings.pmtiles"), options: .alwaysMapped))
        let city = CityTileArea.areas(in: baseMap.appendingPathComponent("city"))
        let temples = try RealTemples(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_temples.json")))
        let snapshot = world.railwaySnapshot()
        let skyline = CitySkyline(world: world)
        for (name, latitude, longitude) in [("THSR Taichung", 24.1121, 120.6158), ("open track south of Miaoli", 24.5200, 120.7900)] {
            let at = try Map3DOpenHereTests.point(latitude, longitude, in: world)
            let grid = Map3DStreaming(originX: at.x, originY: at.y, map: WorldRegion(bounds: world.bounds))
            // Decision 578: the block round the stop, a 5 × 5 in full.
            let keys = grid.area(round: Map3DPoint(0, 0, 0), radius: Map3DStreaming.stationRadius)
            var start = Date()
            let chunks = Map3DScene.chunks(keys, of: grid, world: world, snapshot: snapshot, skyline: skyline, baseMap: tiles, cityTiles: city,
                                           footprints: footprints, heights: HighSpeedDemoTests.heights, railways: railways, temples: temples,
                                           detail: Map3DPoint(0, 0, 0))
            let built = Date().timeIntervalSince(start)
            var bytes = 0, props = 0, signs = 0, triangles = 0, facadeBytes = 0
            var busiest = (props: 0, bytes: 0)
            start = Date()
            var longest = 0.0
            for chunk in chunks {
                let one = Date()
                // What makeChunk does on the main thread besides the copies.
                let sorted = Map3DPropRuns(chunk.props)
                let floats = sorted.instances.flatMap(\.floats)
                let signFloats = chunk.signs.flatMap(\.floats)
                longest = max(longest, Date().timeIntervalSince(one))
                var chunkBytes = (floats.count + signFloats.count) * 4 + chunk.farBoxes.count * MemoryLayout<Map3DBoxInstance>.stride
                for mesh in [chunk.mesh, chunk.far, chunk.close, chunk.standIn, chunk.shadows] {
                    chunkBytes += mesh.vertices.count * MemoryLayout<Map3DVertex>.stride + mesh.indices.count * MemoryLayout<UInt32>.stride
                    triangles += mesh.triangleCount
                }
                facadeBytes += chunk.facade.vertices.count * MemoryLayout<Map3DVertex>.stride + chunk.facade.indices.count * 4
                bytes += chunkBytes
                props += chunk.props.count
                signs += chunk.signs.count
                if chunk.props.count > busiest.props { busiest = (chunk.props.count, chunkBytes) }
            }
            let prep = Date().timeIntervalSince(start)
            print(String(format: "WURI-FPS %@: %d chunks built in %.0f ms (background); main-thread prep %.1f ms (longest chunk %.1f ms); "
                         + "buffers %.1f MB copied on the main thread, %d triangles, %d props, %d signs, street fronts %.1f MB (uploaded a few a frame); "
                         + "busiest chunk %d props, %.1f MB",
                         name, chunks.count, built * 1000, prep * 1000, longest * 1000, Double(bytes) / 1_048_576, triangles, props, signs,
                         Double(facadeBytes) / 1_048_576, busiest.props, Double(busiest.bytes) / 1_048_576))
        }
    }
}
