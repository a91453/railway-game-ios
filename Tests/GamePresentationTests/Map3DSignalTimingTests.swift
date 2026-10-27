@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 429: the 3D map's signals change with the game clock, green,
/// amber and red, the main road and the crossing road in turn, each
/// junction a little apart from its neighbours.
final class Map3DSignalTimingTests: XCTestCase {
    private typealias Timing = Map3DSignalTiming

    /// The seconds of one cycle `road` shows `light` (no offset).
    private func seconds(_ road: Timing.Road, _ light: Timing.Light) -> [Int64] {
        (0..<Timing.cycle).filter { Timing.light(road, at: $0) == light }
    }

    func testOneCycleIsTheReferencesSeventySeconds() {
        // `SIGNAL_TIMING` of the TW3D pack's `city-config.js`: 70 s, the
        // main road green to 32 s and amber to 35 s; the crossing road
        // green from 36 s, amber from 64 s, red from 67 s.
        XCTAssertEqual(Timing.cycle, 70)
        XCTAssertEqual(seconds(.main, .green), Array(0..<32))
        XCTAssertEqual(seconds(.main, .amber), Array(32..<35))
        XCTAssertEqual(seconds(.main, .red), Array(35..<70))
        XCTAssertEqual(seconds(.cross, .red), Array(0..<36) + Array(67..<70))
        XCTAssertEqual(seconds(.cross, .green), Array(36..<64))
        XCTAssertEqual(seconds(.cross, .amber), Array(64..<67))
        // The cycle repeats, before the clock's start as after.
        for second: Int64 in [-141, -70, -1, 0, 33, 69, 70, 1_000_003] {
            for road in [Timing.Road.main, .cross] {
                XCTAssertEqual(Timing.light(road, at: second), Timing.light(road, at: second + 7 * Timing.cycle), "\(road) \(second)")
            }
        }
    }

    func testTheRoadsNeverGoTogetherAndAllStopBetween() {
        for group in 0..<Timing.groups {
            var allRed: [Int64] = []
            for second in 0..<Timing.cycle {
                let main = Timing.light(.main, group: group, at: second), cross = Timing.light(.cross, group: group, at: second)
                XCTAssertTrue(main == .red || cross == .red, "group \(group) at \(second): \(main) and \(cross)")
                if main == .red && cross == .red { allRed.append(second) }
            }
            XCTAssertEqual(allRed.count, 4, "group \(group): 1 s after the main road's amber, 3 s after the crossing road's")
        }
        // Each change of way passes through red both ways.
        for (from, to) in [(Timing.Road.main, Timing.Road.cross), (.cross, .main)] {
            for second in 0..<Timing.cycle where Timing.light(from, at: second) == .amber && Timing.light(from, at: second + 1) == .red {
                XCTAssertEqual(Timing.light(to, at: second + 1), .red, "\(from) to \(to) at \(second + 1)")
            }
        }
    }

    func testTheGroupsAreApartAndEachJunctionKeepsItsOwn() {
        // Four groups, each a quarter cycle on from the one before.
        XCTAssertEqual(Timing.groups, 4)
        XCTAssertEqual((0..<Timing.groups).map(Timing.offset), [0, 17, 35, 52])
        XCTAssertEqual(Timing.light(.main, group: 1, at: 0), Timing.light(.main, at: 17))
        // A junction's group is the same every time, from where it is.
        let junctions = (0..<6).flatMap { x in (0..<6).map { z in Map3DBaseMap.Point(x: Double(x) * 180 - 412.3, z: Double(z) * 140 + 77.8) } }
        let groups = junctions.map(Timing.group)
        XCTAssertEqual(groups, junctions.map(Timing.group))
        XCTAssertTrue(groups.allSatisfy { (0..<Timing.groups).contains($0) })
        // Neighbours are not all alike: each group among them.
        XCTAssertEqual(Set(groups), Set(0..<Timing.groups))
    }

    func testTooFastAClockHoldsTheMainRoadGreen() {
        // A cycle shorter than 4 s on the screen would blink: from 60×
        // up, the main road green and the crossing road red.
        XCTAssertTrue(Timing.changes(at: .x1))
        XCTAssertTrue(Timing.changes(at: .x10))
        for speed in [GameSpeed.x60, .normal, .double, .fast] {
            XCTAssertFalse(Timing.changes(at: speed), speed.rawValue)
        }
        var clock = GameClock(now: GameTime(seconds: 33), speed: .fast)
        for group in 0..<Timing.groups {
            XCTAssertEqual(Timing.Clock(clock).light(.main, group: group), .green)
            XCTAssertEqual(Timing.Clock(clock).light(.cross, group: group), .red)
        }
        // Paused, as fast as it resumes at.
        clock.pause()
        XCTAssertEqual(Timing.Clock(clock).light(.main, group: 0), .green)
        // At 10× (and paused at it) the lights change.
        clock = GameClock(now: GameTime(seconds: 33), speed: .x10)
        XCTAssertEqual(Timing.Clock(clock).light(.main, group: 0), .amber)
        clock.pause()
        XCTAssertEqual(Timing.Clock(clock).light(.main, group: 0), .amber)
        XCTAssertEqual(Timing.Clock(clock).light(.cross, group: 0), .red)
    }

