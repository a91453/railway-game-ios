import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 714 (MAP3D-FAR): the far view has ground wherever the map
/// does. The window builds what the camera sees, not only what stands
/// within ``Map3DStreaming/around`` of its target, and the camera's target
/// stays over the map.
final class Map3DFarSightTests: XCTestCase {
    private typealias Key = Map3DStreaming.Key
    private let metre = Double(WorldCoordinate.unitsPerMetre)
    private let side = Map3DScene.chunkSize

    /// A streaming grid round the middle of a map `width` metres square.
    private func streaming(width: Double = 100_000) -> Map3DStreaming {
        let half = width / 2 * metre
        return Map3DStreaming(originX: half, originY: half, map: WorldRegion(minX: 0, minY: 0, maxX: 2 * half, maxY: 2 * half))
    }

    /// The window of a scene as the app builds it (``Map3DScene/reach``
    /// each way of the grid's origin).
    private func window(_ grid: Map3DStreaming) -> Map3DStreaming.Window {
        let half = Map3DScene.reach * metre
        return Map3DStreaming.Window(grid: grid, region: WorldRegion(minX: grid.originX - half, minY: grid.originY - half,
                                                                     maxX: grid.originX + half, maxY: grid.originY + half))
    }

    /// A phone held sideways, looking straight down from as far as the
    /// view goes.
    private func farthest(over target: Map3DPoint) -> Map3DCamera {
        Map3DCamera(target: target, distance: Map3DCamera.farthest, viewport: (874, 402))
    }

    /// The chunks on the map whose ground `camera` sees.
    private func seen(by camera: Map3DCamera, on grid: Map3DStreaming) -> [Key] {
        let matrix = camera.viewProjection, centre = grid.key(of: camera.target), span = Int(2 * camera.distance / side)
        var keys: [Key] = []
        for row in (centre.row - span)...(centre.row + span) {
            for column in (centre.column - span)...(centre.column + span) {
                let key = Key(column: column, row: row)
                let low = Map3DPoint(Float(column) * side, 0, Float(row) * side)
                if grid.isOnMap(key), Map3DCamera.sees(minimum: low, maximum: Map3DPoint(low.x + side, 0, low.z + side), through: matrix) {
                    keys.append(key)
                }
            }
        }
        return keys
    }

    /// Steps `window` with `camera` standing still, each block built as
    /// soon as it is asked for, until it asks for nothing; the blocks
    /// built and the chunks let go.
    @discardableResult
    private func settle(_ window: inout Map3DStreaming.Window, camera: Map3DCamera, from seconds: Double = 0, room: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) -> (blocks: Int, dropped: Set<Key>) {
        var blocks = 0, dropped = Set<Key>(), seconds = seconds
        while blocks < 500 {
            seconds += 1
            let step = window.step(target: camera.target, at: seconds, sight: camera.distance, seeing: camera, room: room)
            dropped.formUnion(step.drop)
            guard !step.build.isEmpty else { return (blocks, dropped) }
            XCTAssertTrue(window.finished(step.build, generation: window.generation), file: file, line: line)
            blocks += 1
        }
        XCTFail("the window never stops building", file: file, line: line)
        return (blocks, dropped)
    }

    // MARK: - What the camera sees is built

    /// Pulled out as far as the view goes over where the map opened, the
    /// camera sees past the scene's own chunks (some 23 km across a phone
    /// held sideways, of a scene 12 km square): they are built too. Before
    /// decision 714 only the scene's stood there, and the ground ended in
    /// a strip down the middle of the screen (the owner's iPhone,
    /// `docs/research/DEVICE_C_2026-11-13.md` §3.2).
    func testTheFarthestViewBuildsWhatItSees() {
        let grid = streaming()
        var window = window(grid)
        let camera = farthest(over: .zero)
        let seen = seen(by: camera, on: grid)
        XCTAssertGreaterThan(seen.count, window.scene.count / 2)
        XCTAssertFalse(seen.allSatisfy(window.built.contains), "the scene alone is not all the camera sees")
        settle(&window, camera: camera)
        let missing = seen.filter { !window.built.contains($0) }
        XCTAssertEqual(missing, [], "\(missing.count) of the \(seen.count) chunks in view are not built")
    }

    /// Dragged far off the scene, the same: everything in view is built,
    /// not a circle round the target in the middle of nothing.
    func testAViewDraggedOffTheSceneBuildsWhatItSees() {
        let grid = streaming()
        var window = window(grid)
        let camera = farthest(over: Map3DPoint(20_000, 0, 20_000))
        settle(&window, camera: camera)
        let seen = seen(by: camera, on: grid)
        let missing = seen.filter { !window.built.contains($0) }
        XCTAssertEqual(missing, [], "\(missing.count) of the \(seen.count) chunks in view are not built")
    }

    /// The nearest first: the ground under what the camera looks at
    /// before the edges of the view.
    func testTheNearestOfWhatItSeesFirst() {
        let grid = streaming()
        var window = window(grid)
        let camera = farthest(over: Map3DPoint(30_000, 0, 0))
        var last: Float = 0, seconds = 0.0
        for _ in 0..<40 {
            seconds += 1
            let step = window.step(target: camera.target, at: seconds, sight: camera.distance, seeing: camera)
            guard let first = step.build.first else { break }
            let nearest = step.build.map { Map3DStreaming.distance(of: $0, to: camera.target) }.min() ?? 0
            XCTAssertGreaterThanOrEqual(nearest + 3 * side, last, "block round \(first) is nearer than the one before it")
            last = max(last, nearest)
            XCTAssertTrue(window.finished(step.build, generation: window.generation))
        }
    }

