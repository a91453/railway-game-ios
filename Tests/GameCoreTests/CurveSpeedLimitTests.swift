@testable import GameCore
import XCTest

/// Decision 217: curve speed limits from an edge's radius, and the running
/// curve that keeps to them.
final class CurveSpeedLimitTests: XCTestCase {
    // MARK: - The rule

    func testTheRuleIsFourPointFourTimesTheRootOfTheRadiusInStepsOfFive() {
        // √(19.4·R), rounded down to 5 km/h.
        let cases: [(Int64, Int64?)] = [
            (0, 15), (10, 15), (50, 30), (100, 40), (300, 75), (400, 85), (600, 105),
            (800, 120), (1000, 135), (2000, 195), (4600, 295), (6250, 345), (8000, 390), (9000, nil),
        ]
        for (radius, speed) in cases {
            XCTAssertEqual(CurveSpeedLimit.speed(radiusMetres: radius), speed, "radius \(radius) m")
        }
    }

    // MARK: - An edge's limits

    /// A quarter circle of `metres` from (0, 0) heading east to (R, R)
    /// heading north, as the usual cubic (control points 0.5523 R along the
    /// tangents).
    private func quarter(metres: Int64) -> (PlanPoint, PlanPoint, TrackCurve) {
        let r = metres * WorldCoordinate.unitsPerMetre
        let k = r * 5523 / 10_000
        return (PlanPoint(x: 0, y: 0), PlanPoint(x: r, y: r), .cubic(PlanPoint(x: k, y: 0), PlanPoint(x: r, y: r - k)))
    }

    private func limits(_ start: PlanPoint, _ end: PlanPoint, _ curve: TrackCurve) throws -> (TrackGeometry, [TrackSpeedLimit]) {
        let geometry = try XCTUnwrap(TrackGeometry(from: WorldCoordinate(x: start.x, y: start.y), to: WorldCoordinate(x: end.x, y: end.y), curve: curve))
        return (geometry, CurveSpeedLimit.limits(of: geometry, curve: curve))
    }

    func testAQuarterCircleIsLimitedAllAlongByItsRadius() throws {
        for (metres, speed) in [(Int64(80), Int64(35)), (300, 75), (400, 85), (1000, 135), (4600, 295)] {
            let (start, end, curve) = quarter(metres: metres)
            let (geometry, found) = try limits(start, end, curve)
            // The cubic is not quite a circle: its ends turn a little more
            // gently, by up to a step.
            XCTAssertEqual(found.first?.start, 0)
            XCTAssertEqual(found.last?.end, geometry.length)
            XCTAssertEqual(found.map(\.speed).min(), speed, "radius \(metres) m")
            XCTAssertTrue(found.allSatisfy { $0.speed <= speed + CurveSpeedLimit.step }, "radius \(metres) m")
            XCTAssertTrue(zip(found, found.dropFirst()).allSatisfy { $0.end == $1.start })
        }
    }

    func testAStraightOrGentleEdgeHasNoLimit() throws {
        XCTAssertEqual(try limits(PlanPoint(x: 0, y: 0), PlanPoint(x: 64_000, y: 0), .straight).1, [])
        // A cubic along a straight line has no curvature.
        XCTAssertEqual(try limits(PlanPoint(x: 0, y: 0), PlanPoint(x: 64_000, y: 0),
                                  .cubic(PlanPoint(x: 20_000, y: 0), PlanPoint(x: 40_000, y: 0))).1, [])
        // Radius 10 km: no train runs faster than its 440 km/h.
        let (start, end, curve) = quarter(metres: 10_000)
        XCTAssertEqual(try limits(start, end, curve).1, [])
    }

