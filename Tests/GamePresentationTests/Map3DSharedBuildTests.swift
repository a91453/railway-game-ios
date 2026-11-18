import GameCore
@testable import GamePresentation
import XCTest

/// Decision 876: what the builds of one scene share
/// (``Map3DSharedBuild``) is what each worked out itself before: the
/// network's samples, the lazily hashed track, and a block of chunks built
/// with the scene's memo beside one built alone.
final class Map3DSharedBuildTests: XCTestCase {
    /// A flat world 1,280 m by 512 m: surface track from x = 32 m to a
    /// portal at 192 m, a tunnel falling 4 m to x = 480 m and on to 960 m,
    /// with a train in it. `more`: a second line of track 128 m north.
    private func world(more: Bool = false) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 81_920, height: 32_768),
                                  economy: GameEconomy(balance: 100_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 16_384))
        let portal = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: 16_384))
        let down = try world.buildTrackNode(at: WorldCoordinate(x: 30_720, y: 16_384, z: -256))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: 16_384, z: -256))
        try world.buildTrackEdge(from: a, to: portal)
        try world.buildTrackEdge(from: portal, to: down, structure: .tunnel)
        try world.buildTrackEdge(from: down, to: end, structure: .tunnel)
        if more {
            let c = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 8_192))
            let d = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: 8_192))
            try world.buildTrackEdge(from: c, to: d)
        }
        let train = try world.purchaseTrain(named: "Mole").id
        try world.setTrainCars(train, to: 4)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 20_480))
        return world
    }

    /// Each span's line is the builder's own sampling of it, its box holds
    /// the line, and the cells are those the lines run through.
    func testTheSamplesAreEachSpansOwn() throws {
        let snapshot = try world(more: true).railwaySnapshot()
        let samples = Map3DTrackSamples(snapshot)
        XCTAssertEqual(samples.edges.count, snapshot.edges.count)
        let cell = Double(Land.cellLength)
        var cells = Set<Map3DScene.ChunkKey>()
        var spans = 0
        for (alignment, held) in zip(snapshot.edges, samples.edges) {
            XCTAssertEqual(held.count, alignment.edge.sectionSpans.count)
            for (span, kept) in zip(alignment.edge.sectionSpans, held) {
                XCTAssertEqual(kept.kind, span.kind)
                XCTAssertEqual(kept.start, span.start)
                XCTAssertEqual(kept.end, span.end)
                let line = span.end > span.start ? Map3DScene.Builder.sample(alignment.geometry, from: span.start, to: span.end) : []
                XCTAssertEqual(kept.line, line)
                for point in line {
                    XCTAssertTrue(point.x >= kept.minX && point.x <= kept.maxX && point.y >= kept.minY && point.y <= kept.maxY)
                    cells.insert(Map3DScene.ChunkKey(column: Int((Double(point.x) / cell).rounded(.down)),
                                                     row: Int((Double(point.y) / cell).rounded(.down))))
                    // A region that holds a point of the span is one the
                    // span reaches.
                    let x = Double(point.x), y = Double(point.y)
                    XCTAssertTrue(kept.reaches(WorldRegion(minX: x - 1, minY: y - 1, maxX: x + 1, maxY: y + 1)))
                }
                if !line.isEmpty {
                    spans += 1
                    let away = WorldRegion(minX: Double(kept.maxX) + 200, minY: Double(kept.minY), maxX: Double(kept.maxX) + 300,
                                           maxY: Double(kept.maxY))
                    XCTAssertFalse(kept.reaches(away, by: 100))
                    XCTAssertTrue(kept.reaches(away, by: 200))
                }
            }
        }
        XCTAssertGreaterThanOrEqual(spans, 4)
        XCTAssertEqual(samples.cells, cells)
        XCTAssertFalse(cells.isEmpty)
    }

    /// The memo keeps the first snapshot's samples and still answers
    /// another snapshot with that snapshot's own.
    func testAMemoGivenAnotherSnapshotAnswersWithItsOwn() throws {
        let first = try world().railwaySnapshot(), second = try world(more: true).railwaySnapshot()
        XCTAssertNotEqual(Map3DTrackSamples.mark(of: first), Map3DTrackSamples.mark(of: second))
        XCTAssertEqual(Map3DTrackSamples.mark(of: first), Map3DTrackSamples.mark(of: try world().railwaySnapshot()))
        let shared = Map3DSharedBuild()
        XCTAssertEqual(shared.samples(of: first).edges.count, first.edges.count)
        let other = shared.samples(of: second)
        XCTAssertEqual(other.edges.count, second.edges.count)
        XCTAssertEqual(other.mark, Map3DTrackSamples.mark(of: second))
        XCTAssertEqual(other.cells, Map3DTrackSamples(second).cells)
        XCTAssertEqual(shared.samples(of: first).mark, Map3DTrackSamples.mark(of: first))
        XCTAssertNotEqual(first.edges.count, second.edges.count)
    }

    /// The track hashed a square at a time answers as the track hashed
    /// whole, wherever it is asked first.
    func testTheTrackHashedWhenAskedAnswersAsTheWholeOne() {
        // Zigzags over several 512 m squares, on both sides of the origin.
        var lines: [[Map3DPoint]] = []
        for number in 0..<9 {
            let startX = Float(number % 3) * 700 - 900, startZ = Float(number / 3) * 650 - 800
            lines.append((0..<12).map { step in
                Map3DPoint(startX + Float(step) * 55, 0, startZ + Float((step * (number + 2)) % 5) * 37)
            })
        }
        lines.append([])
        let whole = Map3DRealTrains.PlayerTrack(lines)
        var near = 0, far = 0, along = 0
        // Asked from the far corner first and from the origin first: the
        // order of hashing changes nothing.
        for reversed in [false, true] {
            let lazy = Map3DRealTrains.PlayerTrack(boxes: lines.map(Map3DRealTrains.PlayerTrack.Box.init)) { lines[$0] }
            var probes: [Map3DPoint] = []
            for column in -24...24 {
                for row in -24...24 {
                    probes.append(Map3DPoint(Float(column) * 47 + 3, 0, Float(row) * 43 - 5))
                }
            }
            for point in reversed ? probes.reversed() : probes {
                let isNear = whole.isNear(point, within: 20)
                XCTAssertEqual(lazy.isNear(point, within: 20), isNear, "\(point)")
                let runs = whole.runsAlong(point, dx: 1, dz: 0.2, within: 25)
                XCTAssertEqual(lazy.runsAlong(point, dx: 1, dz: 0.2, within: 25), runs, "\(point)")
                near += isNear ? 1 : 0
                far += isNear ? 0 : 1
                along += runs ? 1 : 0
            }
        }
        XCTAssertGreaterThan(near, 50)
        XCTAssertGreaterThan(far, 50)
        XCTAssertGreaterThan(along, 10)
    }

    /// A block built with the scene's memo (its track cover's), again and
    /// after other blocks, is the block built alone with a memo of its
    /// own, to the byte.
    func testABlockBuiltWithTheScenesMemoIsTheBlockBuiltAlone() throws {
        let world = try world(more: true)
        let origin = (x: 40_960.0, y: 16_384.0)
        let whole = WorldRegion(bounds: world.bounds)
        let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: whole)
        let snapshot = world.railwaySnapshot()
        let scene = Map3DScene(world: world, snapshot: snapshot, skyline: nil, frame: (whole, origin.x, origin.y), baseMap: nil, cityTiles: [],
                               heights: nil, lineBands: nil, railways: nil, temples: nil)
        let blocks = [-2, 0, 1].map { column in
            [Map3DStreaming.Key(column: column, row: -1), Map3DStreaming.Key(column: column, row: 0)]
        }
        let alone = blocks.map { Map3DMapLoad.digest(Map3DScene.chunks($0, of: grid, world: world, snapshot: snapshot)) }
        for _ in 0..<2 {
            for (keys, digest) in zip(blocks, alone) {
                let chunks = Map3DScene.chunks(keys, of: grid, world: world, snapshot: snapshot, trackCover: scene.trackCover)
                XCTAssertEqual(chunks.count, keys.count)
                XCTAssertEqual(Map3DMapLoad.digest(chunks), digest)
            }
        }
        XCTAssertEqual(Set(alone).count, alone.count, "the blocks differ")
        // The scene's own chunks are those blocks.
        let built = Dictionary(grouping: scene.chunks) { $0.column }
        for (keys, digest) in zip(blocks, alone) {
            XCTAssertEqual(Map3DMapLoad.digest(built[keys[0].column] ?? []), digest)
        }
    }
}
