import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// MAP3D-CAP: what a save's 3D map holds and draws, counted without a
/// screen. A report, not a check: it runs only with `MAP3D_SAVE` naming a
/// save file (the player's own, never in the repository).
///
///     MAP3D_SAVE=/path/to/save.json swift test --skip-build --filter Map3DFrameLoadReportTests
final class Map3DFrameLoadReportTests: XCTestCase {
    private struct File: Decodable {
        let game: SavedGame
    }

    func testReportOfASave() throws {
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
        let pack = Map3DModelPack.standard

        // The stations with the most others within 3 km: the densest of
        // the player's network.
        let stations: [(x: Double, y: Double)] = world.stations.map { (x: Double($0.point.x), y: Double($0.point.y)) }
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let near: Double = 3_000 * metre
        var crowded: [((x: Double, y: Double), Int)] = []
        for a in stations {
            var count = 0
            for b in stations where abs(b.x - a.x) < near && abs(b.y - a.y) < near { count += 1 }
            crowded.append((a, count))
        }
        crowded.sort { $0.1 > $1.1 }
        var foci: [(x: Double, y: Double)?] = [nil]
        if let first = crowded.first { foci.append(first.0) }
        if ProcessInfo.processInfo.environment["MAP3D_ALL"] != nil { foci += crowded.dropFirst().prefix(3).map { $0.0 } }
        print("MAP3D-REPORT save: \(stations.count) stations, \(world.trains.count) trains")
        for focus in foci {
            let scene = Map3DScene(world: world, snapshot: snapshot, skyline: skyline, focus: focus, baseMap: tiles, cityTiles: city,
                                   footprints: footprints, heights: heights, lineBands: bands, railways: Map3DRealTrainsTests.railways,
                                   temples: temples, noBuild: land)
            var held = (base: 0, city: 0, far: 0, boxes: 0, close: 0, standIn: 0, shadows: 0, facade: 0, props: 0, signs: 0)
            var bytes = 0, propInstances = 0, full = 0
            for chunk in scene.chunks {
                held.base += chunk.baseIndexCount / 3
                held.city += chunk.mesh.triangleCount - chunk.baseIndexCount / 3
                held.far += chunk.far.triangleCount
                held.boxes += chunk.farBoxes.reduce(0) { $0 + $1.triangleCount }
                held.close += chunk.close.triangleCount
                held.standIn += chunk.standIn.triangleCount
                held.shadows += chunk.shadows.triangleCount
                held.facade += chunk.facade.triangleCount
                held.props += chunk.props.reduce(0) { $0 + pack.models[$1.model].triangleCount }
                held.signs += 2 * chunk.signs.count
                propInstances += chunk.props.count
                if !chunk.coarse { full += 1 }
                for mesh in [chunk.mesh, chunk.far, chunk.close, chunk.standIn, chunk.shadows, chunk.facade] {
                    bytes += mesh.vertices.count * MemoryLayout<Map3DVertex>.stride + mesh.indices.count * 4
                }
                bytes += chunk.farBoxes.count * 88 + chunk.props.count * 80 + chunk.signs.count * 64
            }
            print("MAP3D-REPORT focus \(focus.map { "\(Int($0.x / metre)),\(Int($0.y / metre))" } ?? "built middle"): \(scene.chunks.count) chunks, \(full) in full, \(bytes >> 20) MB of buffers, \(propInstances) props")
            print("MAP3D-REPORT   held triangles \(held)")
            for (distance, viewport) in [(Float(300), (Float(874), Float(402))), (1_800, (874, 402)),
                                         (12_000, (874, 402))] {
                let camera = Map3DCamera(target: .zero, distance: distance, viewport: viewport)
                let frame = Map3DFrameLoad.frame(of: scene.chunks, camera: camera, pack: pack)
                print("MAP3D-REPORT   \(Int(distance)) m \(Int(viewport.0))x\(Int(viewport.1)): \(frame)")
            }
        }
    }
}

/// What the Metal view's pass draws of chunks (``Map3DMetalView/draw``),
/// counted the same way.
enum Map3DFrameLoad {
    struct Frame: CustomStringConvertible {
        var chunks = 0, detailed = 0
        var base = 0, city = 0, far = 0, boxes = 0, close = 0, standIn = 0, shadows = 0, facade = 0, props = 0, signs = 0
        var total: Int { base + city + far + boxes + close + standIn + shadows + facade + props + signs }
        var description: String {
            "\(chunks) chunks (\(detailed) in full) \(total) triangles: base \(base) city \(city) far \(far) boxes \(boxes) close \(close) "
                + "standIn \(standIn) shadows \(shadows) facade \(facade) props \(props) signs \(signs)"
        }
    }

    static func frame(of chunks: [Map3DScene.Chunk], camera: Map3DCamera, pack: Map3DModelPack) -> Frame {
        let matrix = camera.viewProjection
        var frame = Frame()
        for chunk in chunks {
            let detailed = !chunk.coarse && camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: true)
            let close = camera.drawsClose(minimum: chunk.minimum, maximum: chunk.maximum, detailed: detailed, coarse: chunk.coarse, wasClose: true)
            guard Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: matrix) else { continue }
            frame.chunks += 1
            frame.base += chunk.baseIndexCount / 3
            frame.shadows += chunk.shadows.triangleCount
            if detailed {
                frame.detailed += 1
                frame.city += chunk.mesh.triangleCount - chunk.baseIndexCount / 3
                frame.props += chunk.props.reduce(0) { $0 + pack.models[$1.model].triangleCount }
                frame.signs += 2 * chunk.signs.count
                if !(close && !chunk.close.isEmpty) { frame.standIn += chunk.standIn.triangleCount }
            } else {
                frame.far += chunk.far.triangleCount
                frame.boxes += chunk.farBoxes.reduce(0) { $0 + $1.triangleCount }
            }
            if close {
                frame.close += chunk.close.triangleCount
                frame.facade += chunk.facade.triangleCount
            }
        }
        return frame
    }
}