    /// Close up nothing changes: the view sees less than the window
    /// already keeps round its target.
    func testCloseUpNothingMoreIsBuilt() {
        let grid = streaming()
        var with = window(grid), without = window(grid)
        let camera = Map3DCamera(target: Map3DPoint(9_000, 0, 0), distance: 1_600, viewport: (874, 402))
        settle(&with, camera: camera)
        var seconds = 0.0
        while true {
            seconds += 1
            let step = without.step(target: camera.target, at: seconds, sight: camera.distance)
            guard !step.build.isEmpty else { break }
            XCTAssertTrue(without.finished(step.build, generation: without.generation))
        }
        XCTAssertEqual(with.built, without.built)
    }

    // MARK: - Let go

    /// What the far view saw and no longer does is let go once the camera
    /// has moved on (the scene's own chunks stay, as before).
    func testWhatTheFarViewNoLongerSeesIsLetGo() {
        let grid = streaming()
        var window = window(grid)
        let first = farthest(over: Map3DPoint(20_000, 0, 20_000))
        settle(&window, camera: first)
        let stood = window.built.subtracting(window.scene)
        XCTAssertFalse(stood.isEmpty)
        // Sent somewhere else (a jump is no motion: the plan is of a still
        // target there).
        let second = farthest(over: Map3DPoint(-25_000, 0, -25_000))
        let dropped = settle(&window, camera: second, from: 1_000).dropped
        XCTAssertEqual(dropped, stood)
        XCTAssertTrue(window.scene.isSubset(of: window.built))
    }

    /// A camera that only shakes at the edge does not build and let go
    /// by turns: a chunk is kept a little past where it is last seen.
    func testTheEdgeOfTheViewIsKept() {
        let grid = streaming()
        var window = window(grid)
        let camera = farthest(over: Map3DPoint(20_000, 0, 20_000))
        settle(&window, camera: camera)
        let nudged = farthest(over: Map3DPoint(20_000 + side / 2, 0, 20_000))
        var seconds = 2_000.0, dropped: [Key] = []
        for _ in 0..<4 {
            seconds += 1
            let step = window.step(target: nudged.target, at: seconds, sight: nudged.distance, seeing: nudged)
            dropped += step.drop
            if !step.build.isEmpty { XCTAssertTrue(window.finished(step.build, generation: window.generation)) }
        }
        XCTAssertEqual(dropped, [])
    }

    // MARK: - Within decision 711's limits

    /// While the scene's buffers are over what the device holds
    /// (`room: false`), nothing more is built for the view's edges; what
    /// stands there is kept, and the chunks round the target are built
    /// as ever.
    func testNoRoomBuildsOnlyRoundTheTarget() {
        let grid = streaming()
        var window = window(grid)
        let camera = farthest(over: Map3DPoint(20_000, 0, 20_000))
        settle(&window, camera: camera, room: false)
        let beyond = window.built.subtracting(window.scene).filter { Map3DStreaming.distance(of: $0, to: camera.target) > Map3DStreaming.around }
        XCTAssertEqual(beyond, [])
        XCTAssertTrue(grid.area(round: camera.target, radius: Map3DStreaming.around).allSatisfy(window.built.contains))
        // With room again the rest is built; without it once more, it stays.
        settle(&window, camera: camera, from: 1_000)
        let stood = window.built
        let dropped = settle(&window, camera: camera, from: 2_000, room: false).dropped
        XCTAssertEqual(dropped, [])
        XCTAssertEqual(window.built, stood)
    }

    /// What is let go when memory runs short (decision 711's
    /// ``Map3DStreaming/Window/shed(farFrom:radius:)``, as far as the
    /// camera sees) is nothing the view then builds again: shedding and
    /// building do not chase each other.
    func testSheddingLeavesWhatTheViewBuilds() {
        let grid = streaming()
        var window = window(grid)
        let camera = farthest(over: Map3DPoint(8_000, 0, 0))
        settle(&window, camera: camera)
        let shed = window.shed(farFrom: camera.target, radius: Map3DStreaming.sight(of: camera))
        XCTAssertFalse(shed.isEmpty, "the scene's far side is let go")
        XCTAssertEqual(settle(&window, camera: camera, from: 1_000).blocks, 0)
        XCTAssertEqual(window.shed(farFrom: camera.target, radius: Map3DStreaming.sight(of: camera)), [])
    }

    // MARK: - The camera stays over the map

    /// A drag cannot take the camera's target off the map: three fast
    /// drags of the farthest view (some 11 km each) took it off a map
    /// 16 km square, where nothing is ever built (the owner's iPhone,
    /// `DEVICE_C_2026-11-13.md` §3.3: empty 22 seconds later).
    func testTheTargetStaysOverTheMap() {
        let grid = streaming(width: 16_384)
        var camera = farthest(over: .zero)
        for _ in 0..<3 { camera = camera.panned(dx: -437, dy: 0).held(over: grid.ground) }
        XCTAssertEqual(camera.target.x, 8_192)
        XCTAssertEqual(camera.target.z, 0)
        XCTAssertFalse(seen(by: camera, on: grid).isEmpty)
        // Within the map a drag is as it was.
        let inside = farthest(over: Map3DPoint(1_000, 0, -2_000))
        XCTAssertEqual(inside.held(over: grid.ground), inside)
        // A map not centred on the scene: its own edges.
        let off = Map3DStreaming(originX: 1_000 * metre, originY: 3_000 * metre,
                                 map: WorldRegion(minX: 0, minY: 0, maxX: 10_000 * metre, maxY: 10_000 * metre))
        let held = farthest(over: Map3DPoint(-50_000, 7, 50_000)).held(over: off.ground)
        XCTAssertEqual(held.target, Map3DPoint(-1_000, 7, 7_000))
    }
}