    func testAnSCurveIsLimitedWhereItBendsAndFreeWhereItTurnsOver() throws {
        // East from (0, 0), across to (2 km, 400 m) heading east again.
        let (geometry, found) = try limits(PlanPoint(x: 0, y: 0), PlanPoint(x: 128_000, y: 25_600),
                                           .cubic(PlanPoint(x: 64_000, y: 0), PlanPoint(x: 64_000, y: 25_600)))
        XCTAssertFalse(found.isEmpty)
        // In order, apart, within the edge, and the inflection in the middle
        // is not limited.
        for (one, next) in zip(found, found.dropFirst()) {
            XCTAssertLessThanOrEqual(one.end, next.start)
            XCTAssertFalse(one.end == next.start && one.speed == next.speed)
        }
        XCTAssertGreaterThanOrEqual(found[0].start, 0)
        XCTAssertLessThanOrEqual(found[found.count - 1].end, geometry.length)
        let middle = geometry.length / 2
        XCTAssertFalse(found.contains { $0.start < middle && middle < $0.end && $0.speed < 200 })
    }

    /// Against the radius worked out in `Double` from the same cubic (the
    /// loupe's way, decision 204): a deterministic sweep of cubics, each
    /// limit within one step of the floating-point one.
    func testTheIntegerCurvatureAgreesWithFloatingPoint() {
        var seed: UInt64 = 0x2017_0217
        func next(_ range: Int64) -> Int64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int64((seed >> 33) % UInt64(range)) - range / 2
        }
        for _ in 0..<400 {
            let scale = [Int64(4_000), 40_000, 400_000, 4_000_000][Int(abs(next(8)) % 4)]
            let p0 = PlanPoint(x: 0, y: 0)
            let c1 = PlanPoint(x: scale / 3 + abs(next(scale / 4)) + 1, y: next(scale / 3))
            let c2 = PlanPoint(x: 2 * scale / 3 + next(scale / 4), y: next(scale))
            let p3 = PlanPoint(x: scale, y: next(scale))
            let a = c1.vector(from: p0), b = c2.vector(from: c1), c = p3.vector(from: c2)
            for step in Int64(0)...64 {
                let t = Double(step) / 64, u = 1 - t
                let p = [p0, c1, c2, p3].map { (x: Double($0.x), y: Double($0.y)) }
                let d1x = 3 * (u * u * (p[1].x - p[0].x) + 2 * u * t * (p[2].x - p[1].x) + t * t * (p[3].x - p[2].x))
                let d1y = 3 * (u * u * (p[1].y - p[0].y) + 2 * u * t * (p[2].y - p[1].y) + t * t * (p[3].y - p[2].y))
                let d2x = 6 * (u * (p[2].x - 2 * p[1].x + p[0].x) + t * (p[3].x - 2 * p[2].x + p[1].x))
                let d2y = 6 * (u * (p[2].y - 2 * p[1].y + p[0].y) + t * (p[3].y - 2 * p[2].y + p[1].y))
                let cross = abs(d1x * d2y - d1y * d2x)
                let speed = (d1x * d1x + d1y * d1y).squareRoot()
                let integer = CurveSpeedLimit.speed(at: step, a: a, b: b, c: c)
                guard cross > 0, speed > 0 else { continue }
                let metres = speed * speed * speed / cross / 64
                let raw = (19.4 * metres).squareRoot()
                guard raw < 399 else {
                    XCTAssertTrue(integer == nil || integer! >= 395)
                    continue
                }
                let expected = max(15, Int64(raw) / 5 * 5)
                let found = integer ?? 400
                XCTAssertLessThanOrEqual(abs(found - expected), 5, "step \(step) of \(p0) \(c1) \(c2) \(p3)")
            }
        }
    }

    func testAnEdgeKeepsItsLimitsWhenBuiltAndLoaded() throws {
        var world = try GameWorld(
            bounds: WorldBounds(width: 65_536, height: 65_536),
            economy: GameEconomy(balance: 100_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500))
        )
        let (start, end, curve) = quarter(metres: 300)
        let offset: Int64 = 4_096
        let a = try world.buildTrackNode(at: WorldCoordinate(x: start.x + offset, y: start.y + offset))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: end.x + offset, y: end.y + offset))
        guard case .cubic(let c1, let c2) = curve else { return XCTFail() }
        let id = try world.buildTrackEdge(from: a, to: b, curve: .cubic(PlanPoint(x: c1.x + offset, y: c1.y + offset),
                                                                      PlanPoint(x: c2.x + offset, y: c2.y + offset)))
        let edge = try XCTUnwrap(world.network.edge(id))
        XCTAssertEqual(edge.speedLimits, [TrackSpeedLimit(start: 0, end: edge.length, speed: 75)])
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        XCTAssertEqual(loaded.network.edge(id)?.speedLimits, edge.speedLimits)
    }

    func testARunMeetsTheLimitsOfTheEdgesAlongItsPathEachWayAndUntilItsTailIsOut() throws {
        var world = try GameWorld(
            bounds: WorldBounds(width: 131_072, height: 131_072),
            economy: GameEconomy(balance: 100_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500))
        )
        // 1 km straight east, then a quarter circle of 300 m north.
        let r: Int64 = 300 * 64, k = r * 5523 / 10_000
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 4_096, y: 4_096))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 4_096 + 64_000, y: 4_096))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 4_096 + 64_000 + r, y: 4_096 + r))
        let straight = try world.buildTrackEdge(from: a, to: b)
        let bend = try world.buildTrackEdge(from: b, to: c, curve: .cubic(PlanPoint(x: 4_096 + 64_000 + k, y: 4_096),
                                                                         PlanPoint(x: 4_096 + 64_000 + r, y: 4_096 + r - k)))
        let edge = try XCTUnwrap(world.network.edge(bend))
        let network = world.network
        // From 200 m along the straight to the end of the bend.
        let out = network.speedLimits(from: TrackTraversal(edge: straight, direction: .forward), offset: 12_800,
                                      through: [TrackTraversal(edge: bend, direction: .forward)],
                                      distance: 51_200 + edge.length, trailing: 6_400)
        XCTAssertEqual(out.first?.start, 51_200)
        XCTAssertEqual(out.last?.end, 51_200 + edge.length)
        XCTAssertEqual(out.map(\.speed).min(), 75)
        // Back: from the end of the bend to 200 m along the straight; the
        // limits hold 100 m past the bend.
        let back = network.speedLimits(from: TrackTraversal(edge: bend, direction: .backward), offset: 0,
                                       through: [TrackTraversal(edge: straight, direction: .backward)],
                                       distance: edge.length + 51_200, trailing: 6_400)
        XCTAssertEqual(back.first?.start, 0)
        XCTAssertEqual(back.map(\.end).max(), edge.length + 6_400)
        XCTAssertEqual(back.map(\.speed).min(), 75)
        // A run counts only the track ahead of its head: a curve behind,
        // where the tail may still be, is not counted.
        XCTAssertEqual(network.speedLimits(from: TrackTraversal(edge: straight, direction: .backward), offset: 3_200,
                                           through: [], distance: 30_000, trailing: 6_400), [])
    }

    func testOverlappingLimitsMergeIntoTheLowestOverEachStretch() {
        let limits = [
            TrackSpeedLimit(start: 500, end: 900, speed: 80),
            TrackSpeedLimit(start: 100, end: 400, speed: 60),
            TrackSpeedLimit(start: 300, end: 600, speed: 40),
            TrackSpeedLimit(start: 900, end: 1_200, speed: 80),
            TrackSpeedLimit(start: -50, end: 50, speed: 30),
        ]
        XCTAssertEqual(CurveSpeedLimit.merged(limits, within: 1_000), [
            TrackSpeedLimit(start: 0, end: 50, speed: 30),
            TrackSpeedLimit(start: 100, end: 300, speed: 60),
            TrackSpeedLimit(start: 300, end: 600, speed: 40),
            TrackSpeedLimit(start: 600, end: 1_000, speed: 80),
        ])
        XCTAssertEqual(CurveSpeedLimit.merged([], within: 1_000), [])
    }

    func testAnEdgeIsPostedInAtMostEightStretches() throws {
        // An S-curve whose radius changes all along.
        let (_, found) = try limits(PlanPoint(x: 0, y: 0), PlanPoint(x: 64_000, y: 12_800),
                                    .cubic(PlanPoint(x: 30_000, y: -6_000), PlanPoint(x: 34_000, y: 19_000)))
        XCTAssertFalse(found.isEmpty)
        XCTAssertLessThanOrEqual(found.count, 8)
    }

    // MARK: - The running curve

    private let tenKilometres: Int64 = 640_000

    func testWithoutLimitsItTakesAboutAsLongAsTheReferenceCurve() throws {
        for performance in [TrainPerformance.standard, .local, .emu3000, .forestRailway, .metro] {
            for metres in [Int64(300), 1_000, 5_000, 30_000] {
                let length = metres * 64
                let plain = try XCTUnwrap(RunningCurve.leastSeconds(length: length, performance: performance))
                let limited = try XCTUnwrap(LimitedRunningCurve.leastSeconds(length: length, performance: performance, limits: []))
                XCTAssertLessThanOrEqual(abs(plain - limited), 1, "\(metres) m at \(performance)")
            }
        }
    }

    func testACurveSlowsTheRunDown() throws {
        let free = try XCTUnwrap(LimitedRunningCurve.leastSeconds(length: tenKilometres, performance: .standard, limits: []))
        var previous = free
        for speed in [Int64(100), 80, 60, 40] {
            let limits = [TrackSpeedLimit(start: 256_000, end: 320_000, speed: speed)]
            let seconds = try XCTUnwrap(LimitedRunningCurve.leastSeconds(length: tenKilometres, performance: .standard, limits: limits))
            XCTAssertGreaterThan(seconds, previous, "limit \(speed)")
            previous = seconds
        }
        // A limit above the top speed changes nothing.
        let above = [TrackSpeedLimit(start: 256_000, end: 320_000, speed: 150)]
        XCTAssertEqual(LimitedRunningCurve.leastSeconds(length: tenKilometres, performance: .standard, limits: above), free)
    }

    /// At every tenth of a second: never faster than the limit where it
    /// applies (2 % as the reference's `zoneProfileOk` allows), never
    /// backwards, at the end by the duration, and its time and distance
    /// queries agree.
    private func checkKeepsTo(_ curve: LimitedRunningCurve, limits: [TrackSpeedLimit], file: StaticString = #filePath, line: UInt = #line) {
        var last: Int64 = 0
        var time: Int64 = 0
        while time <= curve.duration {
            let distance = curve.distance(at: time)
            XCTAssertGreaterThanOrEqual(distance, last, "backwards at \(time) ms", file: file, line: line)
            let speed = curve.speed(at: time)
            for limit in limits where limit.start <= distance && distance < limit.end {
                XCTAssertLessThanOrEqual(speed * 100, limit.speed * 102, "\(speed) km/h at \(distance) under \(limit.speed)", file: file, line: line)
            }
            if distance > 0 && distance < curve.length {
                let back = curve.time(atDistance: distance)
                XCTAssertLessThanOrEqual(abs(back - time), 200, "time of \(distance) is \(back), not \(time)", file: file, line: line)
            }
            last = distance
            time += 100
        }
        XCTAssertEqual(curve.distance(at: curve.duration), curve.length, file: file, line: line)
    }

    func testTheTrainBrakesToEachLimitAndAcceleratesAfter() throws {
        let limits = [
            TrackSpeedLimit(start: 128_000, end: 160_000, speed: 60),
            TrackSpeedLimit(start: 150_000, end: 200_000, speed: 75),
            TrackSpeedLimit(start: 400_000, end: 420_000, speed: 40),
        ]
        for performance in [TrainPerformance.standard, .emu3000, .highSpeed] {
            let least = try XCTUnwrap(LimitedRunningCurve.leastSeconds(length: tenKilometres, performance: performance, limits: limits))
            for seconds in [least, least + 30, least * 2] {
                let curve = try XCTUnwrap(LimitedRunningCurve(length: tenKilometres, duration: seconds * 1000,
                                                              performance: performance, limits: limits))
                checkKeepsTo(curve, limits: limits)
            }
            XCTAssertNil(LimitedRunningCurve(length: tenKilometres, duration: (least - 1) * 1000, performance: performance, limits: limits))
        }
    }

    func testTheSpeedFallsBeforeTheCurveBegins() throws {
        let limits = [TrackSpeedLimit(start: 320_000, end: 384_000, speed: 40)]
        let seconds = try XCTUnwrap(LimitedRunningCurve.leastSeconds(length: tenKilometres, performance: .standard, limits: limits))
        let curve = try XCTUnwrap(LimitedRunningCurve(length: tenKilometres, duration: seconds * 1000, performance: .standard, limits: limits))
        // At 110 km/h, braking at 2.5 km/h/s to 40 takes 28 s over 583 m:
        // the train is already slowing 400 m before the curve.
        let before = curve.time(atDistance: 320_000 - 400 * 64)
        XCTAssertLessThan(curve.speed(at: before), 105)
        XCTAssertGreaterThan(curve.speed(at: before), 40)
        // And it is back to its top speed well after it.
        XCTAssertGreaterThanOrEqual(curve.speed(at: curve.time(atDistance: 384_000 + 2_000 * 64)), 105)
    }

    func testALongTimeIsKeptBelowTheLimitsAndAShortOneIsRefused() throws {
        let limits = [TrackSpeedLimit(start: 0, end: 640_000, speed: 60)]
        // 10 km at 60 km/h is 600 s, and reaching it at 1.5 km/h/s and
        // stopping from it at 2.5 cost half their 40 s and 24 s more: 632 s
        // exactly, and the limit's speed rounded down to the curve's scale
        // makes it a whisker over.
        let least = try XCTUnwrap(LimitedRunningCurve.leastSeconds(length: tenKilometres, performance: .standard, limits: limits))
        XCTAssertEqual(least, 633)
        let slow = try XCTUnwrap(LimitedRunningCurve(length: tenKilometres, duration: 3_600_000, performance: .standard, limits: limits))
        checkKeepsTo(slow, limits: limits)
        XCTAssertEqual(Double(slow.distance(at: 1_800_000)) / 6_400, 50, accuracy: 1)
    }

    func testARunCurveIsTheReferenceCurveWithoutALimitBelowTheTopSpeed() throws {
        let above = [TrackSpeedLimit(start: 0, end: 640_000, speed: 110)]
        for limits in [[], above] {
            let curve = try XCTUnwrap(RunCurve(length: tenKilometres, duration: 400_000, performance: .standard, limits: limits))
            XCTAssertEqual(curve, .plain(try XCTUnwrap(RunningCurve(length: tenKilometres, duration: 400_000, performance: .standard))))
            XCTAssertEqual(RunCurve.leastSeconds(length: tenKilometres, performance: .standard, limits: limits),
                           RunningCurve.leastSeconds(length: tenKilometres, performance: .standard))
        }
        let below = [TrackSpeedLimit(start: 100_000, end: 200_000, speed: 60)]
        guard case .limited? = RunCurve(length: tenKilometres, duration: 600_000, performance: .standard, limits: below) else {
            return XCTFail("a limit below the top speed makes a limited curve")
        }
    }

    func testItFitsExactlyWhenACurveIsBuilt() throws {
        let limits = [TrackSpeedLimit(start: 100_000, end: 200_000, speed: 60), TrackSpeedLimit(start: 400_000, end: 410_000, speed: 30)]
        for performance in [TrainPerformance.standard, .highSpeed, .metro] {
            let least = try XCTUnwrap(RunCurve.leastSeconds(length: tenKilometres, performance: performance, limits: limits))
            for seconds in [least - 2, least - 1, least, least + 1, least * 3] {
                XCTAssertEqual(RunCurve.fits(length: tenKilometres, duration: seconds * 1000, performance: performance, limits: limits),
                               RunCurve(length: tenKilometres, duration: seconds * 1000, performance: performance, limits: limits) != nil,
                               "\(seconds) s")
            }
        }
    }
}
