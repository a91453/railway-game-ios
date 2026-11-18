import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// HSRPACE (decision 861): following a High Speed Rail train from the cab at
/// ten times real time, the window keeps the ground, track and city in
/// full under the train and down the line ahead of it, with each block
/// taking as long to build as it did in this container round Taipei
/// Station (decision 358's slowest numbers) and four times that (a slower
/// device), the train running east and on the High Speed Rail's slant.
///
/// The owner's recording (2026-11-18, an iPad, 287 km/h at 10×, from the
/// cab between Taichung and Miaoli): every second or two the whole ground
/// and the track under the train were gone for half a second, and between
/// them stretches of track were the simplified chunks', without the line's
/// colour band.
final class Map3DStreamingPaceTests: XCTestCase {
    typealias Key = Map3DStreaming.Key
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// How long a block takes to build: a fixed part and a part for each
    /// chunk's square of the block's bounding square with the apron
    /// (``Map3DStreaming/apron``, half a chunk each way), seconds.
    struct Cost {
        var fixed: Double
        var perSquare: Double

        func seconds(_ keys: [Key]) -> Double {
            guard let first = keys.first else { return 0 }
            var low = (first.column, first.row), high = low
            for key in keys {
                low = (min(low.0, key.column), min(low.1, key.row))
                high = (max(high.0, key.column), max(high.1, key.row))
            }
            let squares = Double((high.0 - low.0 + 2) * (high.1 - low.1 + 2))
            return fixed + perSquare * squares
        }

        /// Round Taipei Station in this container (decision 358's slowest
        /// place): 1 chunk 0.069 s, 3 × 3 0.145 s, 5 × 5 0.242 s, the
        /// blocks' squares with the apron 4, 16 and 36.
        static let taipei = Cost(fixed: 0.05, perSquare: 0.0054)
    }

    /// What a run saw, frame by frame.
    struct Run: CustomStringConvertible {
        var frames = 0
        /// Frames whose target stood on a chunk not built.
        var missingUnder = 0
        /// Frames whose target stood on a chunk built without the city in full.
        var coarseUnder = 0
        /// Frames with a chunk of the line's next 2 km not built.
        var missingAhead = 0
        /// Frames with a chunk of the line's next 2 km built without the city
        /// in full, from the fifth second on.
        var coarseAhead = 0
        var blocks = 0
        var chunks = 0
        /// Seconds of building, all blocks together (a core's time).
        var busy = 0.0
        /// Blocks begun while another was being built.
        var besideAnother = 0
        /// The most chunks built in full at once.
        var mostInFull = 0

        var description: String {
            "\(frames) frames: under the train not built \(missingUnder), simplified \(coarseUnder); "
                + "next 2 km not built \(missingAhead), simplified \(coarseAhead); "
                + "\(blocks) blocks, \(chunks) chunks (\(String(format: "%.1f", Double(chunks) / Double(max(blocks, 1)))) a block), "
                + "\(besideAnother) begun beside another; building \(String(format: "%.0f", busy / (Double(frames) / 60) * 100))% of a core; at most \(mostInFull) in full"
        }
    }

    /// The window of a 12 km scene round the middle of a 200 km map, the
    /// city in full within ``Map3DScene/detailRadius`` of its middle, as
    /// the app opens a real-world map.
    private func window() -> Map3DStreaming.Window {
        let half = 100_000 * metre
        let grid = Map3DStreaming(originX: half, originY: half, map: WorldRegion(minX: 0, minY: 0, maxX: 2 * half, maxY: 2 * half))
        let region = WorldRegion(minX: grid.originX - Map3DScene.reach * metre, minY: grid.originY - Map3DScene.reach * metre,
                                 maxX: grid.originX + Map3DScene.reach * metre, maxY: grid.originY + Map3DScene.reach * metre)
        let coarse = grid.keys(within: region).filter { Map3DStreaming.distance(of: $0, to: .zero) > Map3DScene.detailRadius }
        return Map3DStreaming.Window(grid: grid, region: region, coarse: coarse)
    }

