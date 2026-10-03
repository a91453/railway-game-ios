import Foundation
@testable import GameCore
import XCTest

/// A service's runs (Phase 4.7 Stage W2c, ARCHITECTURE decision 40): the
/// least whole second a performance builds a running curve for, the
/// performances themselves, a run as it is saved, and a train following one
/// from call to call.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run. With the standard performance (1.5 and
/// 2.5 km/h a second: 26⅔ and 44⁴⁄₉ units a second², so 1/a + 1/b = 0.06 s²
/// a unit) a train that never reaches its top speed runs L units in at
/// least √(2L × 0.06) s, accelerating for 5/8 of that time; 1 km/h is 160/9
/// units a second. Where a train is between calls is read off the curve
/// with `runDistance(_:in:after:)`.
final class ServiceRunTests: XCTestCase {
    // A line along y = 1 with dead ends at both ends, on the track network
    // (Stage F3b): a node at each tile centre, a to g, edges 1 to 6 of 1024
    // between them.
    //
    //   Alpha(1,0)  Beta(3,0)  Gamma(5,0)
    //       |           |          |
    //   a - b - c - d - e - f - g
    //
    // Platforms either side of b, d and f; two edges, 2048, between each.
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let one = TrainID(rawValue: 1)

    private func makeWorld(speed: GameSpeed = .x10) throws -> GameWorld {
        var world = try GameWorld(
            width: 8, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: speed)
        )
        try line.build(in: &world)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try line.buildStation(named: name, beside: x, at: 0, in: &world)
        }
        try world.purchaseTrain(named: "Local")
        try world.placeTrain(one, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(one, to: 1024)
        return world
    }

    /// Alpha to Beta: arrival 0, leaving at `leaving`, and at Beta from
    /// `arriving` to `arriving` (seconds), started at 0.
    private func makeServiceWorld(leaving: Int64, arriving: Int64, speed: GameSpeed = .x10) throws -> GameWorld {
        var world = try makeWorld(speed: speed)
        try world.setTrainTimetable(one, to: [
            ScheduledStop(station: alpha, arrival: .zero, departure: GameTime(seconds: leaving)),
            ScheduledStop(station: beta, arrival: GameTime(seconds: arriving), departure: GameTime(seconds: arriving)),
        ])
        try world.startTrainService(one)
        return world
    }

    private func advance(_ world: inout GameWorld, to second: Int64) throws {
        try world.advance(ticks: Int(second - world.clock.now.seconds))
    }

    private func train(_ world: GameWorld) throws -> Train {
        try XCTUnwrap(world.train(id: one))
    }

    // MARK: - The least seconds

    func testTheLeastSecondsAreTheFastestRunRoundedUp() {
        let cases: [(length: Int64, performance: TrainPerformance, seconds: Int64, why: String)] = [
            (1, .standard, 1, "√0.12 = 0.35"),
            (1_024, .standard, 12, "√122.88 = 11.09"),
            (2_048, .standard, 16, "√245.76 = 15.68"),
            (4_096, .standard, 23, "√491.52 = 22.17"),
            (8_192, .standard, 32, "√983.04 = 31.35"),
            // 3.96 and 4.68 km/h a second: 70.4 and 83.2 units a second²,
            // 1/a + 1/b = 0.026224; 80 km/h is never reached.
            (2_048, .metro, 11, "√107.41 = 10.36"),
            (4_096, .metro, 15, "√214.83 = 14.66"),
            // 0.7 and 1.1 km/h a second: 1/a + 1/b = 0.131494.
            (2_048, .forestRailway, 24, "√538.6 = 23.21"),
            // 2 km/h, 35.56 units a second: 2048 ÷ 35.56 = 57.6 s at it,
            // and 35.56 × 0.06 ÷ 2 = 1.07 s lost speeding up and slowing
            // down.
            (2_048, TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 2), 59, "58.67"),
            // 110 km/h, 1955.6 units a second, is reached: 1,048,576 ÷
            // 1955.6 = 536.2 s, and 1955.6 × 0.03 = 58.67 s lost.
            (1_048_576, .standard, 595, "594.9"),
        ]
        for (length, performance, seconds, why) in cases {
            XCTAssertEqual(RunningCurve.leastSeconds(length: length, performance: performance), seconds, "\(length) units: \(why)")
        }
    }

    /// The least second is the first a curve is built for, and every longer
    /// one up to the longest has one too (the search halves the range on
    /// that).
    func testEveryDurationFromTheLeastBuildsACurve() throws {
        let performances: [TrainPerformance] = [.standard, .metro, .highSpeed, .forestRailway, .dieselRailcar]
        for performance in performances {
            for length: Int64 in [1, 700, 2_048, 45_258, 1 << 20] {
                let least = try XCTUnwrap(RunningCurve.leastSeconds(length: length, performance: performance))
                if least > 1 {
                    XCTAssertNil(RunningCurve(length: length, duration: (least - 1) * 1000, performance: performance), "\(length) in \(least - 1) s")
                }
                for seconds in Array(least...(least + 120)) + [least * 3, RunningCurve.maximumSeconds] {
                    XCTAssertNotNil(RunningCurve(length: length, duration: seconds * 1000, performance: performance), "\(length) in \(seconds) s")
                }
            }
        }
    }

    func testThereIsNoLeastSecondWhereNoCurveFits() {
        XCTAssertNil(RunningCurve.leastSeconds(length: 0, performance: .standard))
        XCTAssertNil(RunningCurve.leastSeconds(length: RunningCurve.maximumLength + 1, performance: .standard))
        // At 1 km/h 2^40 units take 2^40 × 9 ÷ 160 = 61,847,529,063 s, far
        // beyond the longest run, 4,294,967 s.
        XCTAssertEqual(RunningCurve.maximumSeconds, 4_294_967)
        XCTAssertNil(RunningCurve.leastSeconds(length: RunningCurve.maximumLength, performance: TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 1)))
    }

    // MARK: - Performances

    /// Every preset is valid; the metro game's trains are 1.1 and 1.3 m/s²
    /// (3.96 and 4.68 km/h a second) and its lines' design speed, 80 km/h.
    /// A performance is valid with every rate and the top speed from 1 to
    /// 2^20, and a coast slowing the train less than its braking, to a ratio
    /// below 1000.
    func testPerformancesAreValidOnlyWithinTheirLimits() {
        let presets: [TrainPerformance] = [
            .standard, .metro, .local, .express, .semiExpress, .ordinary, .highSpeed, .dieselRailcar, .dieselExpress,
            .forestRailway, .tiltingTaroko, .tiltingPuyuma, .pushPull, .emu3000,
        ]
        XCTAssertTrue(presets.allSatisfy(\.isValid))
        XCTAssertEqual(TrainPerformance.metro, TrainPerformance(acceleration: 3_960, braking: 4_680, topSpeed: 80))

        let limit = RunningCurve.maximumRate
        XCTAssertTrue(TrainPerformance(acceleration: 1, braking: 1, topSpeed: 1).isValid)
        XCTAssertTrue(TrainPerformance(acceleration: limit, braking: limit, topSpeed: limit).isValid)
        XCTAssertTrue(TrainPerformance(acceleration: 1, braking: 2, topSpeed: 1, coast: TrainPerformance.Coast(deceleration: 1, speedRatio: 0)).isValid)
        XCTAssertTrue(TrainPerformance(acceleration: 1, braking: 2, topSpeed: 1, coast: TrainPerformance.Coast(deceleration: 1, speedRatio: 999)).isValid)
        for invalid in [
            TrainPerformance(acceleration: 0, braking: 2_500, topSpeed: 110),
            TrainPerformance(acceleration: 1_500, braking: -1, topSpeed: 110),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 0),
            TrainPerformance(acceleration: limit + 1, braking: 2_500, topSpeed: 110),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, alternativeAcceleration: 0),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, alternativeBraking: limit + 1),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, coast: TrainPerformance.Coast(deceleration: 2_500, speedRatio: 500)),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, coast: TrainPerformance.Coast(deceleration: 0, speedRatio: 500)),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, coast: TrainPerformance.Coast(deceleration: 100, speedRatio: 1_000)),
            TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 110, coast: TrainPerformance.Coast(deceleration: 100, speedRatio: -1)),
        ] {
            XCTAssertFalse(invalid.isValid, "\(invalid)")
        }
    }

    /// A performance is saved with only the values it has; one that is not
    /// valid, or with an explicit `null`, is rejected.
    func testPerformancesSaveAsTheyAreAndBadOnesAreRefused() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try encoder.encode(TrainPerformance.standard), as: UTF8.self), #"{"acceleration":1500,"braking":2500,"topSpeed":110}"#)
        let full = TrainPerformance(
            acceleration: 1_500, braking: 2_500, topSpeed: 110, alternativeAcceleration: 1_800, alternativeBraking: 3_000,
            coast: TrainPerformance.Coast(deceleration: 200, speedRatio: 450)
        )
        let data = try encoder.encode(full)
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            #"{"acceleration":1500,"alternativeAcceleration":1800,"alternativeBraking":3000,"braking":2500,"coast":{"deceleration":200,"speedRatio":450},"topSpeed":110}"#
        )
        XCTAssertEqual(try JSONDecoder().decode(TrainPerformance.self, from: data), full)
        for bad in [
            #"{"acceleration":0,"braking":2500,"topSpeed":110}"#,
            #"{"acceleration":1500,"braking":2500}"#,
            #"{"acceleration":1500,"braking":2500,"topSpeed":110,"coast":null}"#,
            #"{"acceleration":1500,"braking":2500,"topSpeed":110,"alternativeBraking":null}"#,
            #"{"acceleration":1500,"braking":2500,"topSpeed":110,"coast":{"deceleration":2500,"speedRatio":450}}"#,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(TrainPerformance.self, from: Data(bad.utf8)), bad)
        }
    }

    // MARK: - Runs as saved

    /// A run is `{"length", "seconds", "start"}`: at least 1 unit, 1 to the
    /// longest run's seconds; it ends `seconds` after it started, never past
    /// the clock's last second.
    func testARunIsSavedAndCheckedOnItsOwn() throws {
        let run = ServiceRun(start: GameTime(seconds: 60), length: 2_048, seconds: 120)
        XCTAssertEqual(run.end, GameTime(seconds: 180))
        XCTAssertEqual(ServiceRun(start: GameTime(seconds: .max - 5), length: 1, seconds: 10).end, GameTime(seconds: .max))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(run)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"length":2048,"seconds":120,"start":60}"#)
        XCTAssertEqual(try JSONDecoder().decode(ServiceRun.self, from: data), run)
        for bad in [
            #"{"length":0,"seconds":120,"start":60}"#,
            #"{"length":2048,"seconds":0,"start":60}"#,
            #"{"length":2048,"seconds":4294968,"start":60}"#,
            #"{"length":2048,"start":60}"#,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(ServiceRun.self, from: Data(bad.utf8)), bad)
        }
        XCTAssertNotNil(try JSONDecoder().decode(ServiceRun.self, from: Data(#"{"length":2048,"seconds":4294967,"start":60}"#.utf8)))
    }

    // MARK: - Following a run

    /// Leaving Alpha at 60 for Beta at 180, the train runs the two links in
    /// the 120 s its timetable gives it: it arrives at 180, on time, and in
    /// between it is where the curve has taken it.
    func testATrainOnTimeKeepsToItsRunAndArrivesOnTime() throws {
        var world = try makeServiceWorld(leaving: 60, arriving: 180)
        try advance(&world, to: 60)
        XCTAssertNil(try train(world).times?.run, "waiting, it has no run")
        try advance(&world, to: 61)
        XCTAssertEqual(try train(world).execution, .travellingToStop(1))
        XCTAssertEqual(try train(world).times?.run, ServiceRun(start: GameTime(seconds: 60), length: 2_048, seconds: 120))
        XCTAssertEqual(try train(world).position, line.between(1, 2, offset: runDistance(2_048, in: 120, after: 1)))
        // Halfway through the time, not quite halfway along: it lost more
        // speeding up (1.5 km/h a second) than it will slowing down (2.5).
        try advance(&world, to: 120)
        let halfway = runDistance(2_048, in: 120, after: 60)
        XCTAssertLessThan(halfway, 1_024)
        XCTAssertEqual(try train(world).position, line.between(1, 2, offset: halfway))
        XCTAssertEqual(world.lateness(of: one), 0)
        try advance(&world, to: 179)
        XCTAssertEqual(try train(world).execution, .travellingToStop(1))
        try advance(&world, to: 180)
        XCTAssertEqual(try train(world).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(world).position, line.at(3, facingEast: true))
        XCTAssertEqual(try train(world).times, ServiceTimes(arrival: GameTime(seconds: 180), departure: GameTime(seconds: 60)))
        XCTAssertEqual(world.lateness(of: one), 0)
    }

    /// Given 10 s for two links, which take at least 16, the run takes 16:
    /// it reaches Beta at 76, 6 s late.
    func testARunTooTightForTheTrainTakesTheLeastAndArrivesLate() throws {
        var world = try makeServiceWorld(leaving: 60, arriving: 70)
        try advance(&world, to: 61)
        XCTAssertEqual(try train(world).times?.run, ServiceRun(start: GameTime(seconds: 60), length: 2_048, seconds: 16))
        // Accelerating for its first 8 s, to 213⅓ units a second (12 km/h):
        // a·t²/2 = 26⅔ × 9 ÷ 2 = 120 after 3 s.
        try advance(&world, to: 63)
        XCTAssertEqual(try train(world).position, line.between(1, 2, offset: 120))
        try advance(&world, to: 75)
        XCTAssertEqual(world.lateness(of: one), 5, "75 - 70")
        try advance(&world, to: 76)
        XCTAssertEqual(try train(world).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(world).times?.arrival, GameTime(seconds: 76))
    }

    /// Scheduled to leave at 0 and arrive at 120, the service dwells its
    /// 42 s first: the run takes the 120 s from 42, so the train arrives
    /// at 162, as late as it left.
    func testALateDepartureShiftsTheWholeRun() throws {
        var world = try makeServiceWorld(leaving: 0, arriving: 120)
        try advance(&world, to: 43)
        XCTAssertEqual(try train(world).times?.run, ServiceRun(start: GameTime(seconds: 42), length: 2_048, seconds: 120))
        try advance(&world, to: 100)
        XCTAssertEqual(world.lateness(of: one), 42)
        XCTAssertEqual(try train(world).position, line.between(1, 2, offset: runDistance(2_048, in: 120, after: 58)))
        try advance(&world, to: 161)
        XCTAssertEqual(world.lateness(of: one), 42, "left 42 s late; 41 s past its arrival")
        try advance(&world, to: 162)
        XCTAssertEqual(try train(world).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(world).times?.arrival, GameTime(seconds: 162))
        XCTAssertEqual(world.lateness(of: one), 42)
    }

    /// The run the service sets off on: the scheduled seconds when a curve
    /// fits them; the least when none does, or when they are not 1 to the
    /// longest run; none when no curve fits at all, and the train then goes
    /// at its rate.
    func testTheRunIsTheScheduledTimeTheLeastOrNone() throws {
        let world = try makeWorld()
        let local = try train(world)
        let now = world.clock.now
        XCTAssertEqual(world.run(of: local, length: 2_048, scheduled: 600), ServiceRun(start: now, length: 2_048, seconds: 600))
        for scheduled: Int64? in [nil, 0, -5, 15, RunningCurve.maximumSeconds + 1] {
            XCTAssertEqual(world.run(of: local, length: 2_048, scheduled: scheduled), ServiceRun(start: now, length: 2_048, seconds: 16), "\(String(describing: scheduled))")
        }
        XCTAssertEqual(world.run(of: local, length: 2_048, scheduled: RunningCurve.maximumSeconds), ServiceRun(start: now, length: 2_048, seconds: RunningCurve.maximumSeconds))
        XCTAssertNil(world.run(of: local, length: RunningCurve.maximumLength + 1, scheduled: 600))
    }

    /// A run so slow that the train goes a whole minute and more without
    /// moving: two links in 1,200,000 s, one unit about every 586 s. Batches
    /// of idle minutes still stop for the second the curve takes it on, so
    /// a long batch is the same as single ticks and the train is where the
    /// curve puts it.
    func testASlowRunIsNotSkippedByIdleMinutes() throws {
        var batch = try makeServiceWorld(leaving: 0, arriving: 1_200_000, speed: .normal)
        var single = batch
        try batch.advance(ticks: 120)
        for _ in 0..<120 {
            try single.advance(ticks: 1)
        }
        XCTAssertEqual(batch, single)
        let run = ServiceRun(start: GameTime(seconds: 42), length: 2_048, seconds: 1_200_000)
        XCTAssertEqual(try train(batch).times?.run, run)
        let along = runDistance(2_048, in: 1_200_000, after: 120 * 60 - 42)
        XCTAssertGreaterThan(along, 0)
        XCTAssertEqual(try train(batch).position, line.between(1, 2, offset: along))
    }
}
