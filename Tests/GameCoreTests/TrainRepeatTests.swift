import Foundation
import GameCore
import XCTest

/// Turning round and repeating timetables (Phase 4 Stage Q1, ARCHITECTURE
/// decision 21): a stop can turn the train round as the service leaves it,
/// and a timetable can repeat every period, cycle after cycle. Stage P's
/// rules hold within every cycle, and Stage W2b's dwell at every call: 42 s
/// at least where the train turns round or a cycle starts or ends, and
/// reaching stop 0 of the next cycle at once counts as arriving there.
/// On the track network (Stage F3b) a train of one car turned round at a
/// platform stands at its near end for the new way, and its call there is
/// at the far end, the platform's berth: it drives there first.
/// Between calls a train runs on the running curve of its performance in
/// the time its timetable gives the run (Stage W2c, decision 40); where it
/// is on the way is read off the curve with `runDistance(_:in:after:)`.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run. Every train here has rate 1024 and the
/// clock runs a minute a tick, so after `n` ticks from minute 0 the clock
/// reads `n` and the steps of minutes 0 to `n - 1` have run.
final class TrainRepeatTests: XCTestCase {
    // The line of `TrainServiceTests` on the track network (Stage F3b, see
    // `TestLine`), dead ends at both ends:
    //
    //   Alpha(1,0)  Beta(3,0)  Gamma(5,0)
    //       |           |          |
    //   a - b - c - d - e - f - g
    //                          |
    //                      Delta(5,2)
    //
    // Platforms: Alpha either side of b, Beta of d, Gamma of f; Delta's is
    // the second half of edge 6, touching Gamma's at 512.
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let first = TrainID(rawValue: 1)
    private let unknown = TrainID(rawValue: 9)

