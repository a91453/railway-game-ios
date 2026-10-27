import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 445: the 3D map's pedestrian signals: the red standing figure,
/// the little green man walking (faster as the green runs out, then
/// flashing) and the countdown, read off decision 429's clock.
final class Map3DPedestrianSignalTests: XCTestCase {
    private typealias Signal = Map3DPedestrianSignal
    private typealias Timing = Map3DSignalTiming
    private typealias Builder = Map3DScene.Builder
    private typealias Point = Map3DBaseMap.Point

    private func clock(_ second: Int64, speed: GameSpeed = .x1, paused: Bool = false) -> Timing.Clock {
        var clock = GameClock(now: GameTime(seconds: second), speed: speed)
        if paused { clock.pause() }
        return Timing.Clock(clock)
    }

    func testPedestriansWalkOnlyWhileTheirTrafficHasItsGreen() {
        for road in [Timing.Road.main, .cross] {
            for second in Int64(-140)..<140 {
                let light = Timing.light(road, at: second)
                if let left = Signal.left(road, at: second) {
                    XCTAssertEqual(light, .green, "\(road) at \(second)")
                    XCTAssertGreaterThanOrEqual(left, 1)
                } else {
                    XCTAssertNotEqual(light, .green, "\(road) at \(second): green but red for those walking")
                }
            }
        }
        // The countdown runs down to 1 as the green ends: 32 s for those
        // beside the main road, 28 s beside the crossing road.
        XCTAssertEqual(Signal.left(.main, at: 0), 32)
        XCTAssertEqual(Signal.left(.main, at: 31), 1)
        XCTAssertNil(Signal.left(.main, at: 32))
        XCTAssertEqual(Signal.left(.cross, at: 36), 28)
        XCTAssertEqual(Signal.left(.cross, at: 63), 1)
        XCTAssertNil(Signal.left(.cross, at: 35))
        // Never both ways at once.
        for second in 0..<Timing.cycle {
            XCTAssertFalse(Signal.left(.main, at: second) != nil && Signal.left(.cross, at: second) != nil, "\(second)")
        }
    }

    func testTheGreenFlashesForTheTimeToCrossAtOneMetreASecond() {
        // Article 231: t = dw / v, the widest road with signals (a trunk
        // road, 11 m) at 1 m/s.
        XCTAssertEqual(Signal.flashing, 11)
        let c = clock(0) // the main road: 32 s left
        XCTAssertNotEqual(Signal.face(.main, group: 0, clock: c, time: 10.7, reduceMotion: false).figure, .dark, "32 s left: steady")
        let late = clock(25) // 7 s left
        // Article 233: once a second, half on, half off.
        XCTAssertEqual(Signal.face(.main, group: 0, clock: late, time: 10.7, reduceMotion: false).figure, .dark)
        XCTAssertNotEqual(Signal.face(.main, group: 0, clock: late, time: 10.2, reduceMotion: false).figure, .dark)
        XCTAssertEqual(Signal.face(.main, group: 0, clock: late, time: 10.7, reduceMotion: false).count, 7, "the countdown stays")
    }

    func testTheLittleGreenManWalksFasterAsTheGreenRunsOut() {
        XCTAssertEqual(Signal.step(left: 32, of: 32), 0.45, accuracy: 1e-9)
        XCTAssertEqual(Signal.step(left: 1, of: 32), 0.13, accuracy: 1e-9)
        var last = Double.infinity
        for left in stride(from: Int64(32), through: 1, by: -1) {
            let step = Signal.step(left: left, of: 32)
            XCTAssertLessThan(step, last + 1e-12)
            last = step
        }
        // Through all seven frames, in turn.
        let c = clock(0)
        let frames = (0..<Signal.frames).map { Signal.face(.main, group: 0, clock: c, time: (Double($0) + 0.5) * 0.45, reduceMotion: false).figure }
        XCTAssertEqual(frames, (0..<Signal.frames).map { .walk($0) })
        // Red: the standing figure, no countdown.
        XCTAssertEqual(Signal.face(.cross, group: 0, clock: c, time: 3, reduceMotion: false), .init(figure: .stop, count: nil))
        // Each junction's group a quarter cycle on: group 1 is at 17 s.
        XCTAssertEqual(Signal.face(.main, group: 1, clock: c, time: 0, reduceMotion: false).count, 15)
    }

