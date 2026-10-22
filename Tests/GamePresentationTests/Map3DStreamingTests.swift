import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 358: the 3D map's chunks built ahead of the camera as it moves
/// and let go behind it.
final class Map3DStreamingTests: XCTestCase {
    private typealias Key = Map3DStreaming.Key
    private let metre = Double(WorldCoordinate.unitsPerMetre)
    private let side = Map3DScene.chunkSize

    /// A streaming grid round the middle of a map 100 km square.
    private func streaming() -> Map3DStreaming {
        let half = 50_000 * metre
        return Map3DStreaming(originX: half, originY: half, map: WorldRegion(minX: 0, minY: 0, maxX: 2 * half, maxY: 2 * half))
    }

    private func centre(_ key: Key) -> Map3DPoint {
        Map3DPoint((Float(key.column) + 0.5) * side, 0, (Float(key.row) + 0.5) * side)
    }

    // MARK: - Built apart, as built whole

    /// Chunks built a block at a time are the chunks the whole scene
    /// builds, vertex for vertex: round Taichung Station, with the real
    /// ground, buildings, temples and railways (its viaduct) and a line of
    /// the player's across it. All but the closest detail: the park,
    /// temple and commercial kits' scenes keep to a scene's budget, so a
    /// block may give a park another scene (each stands in one chunk).
    func testChunksBuiltApartAreTheWholeScenes() throws {
        let resources = Map3DRealTrainsTests.resources
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.1372, longitudeDegrees: 120.6869)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: 24.1372, longitude: 120.6869)
        let across = Int64(2_000 * WorldCoordinate.unitsPerMetre)
        let built = try LineBuilder.line(through: [PlanPoint(x: Int64(at.x) - across, y: Int64(at.y) - across / 3),
                                                   PlanPoint(x: Int64(at.x) + across, y: Int64(at.y) + across / 3)], in: world)
        let tiles = try BaseMapTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let city = CityTileArea.areas(in: resources.appendingPathComponent("BaseMap/city"))
        let temples = try RealTemples(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan_temples.json")))
        let railways = try XCTUnwrap(Map3DRealTrainsTests.railways)
        let bands = Map3DLineBands(world: built, palette: .standard)
        let origin = (x: at.x.rounded(), y: at.y.rounded())
        let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: WorldRegion(bounds: built.bounds))
        // Six chunks by six whole, of which the middle four by four are
        // compared: the whole scene's own edge is a chunk away.
        let whole = try XCTUnwrap(grid.region(of: [Key(column: -3, row: -3), Key(column: 2, row: 2)]))
        let skyline = CitySkyline(world: built)
        let snapshot = built.railwaySnapshot()
        let scene = Map3DScene(world: built, snapshot: snapshot, skyline: skyline, frame: (whole, origin.x, origin.y), baseMap: tiles,
                               cityTiles: city, heights: nil, lineBands: bands, railways: railways, temples: temples)
        let inner = (-2...1).flatMap { row in (-2...1).map { Key(column: $0, row: row) } }
        var apart: [Map3DScene.Chunk] = []
        for block in [inner.filter { $0.column < 0 && $0.row < 0 }, inner.filter { $0.column >= 0 && $0.row < 0 },
                      inner.filter { $0.column < 0 && $0.row >= 0 }, inner.filter { $0.column >= 0 && $0.row >= 0 }] {
            apart += Map3DScene.chunks(block, of: grid, world: built, snapshot: snapshot, skyline: skyline, baseMap: tiles, cityTiles: city,
                                       lineBands: bands, railways: railways, temples: temples)
        }
        let wholeChunks = Dictionary(uniqueKeysWithValues: scene.chunks.map { (Key(column: $0.column, row: $0.row), $0) })
        XCTAssertEqual(Set(apart.map { Key(column: $0.column, row: $0.row) }), Set(inner).intersection(wholeChunks.keys))
        var triangles = 0
        for chunk in apart {
            let key = Key(column: chunk.column, row: chunk.row)
            let same = try XCTUnwrap(wholeChunks[key])
            triangles += chunk.mesh.triangleCount
            XCTAssertEqual(chunk.mesh.vertices, same.mesh.vertices, "\(key)")
            XCTAssertEqual(chunk.mesh.indices, same.mesh.indices, "\(key)")
            XCTAssertEqual(chunk.baseIndexCount, same.baseIndexCount, "\(key)")
            XCTAssertEqual(chunk.far.vertices, same.far.vertices, "\(key)")
            XCTAssertEqual(chunk.shadows.vertices, same.shadows.vertices, "\(key)")
            XCTAssertEqual(chunk.props.map(\.floats), same.props.map(\.floats), "\(key)")
            XCTAssertEqual(chunk.signs, same.signs, "\(key)")
            XCTAssertEqual(chunk.cityTops, same.cityTops, "\(key)")
        }
        // A busy place: the city, the station and the track are there.
        XCTAssertGreaterThan(triangles, 20_000)
    }

    /// Only a real-world map's 3D map builds ahead.
    func testOnlyARealWorldMapStreams() throws {
        XCTAssertFalse(Map3DStreaming.streams(GameWorld.newGame()))
        XCTAssertTrue(Map3DStreaming.streams(GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.1372, longitudeDegrees: 120.6869)))))
    }

    /// A block off the map builds nothing; one across its edge only what
    /// is on it.
    func testNoChunksOffTheMap() {
        let world = GameWorld.newGame()
        let map = WorldRegion(bounds: world.bounds)
        let grid = Map3DStreaming(originX: map.minX, originY: map.minY, map: map)
        XCTAssertTrue(Map3DScene.chunks([Key(column: -3, row: -3)], of: grid, world: world).isEmpty)
        let corner = Map3DScene.chunks([Key(column: -1, row: -1), Key(column: 0, row: 0)], of: grid, world: world)
        XCTAssertEqual(corner.map { Key(column: $0.column, row: $0.row) }, [Key(column: 0, row: 0)])
    }

    // MARK: - Space

    func testTheKeysAScenesRegionHoldsWhole() {
        let grid = streaming()
        let region = WorldRegion(minX: grid.originX - 1_000 * metre, minY: grid.originY - 512 * metre,
                                 maxX: grid.originX + 1_100 * metre, maxY: grid.originY + 512 * metre)
        // Columns -1...1 lie whole within -1,000...1,100 m; rows -1 and 0.
        XCTAssertEqual(grid.keys(within: region), Set([-1, 0, 1].flatMap { c in [-1, 0].map { Key(column: c, row: $0) } }))
        XCTAssertEqual(grid.key(of: Map3DPoint(-0.5, 0, 511.9)), Key(column: -1, row: 0))
        XCTAssertEqual(grid.region(of: Key(column: 1, row: -1)),
                       WorldRegion(minX: grid.originX + 512 * metre, minY: grid.originY - 512 * metre, maxX: grid.originX + 1_024 * metre, maxY: grid.originY))
    }

    // MARK: - Planning

    /// Standing still, the chunks within ``Map3DStreaming/around`` of the
    /// target, the nearest first.
    func testStillTheChunksRoundTheTarget() {
        let grid = streaming()
        let wanted = grid.wanted(target: Map3DPoint(0, 0, 0), velocity: .zero)
        let reach = Int((Map3DStreaming.around / side).rounded(.up))
        XCTAssertEqual(wanted.count, Set(wanted).count)
        for key in wanted {
            XCTAssertLessThanOrEqual(abs(key.column), reach)
            XCTAssertLessThanOrEqual(abs(key.row), reach)
        }
        // A disc, not a square: no corner of the square.
        XCTAssertFalse(wanted.contains(Key(column: reach, row: reach)))
        XCTAssertEqual(Set(wanted.prefix(4)), [Key(column: -1, row: -1), Key(column: 0, row: -1), Key(column: -1, row: 0), Key(column: 0, row: 0)])
        XCTAssertTrue(wanted.contains(Key(column: 5, row: 0)))
        XCTAssertFalse(wanted.contains(Key(column: 7, row: 0)))
    }

    /// Moving east at a High Speed Rail train's 83 m/s, the strip
    /// ahead to ``Map3DStreaming/ahead`` east is wanted too, the chunks
    /// the target reaches first before those it reaches later, and
    /// nothing further behind than when standing still.
    func testMovingTheChunksAheadInTheOrderReached() throws {
        let grid = streaming()
        let east = SIMD2<Float>(83, 0)
        let wanted = grid.wanted(target: Map3DPoint(0, 0, 0), velocity: east)
        let still = Set(grid.wanted(target: Map3DPoint(0, 0, 0), velocity: .zero))
        XCTAssertTrue(still.isSubset(of: Set(wanted)))
        // The strip's end is round, as wide as its sides.
        let lastAhead = Int((Map3DStreaming.ahead + Map3DStreaming.aheadWidth) / side)
        XCTAssertTrue(wanted.contains(Key(column: lastAhead, row: 0)))
        XCTAssertFalse(wanted.contains(Key(column: lastAhead + 1, row: 0)))
        // Not ahead to the west, north or south.
        XCTAssertFalse(wanted.contains(Key(column: -8, row: 0)))
        XCTAssertFalse(wanted.contains(Key(column: 0, row: 8)))
        func rank(_ key: Key) throws -> Int { try XCTUnwrap(wanted.firstIndex(of: key), "\(key)") }
        XCTAssertLessThan(try rank(Key(column: 6, row: 0)), try rank(Key(column: 8, row: 0)))
        XCTAssertLessThan(try rank(Key(column: 8, row: 0)), try rank(Key(column: 10, row: 0)))
        // Beside the target before far ahead.
        XCTAssertLessThan(try rank(Key(column: 0, row: 3)), try rank(Key(column: 10, row: 0)))
        // Diagonally the same, along the motion.
        let northEast = grid.wanted(target: Map3DPoint(0, 0, 0), velocity: SIMD2(60, -60))
        XCTAssertTrue(northEast.contains(Key(column: 7, row: -8)))
        XCTAssertFalse(northEast.contains(Key(column: 7, row: 7)))
    }

    /// The plan builds the wanted chunks not built or building, the
    /// soonest first, and lets go of the built ones out past the wanted
    /// ones by ``Map3DStreaming/slack``, not those just past them.
    func testThePlanBuildsWhatIsMissingAndDropsWhatIsFarBehind() {
        let grid = streaming()
        let east = SIMD2<Float>(83, 0)
        // Built round the origin, the target now 4 km east of it.
        let built = Set(grid.wanted(target: Map3DPoint(0, 0, 0), velocity: .zero))
        let target = Map3DPoint(4_000, 0, 0)
        let building: Set<Key> = [Key(column: 8, row: 0)]
        let plan = grid.plan(target: target, velocity: east, built: built, building: building)
        XCTAssertFalse(plan.build.contains { built.contains($0) || building.contains($0) })
        XCTAssertEqual(Set(plan.build).union(building).union(built.intersection(grid.wanted(target: target, velocity: east))),
                       Set(grid.wanted(target: target, velocity: east)))
        XCTAssertEqual(plan.build, grid.wanted(target: target, velocity: east).filter { !built.contains($0) && !building.contains($0) })
        // Let go: 3 km west of the origin is 7 km behind; the origin's
        // own chunk 4 km behind, kept (the slack).
        XCTAssertTrue(plan.drop.contains(Key(column: -6, row: 0)))
        XCTAssertFalse(plan.drop.contains(Key(column: 0, row: 0)))
        XCTAssertFalse(plan.drop.contains { !built.contains($0) })
        XCTAssertEqual(plan.drop, plan.drop.sorted())
        // Where it is wanted nothing is let go.
        XCTAssertEqual(grid.plan(target: .zero, velocity: .zero, built: built).drop, [])
    }

    /// A chunk just past the wanted ones is not let go: it would be built
    /// again at the next turn.
    func testTheSlackKeepsTheEdge() {
        let grid = streaming()
        let edge = Key(column: Int(Map3DStreaming.around / side) + 1, row: 0)
        XCTAssertFalse(grid.wanted(target: .zero, velocity: .zero).contains(edge))
        XCTAssertEqual(grid.plan(target: .zero, velocity: .zero, built: [edge]).drop, [])
        let far = Key(column: edge.column + 3, row: 0)
        XCTAssertEqual(grid.plan(target: .zero, velocity: .zero, built: [far]).drop, [far])
    }

    /// Nothing off the map is wanted.
    func testNothingOffTheMap() {
        let world = GameWorld.newGame()
        let map = WorldRegion(bounds: world.bounds)
        let grid = Map3DStreaming(originX: map.minX, originY: map.minY, map: map)
        let wanted = grid.wanted(target: Map3DPoint(100, 0, 100), velocity: SIMD2(-83, 0))
        XCTAssertFalse(wanted.isEmpty)
        XCTAssertTrue(wanted.allSatisfy { $0.column >= 0 && $0.row >= 0 })
    }

    /// A block is the first wanted chunk and those wanted in the three by
    /// three square round it.
    func testABlockRoundTheFirst() {
        let wanted = [Key(column: 5, row: 0), Key(column: 9, row: 0), Key(column: 6, row: 1), Key(column: 4, row: -1), Key(column: 7, row: 0)]
        XCTAssertEqual(Map3DStreaming.block(of: wanted), [Key(column: 4, row: -1), Key(column: 5, row: 0), Key(column: 6, row: 1)])
        XCTAssertEqual(Map3DStreaming.block(of: []), [])
    }

    // MARK: - The window

    /// A window over a scene 2 km each way round the grid's origin.
    private func window(kept: Set<Key> = [], generation: Int = 0) -> Map3DStreaming.Window {
        let grid = streaming()
        let region = WorldRegion(minX: grid.originX - 2_000 * metre, minY: grid.originY - 2_000 * metre,
                                 maxX: grid.originX + 2_000 * metre, maxY: grid.originY + 2_000 * metre)
        return Map3DStreaming.Window(grid: grid, region: region, generation: generation, kept: kept)
    }

    /// It starts with the scene's whole chunks built, and the chunks kept
    /// from before where the scene has none whole.
    func testTheWindowStartsWithTheScenesChunks() {
        let fresh = window()
        // -2,000…2,000 m holds chunks -3…2 whole.
        XCTAssertEqual(fresh.built, Set((-3...2).flatMap { c in (-3...2).map { Key(column: c, row: $0) } }))
        XCTAssertEqual(fresh.stale, [])
        let kept = window(kept: [Key(column: 0, row: 0), Key(column: 9, row: 0)])
        XCTAssertEqual(kept.stale, [Key(column: 9, row: 0)])
        XCTAssertTrue(kept.built.contains(Key(column: 9, row: 0)))
    }

    /// Still, it builds one block at a time round the target, the soonest
    /// first, plans no sooner than ``Map3DStreaming/interval`` unless a
    /// block was just placed, and places a block only for its own scene.
    func testTheWindowBuildsABlockAtATime() {
        var window = window(generation: 2)
        let first = window.step(target: .zero, at: 0)
        XCTAssertEqual(first.drop, [])
        XCTAssertFalse(first.build.isEmpty)
        XCTAssertLessThanOrEqual(first.build.count, 9)
        XCTAssertTrue(first.build.allSatisfy { !window.built.contains($0) })
        XCTAssertEqual(first.build, Map3DStreaming.block(of: window.grid.plan(target: .zero, velocity: .zero, built: window.built).build))
        // Too soon, and then while it builds: nothing more.
        XCTAssertTrue(window.step(target: .zero, at: 0.1).build.isEmpty)
        XCTAssertTrue(window.step(target: .zero, at: 0.5).build.isEmpty)
        // Built for an older scene: not placed.
        XCTAssertFalse(window.finished(first.build, generation: 1))
        XCTAssertEqual(window.building, first.build)
        XCTAssertTrue(window.finished(first.build, generation: 2))
        XCTAssertTrue(Set(first.build).isSubset(of: window.built))
        // Placed: the next block at once.
        let next = window.step(target: .zero, at: 0.51)
        XCTAssertFalse(next.build.isEmpty)
        XCTAssertTrue(Set(next.build).isDisjoint(with: first.build))
        // Until all round it is built.
        var seconds = 0.51
        while !window.building.isEmpty {
            XCTAssertTrue(window.finished(window.building, generation: 2))
            seconds += 0.01
            _ = window.step(target: .zero, at: seconds)
        }
        XCTAssertTrue(Set(window.grid.wanted(target: .zero, velocity: .zero)).isSubset(of: window.built))
    }

    /// Kept chunks are built again once nothing is missing.
    func testTheWindowRebuildsKeptChunksLast() {
        let kept = Key(column: 3, row: 0)
        var window = window(kept: [kept])
        var seconds = 0.0
        var order: [[Key]] = []
        repeat {
            let step = window.step(target: .zero, at: seconds)
            if !step.build.isEmpty {
                order.append(step.build)
                XCTAssertTrue(window.finished(step.build, generation: 0))
            }
            seconds += 0.3
        } while !window.stale.isEmpty && order.count < 100
        XCTAssertEqual(window.stale, [])
        XCTAssertTrue(order.last?.contains(kept) ?? false)
        XCTAssertFalse(order.dropLast().joined().contains(kept))
    }

    /// Running east, the chunks built on the way are let go once far
    /// behind, the scene's own kept, and those ahead built; faster than
    /// ``Map3DStreaming/fastest``, nothing is.
    func testTheWindowFollowsARunAndStopsWhenTooFast() {
        var window = window()
        var seconds = 0.0, x: Float = 0
        var passed = Set<Key>()
        // 83 m/s for 160 s: from the origin to 13.3 km east.
        while seconds < 160 {
            let step = window.step(target: Map3DPoint(x, 0, 0), at: seconds)
            if !step.build.isEmpty {
                XCTAssertTrue(window.finished(step.build, generation: 0))
                passed.formUnion(step.build)
            }
            XCTAssertTrue(window.scene.isDisjoint(with: step.drop))
            seconds += 1.0 / 60
            x = Float(83 * seconds)
        }
        XCTAssertTrue(window.scene.isSubset(of: window.built), "The scene's own")
        XCTAssertTrue(passed.contains(Key(column: 8, row: 0)))
        XCTAssertFalse(window.built.contains(Key(column: 8, row: 0)), "Built on the way, 8 km behind")
        let ahead = window.grid.key(of: Map3DPoint(x + 3_000, 0, 0))
        XCTAssertTrue(window.built.contains(ahead))
        // 1,200 m/s: nothing more.
        var fast = window
        var frame = 0
        while frame < 120 {
            seconds += 1.0 / 60
            x += 20
            let step = fast.step(target: Map3DPoint(x, 0, 0), at: seconds)
            if frame > 60 {
                XCTAssertEqual(step.drop, [])
                XCTAssertEqual(step.build, [])
            } else if !step.build.isEmpty {
                XCTAssertTrue(fast.finished(step.build, generation: 0))
            }
            frame += 1
        }
    }

    // MARK: - Motion

    /// A steady run gives its velocity within a few seconds; a single
    /// jump (the camera sent somewhere) starts again from still.
    func testTheMotionOfASteadyRun() {
        var motion = Map3DStreaming.Motion()
        for frame in 0...180 {
            let seconds = Double(frame) / 60
            motion.update(target: Map3DPoint(Float(83 * seconds), 0, -Float(20 * seconds)), at: seconds)
        }
        XCTAssertEqual(motion.velocity.x, 83, accuracy: 1)
        XCTAssertEqual(motion.velocity.y, -20, accuracy: 1)
        motion.update(target: Map3DPoint(50_000, 0, 0), at: 3.1)
        XCTAssertEqual(motion.velocity, .zero)
        // One frame's twitch barely moves it.
        var still = Map3DStreaming.Motion()
        still.update(target: .zero, at: 0)
        still.update(target: Map3DPoint(5, 0, 0), at: 1.0 / 60)
        still.update(target: .zero, at: 2.0 / 60)
        XCTAssertLessThan(abs(still.velocity.x), Map3DStreaming.still * 4)
    }
}