    private func makeLineWorld(minute: Int64 = 0) throws -> GameWorld {
        var world = try GameWorld(
            width: 8, height: 4,
            economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let delta = try world.buildStation(named: "Delta", at: TestLine.centre(5, 2)).id
        try world.addTrackPlatform(delta, on: line.edge(6), from: 512, to: 1_024)
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
        try world.setTrainTimetable(first, to: stops, repeatingEvery: periodSeconds(period))
        try world.startTrainService(first)
        return world
    }

    private func stop(_ station: StationID, _ arrival: Int64, _ departure: Int64, reverses: Bool = false) -> ScheduledStop {
        ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: departure), reverses: reverses)
    }

    /// Alpha to Gamma and back every 12 minutes, turning round at both ends.
    /// Each way is four edges (4096 units) in the four minutes the timetable
    /// gives it.
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

    /// A period needs a stop and a second or more (Stage W2a; these are whole minutes), and the timetable must
    /// not go back when it starts again: the last departure no later than
    /// the first arrival one period later.
    func testAPeriodMustLetTheTimetableStartAgainWithoutGoingBack() throws {
        var world = try makeLineWorld()
        // The shuttle spans 0 to 12, so 12 is the shortest period.
        for period: Int64 in [12, 13, 1440, .max] {
            try world.setTrainTimetable(first, to: shuttle, repeatingEvery: periodSeconds(period))
            XCTAssertEqual(try train(in: world).timetablePeriod, periodSeconds(period))
            XCTAssertEqual(try train(in: world).timetable, shuttle)
        }
        let before = world
        for period: Int64 in [11, 1, 0, -1, -12, .min] {
            XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: shuttle, repeatingEvery: periodSeconds(period)), .invalidTimetable)
        }
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [], repeatingEvery: periodSeconds(60)), .invalidTimetable)
        XCTAssertEqual(world, before, "refused timetables change nothing")

        // One stop repeats every period at least its dwell; a later first
        // arrival counts from itself, not from minute 0.
        try world.setTrainTimetable(first, to: [stop(alpha, 3, 8)], repeatingEvery: periodSeconds(5))
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(alpha, 3, 8)], repeatingEvery: periodSeconds(4)), .invalidTimetable)
        try world.setTrainTimetable(first, to: [stop(alpha, 100, 100), stop(beta, 110, 130)], repeatingEvery: periodSeconds(30))

        // Setting a timetable without a period makes it run once; clearing
        // clears the period too.
        try world.setTrainTimetable(first, to: shuttle)
        XCTAssertNil(try train(in: world).timetablePeriod)
        try world.setTrainTimetable(first, to: shuttle, repeatingEvery: periodSeconds(12))
        try world.setTrainTimetable(first, to: [])
        XCTAssertEqual(try train(in: world).timetable, [])
        XCTAssertNil(try train(in: world).timetablePeriod)
    }

    /// The period is checked with the times, after the train and a running
    /// service, and before the stations.
    func testPeriodChecksRunInTheDocumentedOrder() throws {
        var world = try makeLineWorld()
        let ghost = StationID(rawValue: 99)
        XCTAssertThrowsGameError(try world.setTrainTimetable(unknown, to: shuttle, repeatingEvery: periodSeconds(0)), .unknownTrain(unknown))
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(ghost, 0, 0)], repeatingEvery: periodSeconds(0)), .invalidTimetable)
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(ghost, 0, 0)], repeatingEvery: periodSeconds(1)), .unknownStation(ghost))

        try world.placeTrain(first, at: line.at(1, facingEast: true))
        try world.setTrainTimetable(first, to: shuttle, repeatingEvery: periodSeconds(12))
        try world.startTrainService(first)
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: shuttle, repeatingEvery: periodSeconds(0)), .trainServiceActive(first))
    }

    // MARK: - Turning round

    /// Without turning round, a train at a dead-end terminus has no route
    /// back (a route never turns straight back), so its service waits.
    func testATerminusNeedsAStopThatTurnsTheTrainRound() throws {
        var stuck = try makeServiceWorld([stop(gamma, 0, 0), stop(alpha, 4, 4)], every: nil, at: line.at(5, facingEast: true))
        try stuck.advance(ticks: 10)
        XCTAssertEqual(try train(in: stuck).execution, .waitingAtStop(0))
        XCTAssertEqual(try train(in: stuck).position, line.at(5, facingEast: true))

        // Turning round at Gamma: it leaves at 0:42 facing west and reaches
        // b, Alpha's platform, four edges later, at 4:42. It turned where it
        // stood, on edge 5: the path takes it on along edges 4, 3 and 2.
        var turning = try makeServiceWorld([stop(gamma, 0, 0, reverses: true), stop(alpha, 4, 4)], every: nil, at: line.at(5, facingEast: true))
        try turning.advance(ticks: 1)
        XCTAssertEqual(try train(in: turning).execution, .travellingToStop(1))
        XCTAssertEqual(try train(in: turning).position, line.between(5, 4, offset: runDistance(4096, in: 240, after: 18)))
        XCTAssertEqual(try train(in: turning).movement.edges, [4, 3, 2].map(line.edge))
        XCTAssertEqual(try train(in: turning).movement.cursor, 0)
        try turning.advance(ticks: 3)
        XCTAssertEqual(try train(in: turning).execution, .travellingToStop(1))
        XCTAssertEqual(try train(in: turning).position, line.between(2, 1, offset: runDistance(4096, in: 240, after: 198) - 3072))
        try turning.advance(ticks: 1)
        XCTAssertEqual(try train(in: turning).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(in: turning).position, line.at(1, facingEast: false))
    }

    /// A departure that finds no route after turning round changes nothing:
    /// the train is not left turned, and turns when it can leave.
    func testWithoutARouteTheTrainIsNotLeftTurned() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: line.at(5, facingEast: true))
        try world.setTrainMovementRate(first, to: 1024)
        try world.setTrainTimetable(first, to: [stop(gamma, 0, 0, reverses: true), stop(alpha, 4, 4)])
        try world.startTrainService(first)
        // Edge 3, c to d, with Beta's platform before d on it.
        try world.removeTrackPlatform(beta, on: line.edge(3), from: 512)
        try world.removeTrackEdge(line.edge(3))

        try world.advance(ticks: 3)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0))
        XCTAssertEqual(try train(in: world).position, line.at(5, facingEast: true))
        XCTAssertEqual(try train(in: world).movement.edges, [])

        // Rebuilt at minute 3 (as a new edge): the step at minute 3 turns it
        // and sets off on its run of the four minutes from 0 to 4.
        try world.buildTrackEdge(from: line.node(2), to: line.node(3))
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1))
        XCTAssertEqual(try train(in: world).position, line.between(5, 4, offset: runDistance(4096, in: 240, after: 60)))
    }

    /// Turning round at the last stop of a timetable that runs once happens
    /// as the service ends there; the train stays, turned.
    func testTheLastStopTurnsTheTrainAsTheServiceEnds() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 0), stop(beta, 2, 3, reverses: true)], every: nil, at: line.at(1, facingEast: true))
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(in: world).position, line.at(3, facingEast: true))
        try world.advance(ticks: 1)
        XCTAssertNil(try train(in: world).execution)
        XCTAssertEqual(try train(in: world).position, line.turned(at: 3, facingEast: false))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [beta])
    }

    // MARK: - Repeating

    /// The shuttle runs cycle after cycle: out at 0:42, 12:50, 24:50, ...
    /// (42 s at Alpha first each time), at Gamma from 4:42, 16:50, ...,
    /// left on time at 6, 18, ..., back at Alpha from 10, 22, .... Leaving
    /// Alpha at 12 turns the train where it stands, at b: the near end of
    /// Alpha's platform past b for the way east. Cycle 1's call at Alpha is
    /// at that platform's berth, its far end 512 along edge 2, so the train
    /// drives there first, in 8 s, the least (the timetable gives that run
    /// no time): it arrives at 12:08, dwells its 42 s, and leaves at 12:50,
    /// 50 s late, on the four minutes' run of 3584 to Gamma.
    func testAShuttleRepeatsOnTimeTurningAtBothEnds() throws {
        var world = try makeServiceWorld(shuttle, every: 12, at: line.at(1, facingEast: true))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0))

        try world.advance(ticks: 4)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1))
        XCTAssertEqual(try train(in: world).position, line.between(4, 5, offset: runDistance(4096, in: 240, after: 198) - 3072))
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(in: world).position, line.at(5, facingEast: true))

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1), "Gamma is left at 6, not before")

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(2))
        XCTAssertEqual(try train(in: world).position, line.between(5, 4, offset: runDistance(4096, in: 240, after: 60)))

        try world.advance(ticks: 3)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 10))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(2))
        XCTAssertEqual(try train(in: world).position, line.at(1, facingEast: false))

        try world.advance(ticks: 2)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(2), "the last stop is left at 12")

        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1, cycle: 1))
        XCTAssertEqual(try train(in: world).position, line.between(1, 2, offset: 512 + runDistance(3584, in: 240, after: 10)))
        XCTAssertEqual(try train(in: world).movement.edges, [3, 4, 5].map(line.edge))
        XCTAssertEqual(
            try train(in: world).times,
            ServiceTimes(
                arrival: GameTime(seconds: 12 * 60 + 8), departure: GameTime(seconds: 12 * 60 + 50),
                run: ServiceRun(start: GameTime(seconds: 12 * 60 + 50), length: 3584, seconds: 240)
            )
        )

        try world.advance(ticks: 4)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 17))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1, cycle: 1))
        XCTAssertEqual(try train(in: world).position, line.at(5, facingEast: true))

        try world.advance(ticks: 8)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 25))
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1, cycle: 2))
        XCTAssertEqual(try train(in: world).position, line.between(1, 2, offset: 512 + runDistance(3584, in: 240, after: 10)))

        // The timetable is plan data: it keeps its first cycle's times.
        XCTAssertEqual(try train(in: world).timetable, shuttle)
        XCTAssertEqual(try train(in: world).timetablePeriodMinutes, 12)
    }

    /// A late train does not skip a stop or a cycle: it leaves each stop as
    /// soon as it can, and slack in the timetable lets it catch up.
    func testALateShuttleCatchesUpThroughItsSlack() throws {
        // The shuttle has two minutes' slack at each end.
        var world = try makeLineWorld()
        try world.placeTrain(first, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(first, to: 1024)
        try world.setTrainTimetable(first, to: shuttle, repeatingEvery: periodSeconds(12))
        try world.startTrainService(first)
        // Held at Alpha until minute 6 with rate 0: it gets its route at
        // 0:42 but does not move, and drops the run it set off on.
        try world.setTrainMovementRate(first, to: 0)
        try world.advance(ticks: 6)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1))
        XCTAssertEqual(try train(in: world).position, line.at(1, facingEast: true))
        XCTAssertNil(try train(in: world).times?.run)
        XCTAssertEqual(world.lateness(of: first), 120, "two minutes past the arrival due at 4")
        try world.setTrainMovementRate(first, to: 1024)

        // From 6 it sets off from a stand, as fast as it can: four edges in
        // 23 s (√(2 × 4096 × 0.06) = 22.17 s). At Gamma at 6:23, where it
        // turns round and so dwells 42 s: its doors close at 6:56 and it
        // leaves at 7:05, 65 s late, on the four minutes' run to Alpha.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 7))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1))
        XCTAssertEqual(try train(in: world).times?.arrival, GameTime(seconds: 6 * 60 + 23))
        XCTAssertEqual(world.lateness(of: first), 60)
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(2))
        XCTAssertEqual(try train(in: world).position, line.between(5, 4, offset: runDistance(4096, in: 240, after: 55)))
        XCTAssertEqual(world.lateness(of: first), 65)

        // At Alpha at 11:05, where it turns round and waits for the end of
        // the cycle at 12: on time again. Cycle 1 drives to Alpha's berth
        // for the way east and leaves at 12:50, as every later cycle does
        // (see `testAShuttleRepeatsOnTimeTurningAtBothEnds`).
        try world.advance(ticks: 3)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 11))
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(2))
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(2))
        XCTAssertEqual(try train(in: world).times?.arrival, GameTime(seconds: 11 * 60 + 5))
        XCTAssertEqual(world.lateness(of: first), 0)
        try world.advance(ticks: 1)
        XCTAssertEqual(try train(in: world).execution, .travellingToStop(1, cycle: 1))
        XCTAssertEqual(try train(in: world).times?.departure, GameTime(seconds: 12 * 60 + 50))
        XCTAssertEqual(try train(in: world).position, line.between(1, 2, offset: 512 + runDistance(3584, in: 240, after: 10)))
    }

    /// A train never goes round without end: it dwells at every call. A
    /// train saved many cycles behind a one-stop timetable, whose every
    /// call is at the same station, goes one cycle further every 42 s (the
    /// call starts and ends a cycle), however late it is.
    func testALateServiceGoesOneCycleAtATime() throws {
        // On time once the timetable holds it: cycle 0 left at 0:42, cycle 1
        // at 1:24, cycle 2 at 2:06, cycle 3 held for its departure at 3.
        var world = try makeServiceWorld([stop(alpha, 0, 0)], every: 1, at: line.at(1, facingEast: true))
        try world.advance(ticks: 3)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 3), "on time: one call a minute")

        // The same train saved at second 1000, still in cycle 3: it leaves
        // at 1000, then cycle 4 at 1042, cycle 5 waits at 1060 and leaves
        // at 1084, and so on, 42 s each.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(world)) as? [String: Any])
        var clock = try XCTUnwrap(object["clock"] as? [String: Any])
        clock["now"] = 1000
        object["clock"] = clock
        var late = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(try train(in: late).execution, .waitingAtStop(0, cycle: 3))
        try late.advance(ticks: 1)
        XCTAssertEqual(try train(in: late).execution, .waitingAtStop(0, cycle: 5))
        // 1060 to 1360: cycles 6 to 12 arrive at 1084 + 42 k.
        try late.advance(ticks: 5)
        XCTAssertEqual(try train(in: late).execution, .waitingAtStop(0, cycle: 12))

        // Two calls a cycle at the same station, each 42 s (each starts or
        // ends the cycle): cycle 1 reaches the first at 1:24, the second at
        // 2:06, cycle 2 the first at 2:48. (On the grid these were Gamma and
        // Delta sharing f. On the track network two stations cannot share a
        // platform, and where theirs meet a train is at the berth of only
        // one of them each way, so going round it would have to move.)
        var twice = try makeServiceWorld([stop(alpha, 0, 0), stop(alpha, 0, 0)], every: 1, at: line.at(1, facingEast: true))
        try twice.advance(ticks: 2)
        XCTAssertEqual(try train(in: twice).execution, .waitingAtStop(0, cycle: 1))
        try twice.advance(ticks: 1)
        XCTAssertEqual(try train(in: twice).execution, .waitingAtStop(0, cycle: 2))
    }

    // MARK: - Starting

    /// A repeating timetable starts in the first cycle whose first departure
    /// is not before now; one that runs once always starts in its only
    /// cycle, however late.
    func testARepeatingServiceStartsInTheNextCycleThatLeavesOnTime() throws {
        let timetable = [stop(alpha, 0, 5), stop(beta, 7, 7)]
        let cases: [(minute: Int64, cycle: Int64)] = [(0, 0), (5, 0), (6, 1), (25, 1), (26, 2), (30, 2), (45, 2), (46, 3)]
        for (minute, cycle) in cases {
            let world = try makeServiceWorld(timetable, every: 20, at: line.at(1, facingEast: true), minute: minute)
            XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: cycle), "started at \(minute)")
        }
        let once = try makeServiceWorld(timetable, every: nil, at: line.at(1, facingEast: true), minute: 46)
        XCTAssertEqual(try train(in: once).execution, .waitingAtStop(0))

        // Started at 26 in cycle 2: Alpha is left at 45, Beta reached at 47.
        var world = try makeServiceWorld(timetable, every: 20, at: line.at(1, facingEast: true), minute: 26)
        try world.advance(ticks: 19)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 2))
        try world.advance(ticks: 2)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(1, cycle: 2))
        XCTAssertEqual(world.clock.now, GameTime(minutes: 47))
    }

    /// Stopping keeps the timetable and its period; starting again joins
    /// the next cycle that leaves on time.
    func testStoppingAndStartingAgainJoinsTheNextCycle() throws {
        var world = try makeServiceWorld(shuttle, every: 12, at: line.at(1, facingEast: true))
        try world.advance(ticks: 11)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(2))
        try world.stopTrainService(first)
        XCTAssertEqual(try train(in: world).timetablePeriodMinutes, 12)
        try world.startTrainService(first)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 1), "cycle 1 leaves Alpha at 12")

        // Taken off the track, the train keeps its period too.
        try world.stopTrainService(first)
        try world.unplaceTrain(first)
        XCTAssertEqual(try train(in: world).timetablePeriodMinutes, 12)
    }

    // MARK: - The last cycle

    /// Cycles whose times would pass the largest second do not exist: a
    /// service starts at the last cycle that fits, however late, and ends
    /// after it instead of starting again. (Stage W2a: the times and the
    /// period are seconds here, near the end of the range.)
    func testTheServiceEndsAfterTheLastCycleWhoseTimesFit() throws {
        // Cycles 0 and 1 fit: cycle 1 leaves Alpha at 2^62 seconds, which
        // is second 4 of minute `leaving - 1` (2^62 = 60 k + 4); the train
        // leaves at that second (Stage W2b), its doors closing 9 s before.
        let period = Int64(1) << 62
        let leaving = (period + 59) / 60
        var world = try makeLineWorld(minute: 1)
        try world.placeTrain(first, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(first, to: 1024)
        try world.setTrainTimetable(first, to: [stop(alpha, 0, 0)], repeatingEvery: period)
        try world.startTrainService(first)
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 1))
        try world.advance(ticks: Int(leaving - 2))
        XCTAssertEqual(world.clock.now, GameTime(seconds: period - 4))
        XCTAssertEqual(try train(in: world).execution, .waitingAtStop(0, cycle: 1))
        XCTAssertEqual(
            try train(in: world).times,
            ServiceTimes(arrival: GameTime(minutes: 1), exchangeEnd: GameTime(seconds: 68), closing: GameTime(seconds: period - 9))
        )
        try world.advance(ticks: 1)
        XCTAssertNil(try train(in: world).execution, "no cycle 2 to start")
        XCTAssertEqual(world.clock.now, GameTime(minutes: leaving))

        // Only cycle 0 fits when the period is almost the whole range.
        let end = GameTime(seconds: .max - 10)
        var late = try makeLineWorld(minute: 5)
        try late.placeTrain(first, at: line.at(1, facingEast: true))
        try late.setTrainTimetable(first, to: [stop(alpha, 0, 0), ScheduledStop(station: beta, arrival: end, departure: end)], repeatingEvery: .max - 10)
        try late.startTrainService(first)
        XCTAssertEqual(try train(in: late).execution, .waitingAtStop(0))
    }

    // MARK: - Batches

    /// However the time is cut into batches, and at 2x, the shuttle ends up
    /// in the same place.
    func testBatchesSingleTicksAndDoubleSpeedAgree() throws {
        let start = try makeServiceWorld(shuttle, every: 12, at: line.at(1, facingEast: true))
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

        // 1000 = 83 × 12 + 4: cycle 83, which left Alpha's berth 512 along
        // edge 2 at 996:50, reaches Gamma at 1000:50.
        XCTAssertEqual(try train(in: batch).execution, .travellingToStop(1, cycle: 83))
        XCTAssertEqual(try train(in: batch).position, line.between(4, 5, offset: 512 + runDistance(3584, in: 240, after: 190) - 3072))
    }

    /// A departure between two minutes is made at its second (Stage W2b),
    /// and a batch that skips idle minutes wakes for it as single ticks do.
    func testABatchWakesForADepartureBetweenTwoMinutes() throws {
        // From second 15 of minute 1, Alpha is left at second 15 of minute
        // 2 and then every 28 minutes, each cycle arriving at once at Alpha
        // and holding for its departure.
        var start = try makeLineWorld(minute: 1)
        start.setSpeed(.x1)
        try start.advance(ticks: 150)
        start.setSpeed(.normal)
        let time = GameTime(seconds: 135)
        try start.placeTrain(first, at: line.at(1, facingEast: true))
        try start.setTrainTimetable(first, to: [ScheduledStop(station: alpha, arrival: time, departure: time)], repeatingEvery: 28 * 60)
        try start.startTrainService(first)
        var batch = start
        try batch.advance(ticks: 38)
        var single = start
        for _ in 0..<38 {
            try single.advance(ticks: 1)
        }
        XCTAssertEqual(batch, single)
        // Left at 2:15 and 30:15; the next leaves at 58:15.
        XCTAssertEqual(batch.clock.now, GameTime(seconds: 75 + 38 * 60))
        XCTAssertEqual(try train(in: batch).execution, .waitingAtStop(0, cycle: 2))
    }

    // MARK: - Saving

    /// The period, turning round and the cycle are saved only when used,
    /// so worlds without them save as before, and old saves read as running
    /// once, turning nowhere and in cycle 0.
    func testRepeatsTurnsAndCyclesAreSavedOnlyWhenUsed() throws {
        var world = try makeServiceWorld(shuttle, every: 12, at: line.at(1, facingEast: true))
        var text = String(decoding: try encode(world), as: UTF8.self)
        // Stage W2a: the period is saved in seconds.
        XCTAssertTrue(text.contains(#""period":720"#), text)
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
        var world = try makeServiceWorld(shuttle, every: 12, at: line.at(1, facingEast: true))
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
            ("negative period", { $0["period"] = -720 }),
            // Stage W2a: periods are saved in seconds, and the shuttle spans
            // 720 of them.
            ("period too short", { $0["period"] = 719 }),
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
            // The last cycle that fits is (Int64.max - 720) / 720 in
            // seconds, rounded down: 12810238940076076. The next one does
            // not fit.
            ("a cycle past the last that fits", { $0["execution"] = ["phase": "travelling", "stop": 1, "cycle": 12_810_238_940_076_077] }),
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
        XCTAssertNoThrow(try decode { $0["execution"] = ["phase": "travelling", "stop": 1, "cycle": 12_810_238_940_076_076] })
        // Without "cycle", cycle 0: a different but valid service.
        XCTAssertEqual(try train(in: decode { $0["execution"] = ["phase": "travelling", "stop": 1] }).execution, .travellingToStop(1))
    }
}