    func testTheRendererDrawsTheLightTheClockShows() throws {
        let pack = Map3DModelPack.standard
        let models = try XCTUnwrap(Timing.Models(pack: pack))
        let green = try XCTUnwrap(pack.index(of: Map3DProp.signalGo.modelName))
        let red = try XCTUnwrap(pack.index(of: Map3DProp.signalStop.modelName))
        let amber = try XCTUnwrap(pack.index(of: Map3DProp.signalAmber.modelName))
        // No clock: as the signals stand (the main road green).
        XCTAssertEqual(models.model(green, group: 2, clock: nil), green)
        XCTAssertEqual(models.model(red, group: 2, clock: nil), red)
        let clock = Timing.Clock(GameClock(now: GameTime(seconds: 33), speed: .x1))
        XCTAssertEqual(models.model(green, group: 0, clock: clock), amber)
        XCTAssertEqual(models.model(red, group: 0, clock: clock), red)
        // Group 1 is 17 s on: 50 s, the crossing road's green.
        XCTAssertEqual(models.model(green, group: 1, clock: clock), red)
        XCTAssertEqual(models.model(red, group: 1, clock: clock), green)
        // Any other model is drawn as it is.
        let busStop = try XCTUnwrap(pack.index(of: Map3DProp.busStop.modelName))
        XCTAssertEqual(models.model(busStop, group: 0, clock: clock), busStop)
        // The three models are one shape: only the lit light differs.
        let shapes = [green, amber, red].map { pack.models[$0] }
        XCTAssertEqual(Set(shapes.map(\.triangleCount)).count, 1)
        XCTAssertEqual(shapes[0].vertices.map { [$0.x, $0.y, $0.z] }, shapes[1].vertices.map { [$0.x, $0.y, $0.z] })
        XCTAssertEqual(shapes[0].vertices.map { [$0.x, $0.y, $0.z] }, shapes[2].vertices.map { [$0.x, $0.y, $0.z] })
        // A different light lit in each: the glowing faces' colours.
        let lit = shapes.map { Set($0.vertices.filter(\.glows).map(\.color)) }
        XCTAssertTrue(lit.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(lit[0].isDisjoint(with: lit[1]) && lit[1].isDisjoint(with: lit[2]) && lit[0].isDisjoint(with: lit[2]))
        XCTAssertEqual(lit.map { $0.count }, Array(repeating: lit[0].count, count: 3), "one box lit in each")
    }

    func testAChunksPropsRunByModelAndGroup() throws {
        let pack = Map3DModelPack.standard
        let green = try XCTUnwrap(pack.index(of: Map3DProp.signalGo.modelName))
        let tree = try XCTUnwrap(pack.index(of: Map3DProp.tree.modelName))
        func prop(_ model: Int, group: Int = 0) -> Map3DInstance {
            var instance = Map3DInstance.prop(model, at: .zero, forward: Map3DPoint(1, 0, 0), scale: 1, tint: 0xFFFF_FFFF)
            instance.group = group
            return instance
        }
        let runs = Map3DPropRuns([prop(green, group: 3), prop(tree), prop(green, group: 1), prop(tree), prop(green, group: 3)])
        XCTAssertEqual(runs.instances.map(\.model), [tree, tree, green, green, green].sorted())
        // The frame draws a run a model and group…
        XCTAssertEqual(runs.runs.map { [$0.model, $0.group, $0.first, $0.count] },
                       tree < green ? [[tree, 0, 0, 2], [green, 1, 2, 1], [green, 3, 3, 2]] : [[green, 1, 0, 1], [green, 3, 1, 2], [tree, 0, 3, 2]])
        // …and the sun's shadow map one a model: the lights cast no shadow.
        XCTAssertEqual(runs.shapes.map { [$0.model, $0.first, $0.count] }, tree < green ? [[tree, 0, 2], [green, 2, 3]] : [[green, 0, 3], [tree, 3, 2]])
        XCTAssertTrue(Map3DPropRuns([]).runs.isEmpty)
    }
}