    /// Follows a target from the scene's middle at `speed` metres a second
    /// on `heading` (scene x and z) for `seconds`, 60 frames a second, a
    /// block placed `cost` after it was asked for.
    private func follow(heading: SIMD2<Float>, speed: Float, seconds: Double, cost: Cost) -> Run {
        var window = window()
        let way = heading / (heading * heading).sum().squareRoot()
        var run = Run()
        // The blocks being built, each with when it is done: as the app
        // builds them, each on a core of its own.
        var due: [(keys: [Key], at: Double)] = []
        var frame = 0
        while Double(frame) / 60 < seconds {
            let now = Double(frame) / 60
            for block in due where now >= block.at {
                XCTAssertTrue(window.finished(block.keys, generation: 0))
            }
            due.removeAll { now >= $0.at }
            let along = way * speed * Float(now)
            let target = Map3DPoint(along.x, 0, along.y)
            let step = window.step(target: target, at: now)
            if !step.build.isEmpty {
                let took = cost.seconds(step.build)
                if !due.isEmpty { run.besideAnother += 1 }
                due.append((step.build, now + took))
                run.blocks += 1
                run.chunks += step.build.count
                run.busy += took
            }
            run.frames += 1
            let under = window.grid.key(of: target)
            if !window.built.contains(under) { run.missingUnder += 1 } else if window.coarse.contains(under) { run.coarseUnder += 1 }
            var ahead = Set<Key>()
            for metres in stride(from: Float(256), through: 2_000, by: 256) {
                let point = along + way * metres
                ahead.insert(window.grid.key(of: Map3DPoint(point.x, 0, point.y)))
            }
            if !ahead.isSubset(of: window.built) {
                run.missingAhead += 1
            } else if now >= 5, !ahead.isDisjoint(with: window.coarse) {
                run.coarseAhead += 1
            }
            let full = window.built.subtracting(window.coarse)
            run.mostInFull = max(run.mostInFull, full.count)
            frame += 1
        }
        return run
    }

    /// The High Speed Rail between Taichung and Miaoli runs some 30° east
    /// of north (scene z is south).
    private let slant = SIMD2<Float>(0.5, -0.866)
    private let east = SIMD2<Float>(1, 0)
    /// 300 km/h at ten times real time.
    private let speed: Float = 833

    /// At this container's pace, east and on the slant: never a chunk
    /// missing or simplified under the train or down the next 2 km (once
    /// past the first five seconds, while the scene the map opened on,
    /// simplified past 2 km of its middle, is built in full ahead).
    func testATenTimesHighSpeedRunKeepsItsGroundInFull() {
        for heading in [east, slant] {
            let run = follow(heading: heading, speed: speed, seconds: 60, cost: .taipei)
            print("HSRPACE \(heading) 1×: \(run)")
            XCTAssertEqual(run.missingUnder, 0, "\(heading): \(run)")
            XCTAssertEqual(run.coarseUnder, 0, "\(heading): \(run)")
            XCTAssertEqual(run.missingAhead, 0, "\(heading): \(run)")
            XCTAssertEqual(run.coarseAhead, 0, "\(heading): \(run)")
            XCTAssertLessThan(run.busy / 60, 0.75, "\(heading): idle a quarter of the time at least: \(run)")
            XCTAssertEqual(run.besideAnother, 0, "\(heading): one block at a time keeps up: \(run)")
        }
    }

    /// Blocks four times as slow (a device slower than this container;
    /// before decision 861 the line's next 2 km was missing a chunk in
    /// over half the frames at this pace, in 2–14% at three times): still
    /// nothing missing or simplified under the train, nor missing down the
    /// next 2 km, a second block built beside the first when it falls
    /// behind.
    func testATenTimesHighSpeedRunKeepsUpOnASlowerDevice() {
        let slow = Cost(fixed: Cost.taipei.fixed * 4, perSquare: Cost.taipei.perSquare * 4)
        for heading in [east, slant] {
            let run = follow(heading: heading, speed: speed, seconds: 60, cost: slow)
            print("HSRPACE \(heading) 4×: \(run)")
            XCTAssertEqual(run.missingUnder, 0, "\(heading): \(run)")
            XCTAssertEqual(run.coarseUnder, 0, "\(heading): \(run)")
            XCTAssertEqual(run.missingAhead, 0, "\(heading): \(run)")
            XCTAssertGreaterThan(run.besideAnother, 0, "\(heading): \(run)")
        }
    }

