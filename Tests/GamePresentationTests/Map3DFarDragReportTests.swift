import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// MAP3D-FAR (decision 714): the farthest view dragged off the scene, on a
/// save: what the window asks for, block by block, how long each block
/// takes to build, and how much of what the camera sees stands in the end.
/// A report, not a check: only with `MAP3D_SAVE` naming a save file (the
/// player's own, never in the repository).
///
///     MAP3D_SAVE=/path/to/save.json swift test --skip-build --filter Map3DFarDragReportTests
///
/// `MAP3D_DRAG=east,south` is how far the target is dragged, in metres
/// (default 0,0: the view only pulled out); `MAP3D_OLD=1` plans as before
/// decision 714.
final class Map3DFarDragReportTests: XCTestCase {
    private struct File: Decodable {
        let game: SavedGame
    }

    func testReportOfADrag() throws {
        guard let path = ProcessInfo.processInfo.environment["MAP3D_SAVE"] else { throw XCTSkip("set MAP3D_SAVE to a save file") }
        let world = try JSONDecoder().decode(File.self, from: Data(contentsOf: URL(fileURLWithPath: path))).game.world
        let resources = Map3DRealTrainsTests.resources, base = resources.appendingPathComponent("BaseMap")
        let snapshot = world.railwaySnapshot(), skyline = CitySkyline(world: world)
        let tiles = try BaseMapTiles(data: Data(contentsOf: base.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let city = CityTileArea.areas(in: base.appendingPathComponent("city"))
        let footprints = try FootprintTiles(data: Data(contentsOf: base.appendingPathComponent("taiwan_buildings.pmtiles"), options: .alwaysMapped))
        let heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        let bands = Map3DLineBands(world: world, palette: .standard)
        let temples = try RealTemples(data: Data(contentsOf: base.appendingPathComponent("taiwan_temples.json")))
        var land = try? RealNoBuildLand(data: RealWorldDataLoadTests.file("taiwan_no_build", "json"))
        land?.airfields = try RealAirfields(data: Data(contentsOf: base.appendingPathComponent("taiwan_airfields.json")))
        let railways = Map3DRealTrainsTests.railways

        var start = Date()
        let scene = Map3DScene(world: world, snapshot: snapshot, skyline: skyline, focus: nil, baseMap: tiles, cityTiles: city,
                               footprints: footprints, heights: heights, lineBands: bands, railways: railways, temples: temples, noBuild: land)
        print(String(format: "MAP3D-DRAG scene: %d chunks in %.1f s", scene.chunks.count, Date().timeIntervalSince(start)))
        var window = Map3DStreaming.Window(scene: scene, map: WorldRegion(bounds: world.bounds))
        let drag = (ProcessInfo.processInfo.environment["MAP3D_DRAG"] ?? "0,0").split(separator: ",").compactMap { Float($0) }
        let camera = Map3DCamera(target: Map3DPoint(drag[0], 0, drag[1]), distance: Map3DCamera.farthest, viewport: (874, 402))
            .held(over: window.grid.ground)
        let target = camera.target
        // `MAP3D_OLD=1`: as before decision 714, without the camera.
        let old = ProcessInfo.processInfo.environment["MAP3D_OLD"] != nil
        var seconds = 0.0, blocks = 0, built = 0, bytes = 0, triangles = 0
        start = Date()
        while blocks < 400 {
            seconds += 1
            let step = window.step(target: target, at: seconds, sight: camera.distance, seeing: old ? nil : camera)
            guard !step.build.isEmpty else { break }
            let began = Date()
            let chunks = Map3DScene.chunks(step.build, of: window.grid, world: world, snapshot: snapshot, skyline: skyline, baseMap: tiles,
                                           cityTiles: city, footprints: footprints, heights: heights, lineBands: bands, railways: railways,
                                           temples: temples, noBuild: land, trackCover: scene.trackCover, detail: window.buildingAround)
            XCTAssertTrue(window.finished(step.build, generation: window.generation))
            blocks += 1
            built += chunks.count
            for chunk in chunks {
                triangles += chunk.mesh.triangleCount
                for mesh in [chunk.mesh, chunk.far, chunk.close, chunk.standIn, chunk.shadows] {
                    bytes += mesh.vertices.count * MemoryLayout<Map3DVertex>.stride + mesh.indices.count * 4
                }
            }
            print(String(format: "MAP3D-DRAG block %d: %d keys, %d chunks, %.2f s", blocks, step.build.count, chunks.count, Date().timeIntervalSince(began)))
        }
        print(String(format: "MAP3D-DRAG %d blocks, %d chunks, %d triangles, %d MB in %.1f s", blocks, built, triangles, bytes >> 20,
                     Date().timeIntervalSince(start)))
        // What the camera sees of the map, and how much of it stands.
        let matrix = camera.viewProjection, side = Map3DScene.chunkSize
        var seen = 0, standing = 0
        let span = Int(4 * Map3DCamera.farthest / side)
        let centre = window.grid.key(of: target)
        for row in (centre.row - span)...(centre.row + span) {
            for column in (centre.column - span)...(centre.column + span) {
                let key = Map3DStreaming.Key(column: column, row: row)
                guard window.grid.isOnMap(key) else { continue }
                let low = Map3DPoint(Float(column) * side, 0, Float(row) * side), high = Map3DPoint(low.x + side, 0, low.z + side)
                guard Map3DCamera.sees(minimum: low, maximum: high, through: matrix) else { continue }
                seen += 1
                if window.built.contains(key) { standing += 1 }
            }
        }
        print("MAP3D-DRAG the camera sees \(seen) chunks' squares on the map, \(standing) of them built")
    }
}
