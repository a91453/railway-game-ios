import Foundation
import GameCore
import XCTest

/// Turning round and repeating timetables (Phase 4 Stage Q1, ARCHITECTURE
/// decision 21): a stop can turn the train round as the service leaves it,
/// and a timetable can repeat every period, cycle after cycle. Stage P's
/// rules hold within every cycle.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run. Every train here moves at rate 1024 (one
/// link a minute) and the clock runs at 1x, so after `n` ticks from minute 0
/// the clock reads `n` and the steps of minutes 0 to `n - 1` have run.
final class TrainRepeatTests: XCTestCase {
    // The line of `TrainServiceTests`, dead ends at both ends:
    //
    //   Alpha(1,0)  Beta(3,0)  Gamma(5,0)
    //       |           |          |
    //   a - b - c - d - e - f - g
    //                          |
    //                      Delta(5,2)
    //
    // Platforms: Alpha b, Beta d, and Gamma and Delta share f.
    private let a = GridPosition(x: 0, y: 1)
    private let b = GridPosition(x: 1, y: 1)
    private let c = GridPosition(x: 2, y: 1)
    private let d = GridPosition(x: 3, y: 1)
    private let e = GridPosition(x: 4, y: 1)
    private let f = GridPosition(x: 5, y: 1)
    private let g = GridPosition(x: 6, y: 1)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let delta = StationID(rawValue: 4)
    private let first = TrainID(rawValue: 1)
    private let unknown = TrainID(rawValue: 9)