    func testStillWithReduceMotionPausedOrTooFast() {
        let late = clock(25)
        // Reduce Motion: no steps, no flashing; the countdown still shows.
        for time in stride(from: 0.0, to: 3, by: 0.1) {
            XCTAssertEqual(Signal.face(.main, group: 0, clock: late, time: time, reduceMotion: true), .init(figure: .walk(0), count: 7))
        }
        // Paused: the same.
        let paused = clock(25, paused: true)
        for time in stride(from: 0.0, to: 3, by: 0.1) {
            XCTAssertEqual(Signal.face(.main, group: 0, clock: paused, time: time, reduceMotion: false), .init(figure: .walk(0), count: 7))
        }
        // Too fast for the lights to change, or no clock: as the traffic
        // signals stand (the main road green), with no countdown.
        for c in [clock(50, speed: .fast), nil] {
            XCTAssertEqual(Signal.face(.main, group: 2, clock: c, time: 1.7, reduceMotion: false), .init(figure: .walk(0), count: nil))
            XCTAssertEqual(Signal.face(.cross, group: 2, clock: c, time: 1.7, reduceMotion: false), .init(figure: .stop, count: nil))
        }
    }

    func testTheRendererDrawsTheFaceAndDigitsTheClockShows() throws {
        let pack = Map3DModelPack.standard
        let models = try XCTUnwrap(Signal.Models(pack: pack))
        let placed = models.placed
        func name(_ model: Int?) -> String? { model.map { pack.models[$0].name } }
        func shown(_ model: Int, _ group: Int, _ c: Timing.Clock?, _ time: Double = 0.1) -> String? {
            name(models.model(model, group: group, clock: c, time: time, reduceMotion: false))
        }
        // Beside the main road at 0 s: walking, 32 left.
        let main = Signal.group(0, road: .main), cross = Signal.group(0, road: .cross)
        XCTAssertEqual(Signal.junction(of: cross).group, 0)
        XCTAssertEqual(Signal.junction(of: cross).road, .cross)
        XCTAssertEqual(shown(placed.head, main, clock(0)), "walk-0")
        XCTAssertEqual(shown(placed.tens, main, clock(0)), "walk-tens-3")
        XCTAssertEqual(shown(placed.ones, main, clock(0)), "walk-ones-2")
        // Under ten: no tens.
        XCTAssertNil(shown(placed.tens, main, clock(25)))
        XCTAssertEqual(shown(placed.ones, main, clock(25)), "walk-ones-7")
        XCTAssertEqual(shown(placed.head, main, clock(25), 0.7), "walk-dark")
        // Beside the crossing road: red, no digits.
        XCTAssertEqual(shown(placed.head, cross, clock(0)), "walk-stop")
        XCTAssertNil(shown(placed.tens, cross, clock(0)))
        XCTAssertNil(shown(placed.ones, cross, clock(0)))
        // Any other model is drawn as it is.
        let tree = try XCTUnwrap(pack.index(of: Map3DProp.tree.modelName))
        XCTAssertEqual(models.model(tree, group: 0, clock: clock(0), time: 0, reduceMotion: false), tree)
        XCTAssertFalse(models.places(tree))
        // The budget counts each signal's most: a face and two digits.
        let runs = Map3DPropRuns([placed.head, placed.tens, placed.ones, placed.head, placed.tens, placed.ones, tree].map {
            Map3DInstance.prop($0, at: .zero, forward: Map3DPoint(1, 0, 0), scale: 1, tint: 0xFFFF_FFFF)
        }).runs
        let heads = pack.models.filter { $0.name == "walk-stop" || $0.name == "walk-dark" || $0.name.hasPrefix("walk-") && Int($0.name.dropFirst(5)) != nil }
        XCTAssertEqual(heads.count, 2 + Signal.frames)
        func most(_ prefix: String) -> Int { pack.models.filter { $0.name.hasPrefix(prefix) }.map(\.triangleCount).max()! }
        XCTAssertEqual(models.triangles(runs, in: pack), 2 * (heads.map(\.triangleCount).max()! + most("walk-tens-") + most("walk-ones-")))
    }