    /// The chunks in full stay about half the whole scene's (576; decision
    /// 368: all of them in full round Taipei were too many for an iPhone 17
    /// Pro), most of them the scene's own left behind, simplified again in
    /// time.
    func testTheCityInFullStaysAPartOfTheScene() {
        for heading in [east, slant] {
            let run = follow(heading: heading, speed: speed, seconds: 60, cost: .taipei)
            XCTAssertLessThan(run.mostInFull, 288, "\(heading): \(run)")
        }
    }

    // MARK: - The parts

    /// A block from a thin, slanting line of wanted chunks is filled from
    /// the chunks wanted a little later, in the square round the first
    /// that holds the most.
    func testABlockIsFilledFromTheChunksWantedLater() {
        let wanted = (0..<5).map { Key(column: $0, row: -$0) }
        let fill = Set((0..<5).flatMap { column in (-6...0).map { Key(column: column, row: $0) } })
        let block = Map3DStreaming.block(of: wanted, filling: fill)
        XCTAssertTrue(block.contains(wanted[0]))
        XCTAssertEqual(block.count, Map3DStreaming.blockSide * Map3DStreaming.blockSide)
        XCTAssertEqual(block, block.sorted())
        // Without anything to fill: the wanted ones in the square holding the most.
        XCTAssertEqual(Map3DStreaming.block(of: wanted, filling: []).count, 5)
        XCTAssertEqual(Map3DStreaming.block(of: [], filling: fill), [])
    }

    /// The way ahead: as far as ``Map3DStreaming/inFullAhead`` down the
    /// motion, none standing still; a chunk's distance from it, 0 where it
    /// crosses.
    func testTheWayAhead() throws {
        let end = try XCTUnwrap(Map3DStreaming.way(target: .zero, velocity: SIMD2(833, 0)))
        XCTAssertEqual(end.x, Map3DStreaming.inFullAhead, accuracy: 0.01)
        XCTAssertEqual(end.z, 0, accuracy: 0.01)
        XCTAssertNil(Map3DStreaming.way(target: .zero, velocity: SIMD2(1, 0)))
        let side = Map3DScene.chunkSize
        XCTAssertEqual(Map3DStreaming.distance(of: Key(column: 1, row: -1), toWayFrom: .zero, to: end), 0)
        XCTAssertEqual(Map3DStreaming.distance(of: Key(column: 1, row: 1), toWayFrom: .zero, to: end), side, accuracy: 0.01)
        XCTAssertEqual(Map3DStreaming.distance(of: Key(column: -3, row: -1), toWayFrom: .zero, to: end), 2 * side, accuracy: 0.01)
        // Without an end, from the start alone.
        XCTAssertEqual(Map3DStreaming.distance(of: Key(column: 1, row: 1), toWayFrom: .zero, to: nil),
                       Map3DStreaming.distance(of: Key(column: 1, row: 1), to: .zero))
        // On a slant: the square the way runs through.
        let slant = try XCTUnwrap(Map3DStreaming.way(target: .zero, velocity: SIMD2(400, -693)))
        XCTAssertEqual(Map3DStreaming.distance(of: Map3DStreaming(originX: 0, originY: 0, map: WorldRegion(minX: -1, minY: -1, maxX: 1, maxY: 1))
            .key(of: Map3DPoint(slant.x / 2, 0, slant.z / 2)), toWayFrom: .zero, to: slant), 0)
        XCTAssertTrue(Map3DStreaming.isOnTheWay(Key(column: 3, row: 3), target: .zero, velocity: SIMD2(833, 0)))
        XCTAssertFalse(Map3DStreaming.isOnTheWay(Key(column: 3, row: 4), target: .zero, velocity: SIMD2(833, 0)))
        XCTAssertFalse(Map3DStreaming.isOnTheWay(Key(column: 1, row: 1), target: .zero, velocity: .zero))
    }
}