    private func makeLineWorld(minute: Int64 = 0) throws -> GameWorld {
        var world = try GameWorld(
            width: 8, height: 4,
            economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        try world.buildTrack(at: a, connections: .east)
        for tile in [b, c, d, e, f] {
            try world.buildTrack(at: tile, connections: [.east, .west])
        }
        try world.buildTrack(at: g, connections: .west)
        try world.buildStation(named: "Alpha", at: GridPosition(x: 1, y: 0))
        try world.buildStation(named: "Beta", at: GridPosition(x: 3, y: 0))
        try world.buildStation(named: "Gamma", at: GridPosition(x: 5, y: 0))
        try world.buildStation(named: "Delta", at: GridPosition(x: 5, y: 2))
        try world.purchaseTrain(named: "Shuttle")
        return world
    }

    /// A world whose train stands at `position` with rate 1024 and runs
    /// `stops`, repeating every `period`, from `minute` on.
    private func makeServiceWorld(
        _ stops: [ScheduledStop],
        every period: Int64?,
        at position: TrainPosition,
        minute: Int64 = 0
    ) throws -> GameWorld {
        var world = try makeLineWorld(minute: minute)
        try world.placeTrain(first, at: position)
        try world.setTrainMovementRate(first, to: 1024)
        try world.setTrainTimetable(first, to: stops, repeatingEvery: period)
        try world.startTrainService(first)
        return world
    }

    private func stop(_ station: StationID, _ arrival: Int64, _ departure: Int64, reverses: Bool = false) -> ScheduledStop {
        ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: departure), reverses: reverses)
    }

    /// Alpha to Gamma and back every 12 minutes, turning round at both ends.
    /// Each way is four links, so four minutes.
    private var shuttle: [ScheduledStop] {
        [stop(alpha, 0, 0), stop(gamma, 4, 6, reverses: true), stop(alpha, 10, 12, reverses: true)]
    }

    private func train(in world: GameWorld) throws -> Train {
        try XCTUnwrap(world.train(id: first))
    }

    private func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    // MARK: - Setting a repeating timetable

    func testNewTrainsRunTheirTimetableOnceAndTurnNowhere() throws {
        XCTAssertNil(Train(id: first, name: "A").timetablePeriod)
        XCTAssertFalse(ScheduledStop(station: alpha, arrival: .zero, departure: .zero).reverses)
        let world = try makeLineWorld()
        XCTAssertNil(try train(in: world).timetablePeriod)
    }

    /// A period needs a stop and a minute or more, and the timetable must
    /// not go back when it starts again: the last departure no later than
    /// the first arrival one period later.
    func testAPeriodMustLetTheTimetableStartAgainWithoutGoingBack() throws {
        var world = try makeLineWorld()
        // The shuttle spans 0 to 12, so 12 is the shortest period.
        for period: Int64 in [12, 13, 1440, .max] {
            try world.setTrainTimetable(first, to: shuttle, repeatingEvery: period)
            XCTAssertEqual(try train(in: world).timetablePeriod, period)
            XCTAssertEqual(try train(in: world).timetable, shuttle)
        }
        let before = world
        for period: Int64 in [11, 1, 0, -1, -12, .min] {
            XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: shuttle, repeatingEvery: period), .invalidTimetable)
        }
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [], repeatingEvery: 60), .invalidTimetable)
        XCTAssertEqual(world, before, "refused timetables change nothing")

        // One stop repeats every period at least its dwell; a later first
        // arrival counts from itself, not from minute 0.
        try world.setTrainTimetable(first, to: [stop(alpha, 3, 8)], repeatingEvery: 5)
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(alpha, 3, 8)], repeatingEvery: 4), .invalidTimetable)
        try world.setTrainTimetable(first, to: [stop(alpha, 100, 100), stop(beta, 110, 130)], repeatingEvery: 30)

        // Setting a timetable without a period makes it run once; clearing
        // clears the period too.
        try world.setTrainTimetable(first, to: shuttle)
        XCTAssertNil(try train(in: world).timetablePeriod)
        try world.setTrainTimetable(first, to: shuttle, repeatingEvery: 12)
        try world.setTrainTimetable(first, to: [])
        XCTAssertEqual(try train(in: world).timetable, [])
        XCTAssertNil(try train(in: world).timetablePeriod)
    }

    /// The period is checked with the times, after the train and a running
    /// service, and before the stations.
    func testPeriodChecksRunInTheDocumentedOrder() throws {
        var world = try makeLineWorld()
        let ghost = StationID(rawValue: 99)
        XCTAssertThrowsGameError(try world.setTrainTimetable(unknown, to: shuttle, repeatingEvery: 0), .unknownTrain(unknown))
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(ghost, 0, 0)], repeatingEvery: 0), .invalidTimetable)
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(ghost, 0, 0)], repeatingEvery: 1), .unknownStation(ghost))

        try world.placeTrain(first, at: .atNode(b, heading: .east))
        try world.setTrainTimetable(first, to: shuttle, repeatingEvery: 12)
        try world.startTrainService(first)
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: shuttle, repeatingEvery: 0), .trainServiceActive(first))
    }

    // MARK: - Turning round

    /// Without turning round, a train at a dead-end terminus has no route
    /// back (a route never turns straight back), so its service waits.
    func testATerminusNeedsAStopThatTurnsTheTrainRound() throws {
        var stuck = try makeServiceWorld([stop(gamma, 0, 0), stop(alpha, 4, 4)], every: nil, at: .atNode(f, heading: .east))
        try stuck.advance(ticks: 10)
        XCTAssertEqual(try train(in: stuck).execution, .waitingAtStop(0))
        XCTAssertEqual(try train(in: stuck).position, .atNode(f, heading: .east))

        // Turning round at Gamma: it leaves at minute 0 facing west and
        // reaches b, Alpha's platform, four links later.
        var turning = try makeServiceWorld([stop(gamma, 0, 0, reverses: true), stop(alpha, 4, 4)], every: nil, at: .atNode(f, heading: .east))
        try turning.advance(ticks: 1)
        XCTAssertEqual(try train(in: turning).execution, .travellingToStop(1))
        XCTAssertEqual(try train(in: turning).position, .atNode(e, heading: .west))
        XCTAssertEqual(try train(in: turning).movement.continuation, [e, d, c, b])
        XCTAssertEqual(try train(in: turning).movement.cursor, 1)
        try turning.advance(ticks: 3)
        XCTAssertEqual(try train(in: turning).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(in: turning).position, .atNode(b, heading: .west))
    }

    /// A departure that finds no route after turning round changes nothing:
    /// the train is not left turned, and turns when it can leave.
    func testWithoutARouteTheTrainIsNotLeftTurned() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(f, heading: .east))
        try world.setTrainMovementRate(first, to: 1024)
        try world.setTrainTimetable(first, to: [stop(gamma, 0, 0, reverses: true), stop(alpha, 4, 4)])
        try world.startTrainService(first)
        try world.removeTrack(at: c)

        try world.advance(ticks: 3)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0))
        XCTAssertEqual(try train(in: world).position, .atNode(f, heading: .east))
        XCTAssertEqual(try train(in: world).movement.continuation, [])

        // Rebuilt at minute 3: the step at minute 3 turns it and sets off.
        try world.buildTrack(at: c, connections: [.east, .west])
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1))
        XCTAssertEqual(try train(in: world).position, .atNode(e, heading: .west))
    }

    /// Turning round at the last stop of a timetable that runs once happens
    /// as the service ends there; the train stays, turned.
    func testTheLastStopTurnsTheTrainAsTheServiceEnds() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 0), stop(beta, 2, 3, reverses: true)], every: nil, at: .atNode(b, heading: .east))
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(in: world).position, .atNode(d, heading: .east))
        try world.advance(ticks: 1)
        XCTAssertNil(try train(in: world).execution)
        XCTAssertEqual(try train(in: world).position, .atNode(d, heading: .west))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [beta])
    }

    // MARK: - Repeating

    /// The shuttle runs on time cycle after cycle: out at 0, 12, 24, ...,
    /// at Gamma from 4, 16, ..., back at Alpha from 10, 22, .... Leaving
    /// Alpha at 12 turns the train, starts cycle 1 at Alpha at once (it is
    /// already there) and leaves Alpha again in the same step.
    func testAShuttleRepeatsOnTimeTurningAtBothEnds() throws {
        var world = try makeServiceWorld(shuttle, every: 12, at: .atNode(b, heading: .east))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0))

        try world.advance(ticks: 4)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(in: world).position, .atNode(f, heading: .east))

        try world.advance(ticks: 2)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1), "Gamma is left at 6, not before")

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(2))
        XCTAssertEqual(try train(in: world).position, .atNode(e, heading: .west))

        try world.advance(ticks: 3)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 10))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(2))
        XCTAssertEqual(try train(in: world).position, .atNode(b, heading: .west))

        try world.advance(ticks: 2)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(2), "the last stop is left at 12")

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1, cycle: 1))
        XCTAssertEqual(try train(in: world).position, .atNode(c, heading: .east))
        XCTAssertEqual(try train(in: world).movement.continuation, [c, d, e, f])

        try world.advance(ticks: 3)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 16))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1, cycle: 1))
        XCTAssertEqual(try train(in: world).position, .atNode(f, heading: .east))

        try world.advance(ticks: 9)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 25))
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1, cycle: 2))
        XCTAssertEqual(try train(in: world).position, .atNode(c, heading: .east))

        // The timetable is plan data: it keeps its first cycle's times.
        XCTAssertEqual(try train(in: world).timetable, shuttle)
        XCTAssertEqual(try train(in: world).timetablePeriod, 12)
    }

    /// A late train does not skip a stop or a cycle: it leaves each stop as
    /// soon as it can, and slack in the timetable lets it catch up.
    func testALateShuttleCatchesUpThroughItsSlack() throws {
        // The shuttle has two minutes' slack at each end.
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(b, heading: .east))
        try world.setTrainMovementRate(first, to: 1024)
        try world.setTrainTimetable(first, to: shuttle, repeatingEvery: 12)
        try world.startTrainService(first)
        // Held at Alpha until minute 3 with rate 0: it gets its route at 0
        // but does not move.
        try world.setTrainMovementRate(first, to: 0)
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1))
        XCTAssertEqual(try train(in: world).position, .atNode(b, heading: .east))
        try world.setTrainMovementRate(first, to: 1024)

        // Moves from minute 3: Gamma at 7 (three late), left at 7 (one late),
        // Alpha at 11, left at 12 on time.
        try world.advance(ticks: 4)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 7))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1))
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(2))
        try world.advance(ticks: 3)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 11))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(2))
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(2), "back on time: Alpha is left at 12")
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1, cycle: 1))
    }

    /// A service leaves at most one whole cycle of stops in a step. A train
    /// saved many cycles behind a one-stop timetable, whose every call is at
    /// the same station, goes one cycle further each step rather than
    /// going round without end.
    func testAServiceLeavesAtMostOneCycleOfStopsInAStep() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 0)], every: 1, at: .atNode(b, heading: .east))
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 3), "on time: one call a minute")

        // The same train saved at minute 1000, still in cycle 3.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(world)) as? [String: Any])
        var clock = try XCTUnwrap(object["clock"] as? [String: Any])
        clock["now"] = 1000
        object["clock"] = clock
        var late = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(try train(in: late).execution, .waitingAtStop(0, cycle: 3))
        try late.advance(ticks: 1)
        XCTAssertEqual(try train(in: late).execution, .waitingAtStop(0, cycle: 4))
        try late.advance(ticks: 5)
        XCTAssertEqual(try train(in: late).execution, .waitingAtStop(0, cycle: 9))

        // Two calls a cycle at stations sharing a platform: both each step.
        var shared = try makeServiceWorld([stop(gamma, 0, 0), stop(delta, 0, 0)], every: 1, at: .atNode(f, heading: .east))
        try shared.advance(ticks: 2)
        XCTAssertEqual(try train(in: shared).execution, .waitingAtStop(0, cycle: 2))
    }

    // MARK: - Starting

    /// A repeating timetable starts in the first cycle whose first departure
    /// is not before now; one that runs once always starts in its only
    /// cycle, however late.
    func testARepeatingServiceStartsInTheNextCycleThatLeavesOnTime() throws {
        let timetable = [stop(alpha, 0, 5), stop(beta, 7, 7)]
        let cases: [(minute: Int64, cycle: Int64)] = [(0, 0), (5, 0), (6, 1), (25, 1), (26, 2), (30, 2), (45, 2), (46, 3)]
        for (minute, cycle) in cases {
            let world = try makeServiceWorld(timetable, every: 20, at: .atNode(b, heading: .east), minute: minute)
            XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: cycle), "started at \(minute)")
        }
        let once = try makeServiceWorld(timetable, every: nil, at: .atNode(b, heading: .east), minute: 46)
        XCTAssertEqual(try train(in: once).execution, .waitingAtStop(0))

        // Started at 26 in cycle 2: Alpha is left at 45, Beta reached at 47.
        var world = try makeServiceWorld(timetable, every: 20, at: .atNode(b, heading: .east), minute: 26)
        try world.advance(ticks: 19)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 2))
        try world.advance(ticks: 2)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1, cycle: 2))
        XCTAssertEqual(world.clock.now, GameTime(minutes: 47))
    }

    /// Stopping keeps the timetable and its period; starting again joins
    /// the next cycle that leaves on time.
    func testStoppingAndStartingAgainJoinsTheNextCycle() throws {
        var world = try makeServiceWorld(shuttle, every: 12, at: .atNode(b, heading: .east))
        try world.advance(ticks: 11)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(2))
        try world.stopTrainService(first)
        XCTAssertEqual(try train(in: world).timetablePeriod, 12)
        try world.startTrainService(first)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 1), "cycle 1 leaves Alpha at 12")

        // Taken off the track, the train keeps its period too.
        try world.stopTrainService(first)
        try world.unplaceTrain(first)
        XCTAssertEqual(try train(in: world).timetablePeriod, 12)
    }

    // MARK: - The last cycle

    /// Cycles whose times would pass the largest minute do not exist: a
    /// service starts at the last cycle that fits, however late, and ends
    /// after it instead of starting again.
    func testTheServiceEndsAfterTheLastCycleWhoseTimesFit() throws {
        // Cycles 0 and 1 fit: cycle 1 leaves Alpha at 2^62.
        let period = Int64(1) << 62
        var world = try makeServiceWorld([stop(alpha, 0, 0)], every: period, at: .atNode(b, heading: .east), minute: 1)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 1))
        try world.advance(ticks: Int(period - 1))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 1))
        try world.advance(ticks: 1)
        XCTAssertNil(try train(in: world).execution, "no cycle 2 to start")
        XCTAssertEqual(world.clock.now, GameTime(minutes: period + 1))

        // Only cycle 0 fits when the period is almost the whole range.
        let wide = [stop(alpha, 0, 0), stop(beta, .max - 10, .max - 10)]
        let late = try makeServiceWorld(wide, every: .max - 10, at: .atNode(b, heading: .east), minute: 5)
        XCTAssertEqual(try train(in: late).execution, .waitingAtStop(0))
    }

    // MARK: - Batches

    /// However the time is cut into batches, and at 2x, the shuttle ends up
    /// in the same place.
    func testBatchesSingleTicksAndDoubleSpeedAgree() throws {
        let start = try makeServiceWorld(shuttle, every: 12, at: .atNode(b, heading: .east))
        var batch = start
        try batch.advance(ticks: 1000)
        var single = start
        for _ in 0..<1000 {
            try single.advance(ticks: 1)
        }
        XCTAssertEqual(batch, single)
        var double = start
        double.setSpeed(.double)
        try double.advance(ticks: 500)
        double.setSpeed(.normal)
        XCTAssertEqual(double, batch)

        // 1000 = 83 × 12 + 4: cycle 83 has just reached Gamma.
        XCTAssertEqual(try train(in: batch).execution, .waitingAtStop(1, cycle: 83))
        XCTAssertEqual(try train(in: batch).position, .atNode(f, heading: .east))
    }

    // MARK: - Saving

    /// The period, turning round and the cycle are saved only when used,
    /// so worlds without them save as before, and old saves read as running
    /// once, turning nowhere and in cycle 0.
    func testRepeatsTurnsAndCyclesAreSavedOnlyWhenUsed() throws {
        var world = try makeServiceWorld(shuttle, every: 12, at: .atNode(b, heading: .east))
        var text = String(decoding: try encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""period":12"#), text)
        XCTAssertEqual(text.components(separatedBy: #""reverse":true"#).count, 3, "two stops turn the train")
        XCTAssertFalse(text.contains(#""reverse":false"#), text)
        XCTAssertTrue(text.contains(#""execution":{"phase":"waiting","stop":0}"#), text)

        try world.advance(ticks: 13)
        text = String(decoding: try encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""execution":{"cycle":1,"phase":"travelling","stop":1}"#), text)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: encode(world))
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try encode(loaded), try encode(world))

        // Saved before timetables could repeat or turn trains.
        let old = try JSONDecoder().decode(
            Train.self,
            from: Data(#"{"id": 1, "name": "A", "timetable": [{"station": 1, "arrival": 0, "departure": 0}]}"#.utf8)
        )
        XCTAssertNil(old.timetablePeriod)
        XCTAssertEqual(old.timetable.map(\.reverses), [false])
        let service = try JSONDecoder().decode(TimetableExecution.self, from: Data(#"{"phase": "waiting", "stop": 0}"#.utf8))
        XCTAssertEqual(service.cycle, 0)
        // An explicit false is read as false.
        let explicit = try JSONDecoder().decode(ScheduledStop.self, from: Data(#"{"station": 1, "arrival": 0, "departure": 0, "reverse": false}"#.utf8))
        XCTAssertFalse(explicit.reverses)
    }

    /// Bad periods, turns and cycles are refused when loading, never
    /// repaired.
    func testMalformedRepeatsAndCyclesAreRejectedNotRepaired() throws {
        // The shuttle in cycle 1, travelling to Gamma from c.
        var world = try makeServiceWorld(shuttle, every: 12, at: .atNode(b, heading: .east))
        try world.advance(ticks: 13)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(world)) as? [String: Any])

        func decode(_ change: (inout [String: Any]) -> Void) throws -> GameWorld {
            var object = saved
            var trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
            change(&trains[0])
            object["trains"] = trains
            return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        }

        XCTAssertEqual(try decode { _ in }, world)
        let malformed: [(String, (inout [String: Any]) -> Void)] = [
            ("null period", { $0["period"] = NSNull() }),
            ("period as a string", { $0["period"] = "12" }),
            ("zero period", { $0["period"] = 0 }),
            ("negative period", { $0["period"] = -12 }),
            ("period too short", { $0["period"] = 11 }),
            ("cycle without a period", { $0["period"] = nil }),
            ("null reverse", { train in
                var stops = train["timetable"] as! [[String: Any]]
                stops[0]["reverse"] = NSNull()
                train["timetable"] = stops
            }),
            ("reverse as a string", { train in
                var stops = train["timetable"] as! [[String: Any]]
                stops[0]["reverse"] = "true"
                train["timetable"] = stops
            }),
            ("negative cycle", { $0["execution"] = ["phase": "travelling", "stop": 1, "cycle": -1] }),
            ("null cycle", { $0["execution"] = ["phase": "travelling", "stop": 1, "cycle": NSNull()] }),
            ("fractional cycle", { $0["execution"] = ["phase": "travelling", "stop": 1, "cycle": 1.5] }),
            // The last cycle that fits is (Int64.max - 12) / 12, rounded
            // down: 768614336404564649. The next one does not fit.
            ("a cycle past the last that fits", { $0["execution"] = ["phase": "travelling", "stop": 1, "cycle": 768_614_336_404_564_650] }),
            // Nothing travels to the service's very first stop.
            ("travelling to stop 0 of cycle 0", { $0["execution"] = ["phase": "travelling", "stop": 0] }),
        ]
        for (what, change) in malformed {
            XCTAssertThrowsError(try decode(change), what)
        }

        // Travelling to stop 0 is fine in a later cycle: the journey from the
        // last stop back to the first. It still has to end at Alpha, which
        // this one (to f) does not.
        XCTAssertThrowsError(try decode { $0["execution"] = ["phase": "travelling", "stop": 0, "cycle": 1] })
        // The last cycle that fits is a valid cycle.
        XCTAssertNoThrow(try decode { $0["execution"] = ["phase": "travelling", "stop": 1, "cycle": 768_614_336_404_564_649] })
        // Without "cycle", cycle 0: a different but valid service.
        XCTAssertEqual(try train(in: decode { $0["execution"] = ["phase": "travelling", "stop": 1] }).execution, .travellingToStop(1))
    }
}