    func testTheModelsAreSmallAndLightTheRightFigure() throws {
        let pack = Map3DModelPack.standard
        let named = Dictionary(uniqueKeysWithValues: pack.models.filter { $0.name.hasPrefix("walk-") }.map { ($0.name, $0) })
        XCTAssertEqual(named.count, Signal.modelCount)
        let stop = try XCTUnwrap(named["walk-stop"]), dark = try XCTUnwrap(named["walk-dark"]), walk = try XCTUnwrap(named["walk-3"])
        for model in named.values {
            XCTAssertLessThanOrEqual(model.triangleCount, 300, model.name)
        }
        print("Decision 445 models' triangles:", named.mapValues(\.triangleCount).sorted { $0.key < $1.key })
        // The red figure glows over the green (article 202): lit red high
        // up, lit green below; the dark face glows nowhere.
        func glowHeights(_ model: Map3DModelPack.Model) -> [Float] { model.vertices.filter(\.glows).map(\.z) }
        XCTAssertTrue(glowHeights(dark).isEmpty)
        XCTAssertGreaterThan(try XCTUnwrap(glowHeights(stop).min()), 2.6)
        XCTAssertLessThan(try XCTUnwrap(glowHeights(walk).max()), 2.6)
        // Article 220: the head 2.1–3 m up.
        // (The pack's models stand on z, their front toward +y.)
        let heights = stop.vertices.map(\.z)
        XCTAssertGreaterThanOrEqual(heights.filter { $0 > 2 }.min()!, 2.1)
        XCTAssertLessThanOrEqual(heights.max()!, 3)
        // Each digit lights its segments: 8 the most, 1 the fewest.
        let eight = try XCTUnwrap(named["walk-ones-8"]), one = try XCTUnwrap(named["walk-ones-1"])
        XCTAssertGreaterThan(eight.triangleCount, one.triangleCount)
        XCTAssertTrue(eight.vertices.allSatisfy(\.glows))
    }

    func testTwoFaceEachOtherAtEachEndOfACrossing() throws {
        var builder = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000), world: GameWorld.newGame())
        let everywhere = Map3DBaseMap.Bounds(minX: -10_000, minZ: -10_000, maxX: 10_000, maxZ: 10_000)
        func road(_ kind: Map3DBaseMap.RoadKind, _ points: [(Double, Double)]) -> Map3DBaseMap.Road {
            Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Point(x: $0.0, z: $0.1) }, bounds: everywhere)
        }
        var taken = Set<Map3DScene.ChunkKey>()
        builder.addRoads([road(.primary, [(-200, 0), (0, 0), (200, 0)]), road(.secondary, [(0, -200), (0, 0), (0, 200)])], taking: &taken)
        let models = try XCTUnwrap(Builder.walkModels)
        let instances = builder.props.values.flatMap { $0 }
        let heads = instances.filter { $0.model == models.placed.head }
        // Four crossings, a signal at each end.
        XCTAssertEqual(heads.count, 8)
        XCTAssertEqual(instances.filter { $0.model == models.placed.tens }.count, 8)
        XCTAssertEqual(instances.filter { $0.model == models.placed.ones }.count, 8)
        let junction = Timing.group(at: Point(x: 0, z: 0))
        // Those crossing the primary road (on the arms along x) walk
        // beside the secondary, the crossing road; and the other way.
        for head in heads {
            let x = head.transform[12], z = head.transform[14]
            let crossesMain = abs(x) > abs(z)
            XCTAssertEqual(head.group, Signal.group(junction, road: crossesMain ? .cross : .main), "\(x), \(z)")
            // Off the road: past its half width, on the pavement.
            XCTAssertGreaterThan(Double(crossesMain ? abs(z) : abs(x)), Double((crossesMain ? Map3DBaseMap.RoadKind.primary : .secondary).width(ramp: false)) / 2)
            // Its partner across the road, the face looking at it.
            let partner = try XCTUnwrap(heads.first { other in
                other.transform != head.transform && abs((crossesMain ? other.transform[12] : other.transform[14]) - (crossesMain ? x : z)) < 1e-3
            })
            let toward = (partner.transform[12] - x, partner.transform[14] - z)
            let looks = (head.transform[4], head.transform[6]) // the model's +y
            XCTAssertGreaterThan(looks.0 * toward.0 + looks.1 * toward.1, 0, "\(x), \(z) looks away")
        }
    }

    func testTheBudgetTakesTheSignalsAndDropsThemWithTheStreets() {
        XCTAssertTrue(Map3DMotionBudget(tier: .standard).drawsPedestrianSignals)
        XCTAssertTrue(Map3DMotionBudget(tier: .lower, step: .fewerOnStreets).drawsPedestrianSignals)
        XCTAssertFalse(Map3DMotionBudget(tier: .lower, step: .fewestOnStreets).drawsPedestrianSignals)
        XCTAssertFalse(Map3DMotionBudget(tier: nil).drawsPedestrianSignals)
        // Their triangles come out of the streets' room.
        let busy = Map3DMotionBudget(tier: .lower, trainTriangles: Map3DDeviceTier.lower.triangles / 2)
        var withSignals = busy
        withSignals.signalTriangles = Map3DDeviceTier.lower.triangles / 4
        XCTAssertLessThan(withSignals.limits().people + withSignals.limits().vehicles, busy.limits().people + busy.limits().vehicles)
    }
}
