@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 368 (the owner's iPhone 17 Pro, 83.1: following a train into
/// the 3D map killed the app for memory, a per-process limit of 3.4 GB).
/// A class of its own, as it builds a whole scene (about a minute on CI)
/// besides opening the high-speed demo. Decision 380's checks of the
/// demo's cab view and overhead line are here too, sharing the demo.
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

    // MARK: - Decision 380: the cab view

    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// Every 40 m along the demo's track in the open in the scene round
    /// `latitude`, `longitude` as the app builds it: whether a wire or mast
    /// of the closest detail is over it within 30 m. The places none is,
    /// counted in chunks built in full and in coarse ones.
    private func missing(_ latitude: Double, _ longitude: Double) throws -> (full: Int, coarse: Int, checked: Int) {
        let world = try HighSpeedDemoTests.opened.get()
        let focus = try Map3DOpenHereTests.point(latitude, longitude, in: world)
        let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot(), focus: focus,
                               heights: HighSpeedDemoTests.heights, railways: try HighSpeedDemoTests.railways())
        struct Cell: Hashable { let x: Int, z: Int }
        func cell(_ p: Map3DPoint) -> Cell { Cell(x: Int((p.x / 16).rounded(.down)), z: Int((p.z / 16).rounded(.down))) }
        var wired: [Cell: Float] = [:]
        var coarse: Set<Map3DStreaming.Key> = []
        for chunk in scene.chunks {
            if chunk.coarse { coarse.insert(Map3DStreaming.Key(column: chunk.column, row: chunk.row)) }
            for vertex in chunk.close.vertices {
                let p = Map3DPoint(vertex.x, vertex.y, vertex.z)
                wired[cell(p)] = max(wired[cell(p)] ?? -.infinity, p.y)
            }
        }
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let region = scene.region
        var full = 0, rough = 0, checked = 0
        for alignment in world.railwaySnapshot().edges where alignment.edge.structure != .tunnel {
            let points = alignment.geometry.points
            for (a, b) in zip(points, points.dropFirst()) {
                let length = (Double(b.x - a.x) * Double(b.x - a.x) + Double(b.y - a.y) * Double(b.y - a.y)).squareRoot() / metre
                for step in stride(from: 0.0, to: length, by: 40) {
                    let share = step / length
                    let x = Double(a.x) + Double(b.x - a.x) * share, y = Double(a.y) + Double(b.y - a.y) * share
                    // Away from the scene's edge, where a wire's span may
                    // fall outside it.
                    guard x > region.minX + 200 * metre, x < region.maxX - 200 * metre,
                          y > region.minY + 200 * metre, y < region.maxY - 200 * metre else { continue }
                    let height = Double(a.z) + Double(b.z - a.z) * share
                    let p = scene.point(worldX: x, worldY: y, height: height)
                    guard !scene.trackCover.isInTunnel(p) else { continue }
                    checked += 1
                    let c = cell(p)
                    let over = (-2...2).contains { dx in (-2...2).contains { dz in (wired[Cell(x: c.x + dx, z: c.z + dz)] ?? -.infinity) > p.y + 4 } }
                    guard !over else { continue }
                    let key = Map3DStreaming.Key(column: Int((p.x / Map3DScene.chunkSize).rounded(.down)),
                                                 row: Int((p.z / Map3DScene.chunkSize).rounded(.down)))
                    if coarse.contains(key) { rough += 1 } else { full += 1 }
                }
            }
        }
        return (full, rough, checked)
    }

    /// Decision 380: the owner's 85.1 video of the high-speed demo's cab view: no masts
    /// or wires for seconds on end out among the fields. Chunks built ahead
    /// of the camera are coarse (decision 368), and the overhead line was
    /// left out of them with the rest of the closest detail: round Yunlin,
    /// 15,095 of 24,930 places along the track had none over them, all in
    /// coarse chunks.
    func testTheWiresRunAllAlongTheLineOutOfTown() throws {
        let yunlin = try missing(23.736, 120.416)
        XCTAssertGreaterThan(yunlin.checked, 10_000)
        XCTAssertEqual(yunlin.full, 0, "in chunks built in full")
        XCTAssertEqual(yunlin.coarse, 0, "in coarse chunks")
    }

    /// The cab camera following the high-speed demo's fastest set at 1×
    /// for `seconds` at 60 frames a second, as the app ticks and draws
    /// it: its heading each frame.
    private func cabHeadings(seconds: Double) throws -> [Float] {
        var world = try HighSpeedDemoTests.opened.get()
        world.setSpeed(.x1)
        try world.advance(ticks: 600)
        // Ticked and drawn for two seconds first, as the app does, on a
        // clock that, as the app's, reads more than 0.
        let start = 1_000.0
        var now = start - 2, nextTick = start - 1.9
        var motion = TrainMotion(world: world, time: now)
        func tick() throws {
            while now >= nextTick {
                try world.advance(ticks: 1)
                motion = TrainMotion(world: world, previous: motion, time: now)
                nextTick += 0.1
            }
        }
        while now < start {
            try tick()
            now += 1.0 / 60
        }
        let train = try XCTUnwrap(motion.runs.max { $0.lag < $1.lag }).train
        // At speed: more than 50 m a game second.
        XCTAssertGreaterThan(try XCTUnwrap(motion.runs.map(\.lag).max()) / metre, 50)
        let at = try XCTUnwrap(motion.head(of: train, at: now))
        let reach = 1_000 * metre
        let region = WorldRegion(minX: at.x - reach, minY: at.y - reach, maxX: at.x + reach, maxY: at.y + reach)
        let scene = Map3DScene(world: world, snapshot: nil, skyline: nil, frame: (region, at.x.rounded(), at.y.rounded()), baseMap: nil,
                               cityTiles: [], heights: nil, lineBands: nil, railways: nil, temples: nil)
        let heights = Map3DTrains.Heights(world: world)
        let follow = Map3DFollow(train: train, view: .cab)
        var camera = Map3DCamera(target: .zero, distance: 300, viewport: (390, 844))
        var headings: [Float] = []
        while now < start + seconds {
            try tick()
            let drawn = Map3DTrains.frame(motion, progress: motion.progress(at: now), heights: heights, in: scene, models: nil, eye: nil)
            if let head = drawn.heads.first(where: { $0.train == train }) {
                camera = follow.camera(following: head, from: camera, elapsed: 1.0 / 60)
                headings.append(camera.heading)
            }
            now += 1.0 / 60
        }
        return headings
    }

    /// Decision 380: the high-speed demo's cab view at 1× turns smoothly
    /// from frame to frame, its turn changing by under half a point's worth
    /// between frames. The owner's 85.1 video shook by about 2 px of 640
    /// each frame, the sign changing each frame; before the fix this
    /// measured 0.024 rad.
    func testTheDemosCabViewDoesNotShakeAtOneTimes() throws {
        let headings = try cabHeadings(seconds: 3)
        XCTAssertGreaterThan(headings.count, 150)
        let turns = zip(headings, headings.dropFirst()).map { Map3DCamera.turnFromNorth($1 - $0) }
        let jerks = zip(turns, turns.dropFirst()).map { abs($1 - $0) }
        // The phone's view, 68° tall on 844 points: about 625 points a
        // radian, a point 0.0016 rad.
        XCTAssertLessThan(try XCTUnwrap(jerks.max()), 0.0008)
    }
}
