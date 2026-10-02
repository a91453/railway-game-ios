import Foundation
import GameCore
import XCTest

/// Timetable services (Phase 4 Stage P, ARCHITECTURE decision 20): a train
/// runs its timetable once, in order, from its first stop to its last. A
/// service never leaves a stop before its scheduled departure, nor before
/// its dwell there is over (Stage W2b, decision 39: starting counts as
/// arriving; at least 42 s at either end of the timetable or where the
/// train turns round, 36 s elsewhere; see ``ServiceDwellTests``), reaches a
/// repeated station or a shared platform at once (and dwells there too),
/// waits while there is no route, and owns the train's continuation while
/// it runs. How far it has got is saved with the train.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run. Every train here moves at rate 1024 (one
/// link a minute) unless a test says otherwise: a train that leaves at
/// second `s` of a minute has gone 1024 - floor(1024 s / 60) units by the
/// next minute (308 for 42 s, 410 for 36 s, 717 for 18 s).
final class TrainServiceTests: XCTestCase {
    // A line along y = 1 with dead ends at both ends, and five stations:
    //
    //   Alpha(1,0)  Beta(3,0)  Gamma(5,0)
    //       |           |          |
    //   a - b - c - d - e - f - g
    //                          |
    //                      Delta(5,2)        Far(7,3): no platform
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
    private let far = StationID(rawValue: 5)
    private let first = TrainID(rawValue: 1)
    private let second = TrainID(rawValue: 2)
    private let unknown = TrainID(rawValue: 9)

    private func makeLineWorld(minute: Int64 = 0, seconds: Int64? = nil, trainCount: Int = 1) throws -> GameWorld {
        var world = try GameWorld(
            width: 8, height: 4,
            economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: seconds.map(GameTime.init(seconds:)) ?? GameTime(minutes: minute), speed: .normal)
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
        try world.buildStation(named: "Far", at: GridPosition(x: 7, y: 3))
        for number in 0..<trainCount {
            try world.purchaseTrain(named: "Local \(number + 1)")
        }
        return world
    }

    /// A world whose first train stands at `position` with `rate` and runs
    /// `stops` from `minute` on.
    private func makeServiceWorld(
        _ stops: [ScheduledStop],
        rate: Int64 = 1024,
        at position: TrainPosition? = nil,
        minute: Int64 = 0,
        seconds: Int64? = nil
    ) throws -> GameWorld {
        var world = try makeLineWorld(minute: minute, seconds: seconds)
        try world.placeTrain(first, at: position ?? .atNode(b, heading: .east))
        try world.setTrainMovementRate(first, to: rate)
        try world.setTrainTimetable(first, to: stops)
        try world.startTrainService(first)
        return world
    }

    private func stop(_ station: StationID, _ arrival: Int64, _ departure: Int64) -> ScheduledStop {
        ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: departure))
    }

    private func execution(of id: TrainID, in world: GameWorld) throws -> TimetableExecution? {
        try XCTUnwrap(world.train(id: id)).execution
    }

    private func position(of id: TrainID, in world: GameWorld) throws -> TrainPosition? {
        try XCTUnwrap(world.train(id: id)).position
    }

    private func movement(of id: TrainID, in world: GameWorld) throws -> TrainMovement {
        try XCTUnwrap(world.train(id: id)).movement
    }

    private func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    // MARK: - Starting

    func testNewTrainsHaveNoService() throws {
        let world = try makeLineWorld(trainCount: 2)
        XCTAssertNil(try execution(of: first, in: world))
        XCTAssertNil(Train(id: first, name: "A").execution)
    }

    /// Starting waits at stop 0 as if the train had just arrived, and changes
    /// nothing else: nothing moves until time passes.
    func testStartingWaitsAtTheFirstStopAndChangesNothingElse() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(b, heading: .east))
        try world.setTrainMovementRate(first, to: 1024)
        try world.setTrainTimetable(first, to: [stop(alpha, 0, 0), stop(beta, 2, 2)])
        let before = world

        try world.startTrainService(first)

        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))
        var stopped = world
        try stopped.stopTrainService(first)
        XCTAssertEqual(stopped, before, "starting changed more than the service")
        XCTAssertEqual(world.stationsStoppedAt(by: first), [alpha])
    }

    func testStartChecksRunInTheDocumentedOrder() throws {
        var world = try makeLineWorld(trainCount: 2)
        XCTAssertThrowsGameError(try world.startTrainService(unknown), .unknownTrain(unknown))
        // No timetable is reported before the train being unplaced.
        XCTAssertThrowsGameError(try world.startTrainService(first), .noTimetable(first))
        try world.setTrainTimetable(first, to: [stop(alpha, 0, 5), stop(beta, 8, 8)])
        XCTAssertThrowsGameError(try world.startTrainService(first), .trainNotPlaced(first))
        // Placed, but not stopped at Alpha: next to no station, at another
        // station, passing Alpha's platform, or on a link.
        try world.placeTrain(first, at: .atNode(c, heading: .east))
        XCTAssertThrowsGameError(try world.startTrainService(first), .trainNotAtFirstStop(first))
        try world.unplaceTrain(first)
        try world.placeTrain(first, at: .atNode(d, heading: .west))
        XCTAssertThrowsGameError(try world.startTrainService(first), .trainNotAtFirstStop(first))
        try world.unplaceTrain(first)
        try world.placeTrain(first, at: .atNode(b, heading: .east))
        try world.setTrainContinuation(first, to: [c])
        XCTAssertThrowsGameError(try world.startTrainService(first), .trainNotAtFirstStop(first))
        try world.unplaceTrain(first)
        try world.placeTrain(first, at: .onLink(from: a, to: b, offset: 1023))
        XCTAssertThrowsGameError(try world.startTrainService(first), .trainNotAtFirstStop(first))
        try world.unplaceTrain(first)
        try world.placeTrain(first, at: .atNode(b, heading: .west))

        // Every refusal left the world as it was.
        let before = world
        for id in [unknown, second] {
            XCTAssertThrowsError(try world.startTrainService(id))
            XCTAssertEqual(world, before)
        }

        // Stopped at Alpha, facing either way: accepted; then already running.
        try world.startTrainService(first)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))
        XCTAssertThrowsGameError(try world.startTrainService(first), .trainServiceActive(first))
    }

    /// A platform shared by several stations starts a service for any of
    /// them; a station without a platform can never be a first stop.
    func testASharedPlatformStartsAServiceForEitherStation() throws {
        for station in [gamma, delta] {
            let world = try makeServiceWorld([stop(station, 0, 0)], at: .atNode(f, heading: .west))
            XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))
        }
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(f, heading: .west))
        try world.setTrainTimetable(first, to: [stop(far, 0, 0)])
        XCTAssertThrowsGameError(try world.startTrainService(first), .trainNotAtFirstStop(first))
    }

    /// Times already passed skip nothing: the service starts from stop 0
    /// and leaves every stop as soon as its dwell there is over.
    func testAServiceNeverSkipsStopsHoweverLateItStarts() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 1), stop(beta, 2, 3), stop(gamma, 4, 5)], minute: 1000)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))

        // Alpha, where it starts, is an end: 42 s, so it leaves at 1000:42;
        // by 1002 it is 308 + 1024 along, 308 past c, and reaches Beta at
        // 1002:42.
        try world.advance(ticks: 2)
        XCTAssertEqual(world.clock.now.minutes, 1002)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(1))
        XCTAssertEqual(try position(of: first, in: world), .onLink(from: c, to: d, offset: 308))
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        XCTAssertEqual(try position(of: first, in: world), .atNode(d, heading: .east))

        // Beta is between the ends: 36 s, so it leaves at 1003:18 and by
        // 1005 is 717 + 1024 along, 717 past e; Gamma at 1005:18.
        try world.advance(ticks: 2)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(2))
        XCTAssertEqual(try position(of: first, in: world), .onLink(from: e, to: f, offset: 717))

        // Gamma is the last stop: 42 s, so its doors close at 1005:51 and
        // the service ends at 1006:00, in the step that starts then.
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(2))
        try world.advance(ticks: 1)
        XCTAssertNil(try execution(of: first, in: world))
        XCTAssertNil(try XCTUnwrap(world.train(id: first)).times)
        XCTAssertEqual(try position(of: first, in: world), .atNode(f, heading: .east))
    }

    // MARK: - Departures and arrivals

    /// An early train waits at its stop, minute by minute, and leaves in the
    /// step that starts at its scheduled departure: not a minute earlier.
    func testATrainNeverLeavesBeforeItsScheduledDeparture() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 3), stop(beta, 10, 12), stop(gamma, 20, 20)])

        try world.advance(ticks: 3)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))
        XCTAssertEqual(try position(of: first, in: world), .atNode(b, heading: .east))

        // The step from 3 leaves Alpha and enters c.
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(1))
        XCTAssertEqual(try position(of: first, in: world), .atNode(c, heading: .east))
        XCTAssertEqual(try movement(of: first, in: world).continuation, [c, d])
        XCTAssertEqual(try movement(of: first, in: world).cursor, 1)

        // At d by 5, five minutes early for an arrival at 10.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.clock.now.minutes, 5)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        while world.clock.now.minutes < 12 {
            try world.advance(ticks: 1)
            XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1), "minute \(world.clock.now.minutes)")
            XCTAssertEqual(try position(of: first, in: world), .atNode(d, heading: .east), "minute \(world.clock.now.minutes)")
        }

        // The departure is 12: the step from 12 leaves.
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(2))
        XCTAssertEqual(try position(of: first, in: world), .atNode(e, heading: .east))
    }

    /// A timetable without dwells still gets the least dwell at every stop:
    /// a train that arrives with distance to spare stops there, and leaves
    /// once its dwell is over.
    func testAnArrivalWithZeroDwellStillDwellsItsLeast() throws {
        // Four links a minute: leaving Alpha at 0:42 it has gone 4096 - 2867
        // = 1229 by 1, 205 past c, and reaches d (2048) 12 s later, at 1:12
        // (floor(4096 x 12 / 60) = 819 = 2048 - 1229).
        var world = try makeServiceWorld([stop(alpha, 0, 0), stop(beta, 1, 1), stop(gamma, 2, 2)], rate: 4096)

        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(1))
        XCTAssertEqual(try position(of: first, in: world), .onLink(from: c, to: d, offset: 205))

        // Beta: 36 s from 1:12, so it leaves at 1:48 and has gone 4096 -
        // 3276 = 820 by 2, 820 past d; Gamma 1228 later, at 2:18.
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(2))
        XCTAssertEqual(try position(of: first, in: world), .onLink(from: d, to: e, offset: 820))

        // Gamma, the last stop: 42 s from 2:18; the service ends at 3:00.
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(2))
        XCTAssertEqual(try position(of: first, in: world), .atNode(f, heading: .east))
        XCTAssertEqual(try movement(of: first, in: world).continuation, [])
        try world.advance(ticks: 1)
        XCTAssertNil(try execution(of: first, in: world))
        XCTAssertEqual(world.clock.now.minutes, 4)
    }

    /// A late train is not held for its timetable: it leaves as soon as its
    /// least dwell is over.
    func testALateTrainLeavesOnceItsLeastDwellIsOver() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 0), stop(beta, 1, 1), stop(gamma, 10, 10)])

        // Leaving Alpha at 0:42, Beta, two links away, is reached at 2:42,
        // after its departure at 1: 102 s late.
        try world.advance(ticks: 3)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        XCTAssertEqual(world.lateness(of: first), 120)

        // 36 s at Beta: its doors close at 3:09 and it leaves at 3:18, 138 s
        // late, and is 717 past d by 4.
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(2))
        XCTAssertEqual(try position(of: first, in: world), .onLink(from: d, to: e, offset: 717))
        XCTAssertEqual(world.train(id: first)?.times, ServiceTimes(arrival: GameTime(seconds: 162), departure: GameTime(seconds: 198)))
        XCTAssertEqual(world.lateness(of: first), 138)
    }

    /// A stop at the station the train is already stopped at (a repeated
    /// station, or another station on the same platform) is reached at once,
    /// without moving: it counts as arriving there, and the train dwells
    /// there as at any stop.
    func testRepeatedStationsAndSharedPlatformsAreReachedAtOnce() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 0), stop(alpha, 0, 5), stop(beta, 7, 7)])
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        XCTAssertEqual(try position(of: first, in: world), .atNode(b, heading: .east))
        XCTAssertEqual(try movement(of: first, in: world).continuation, [])
        try world.advance(ticks: 4)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(2))

        // Three stops at Alpha, all due: 42 s at the first (left at 0:42),
        // 36 s at the second (left at 1:18), 42 s at the last: the service
        // ends at 2:00, in the step that starts then.
        world = try makeServiceWorld([stop(alpha, 0, 0), stop(alpha, 0, 0), stop(alpha, 0, 0)])
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        XCTAssertEqual(world.train(id: first)?.times, ServiceTimes(arrival: GameTime(seconds: 42), exchangeEnd: GameTime(seconds: 50), departure: GameTime(seconds: 42)))
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(2))
        try world.advance(ticks: 1)
        XCTAssertNil(try execution(of: first, in: world))
        XCTAssertEqual(try position(of: first, in: world), .atNode(b, heading: .east))

        // Gamma to Delta across their shared platform.
        world = try makeServiceWorld([stop(gamma, 0, 0), stop(delta, 0, 4), stop(beta, 10, 10)], at: .atNode(f, heading: .west))
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        XCTAssertEqual(try position(of: first, in: world), .atNode(f, heading: .west))
        try world.advance(ticks: 4)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(2))
        XCTAssertEqual(try position(of: first, in: world), .atNode(e, heading: .west))
    }

    /// Without a route the train waits at its stop; once the map allows a
    /// route, the next step leaves.
    func testWithoutARouteTheTrainWaitsUntilTheMapAllowsOne() throws {
        var world = try makeLineWorld()
        try world.placeTrain(first, at: .atNode(b, heading: .east))
        try world.setTrainMovementRate(first, to: 1024)
        try world.removeTrack(at: c)
        try world.setTrainTimetable(first, to: [stop(alpha, 0, 0), stop(beta, 5, 5)])
        try world.startTrainService(first)
        XCTAssertNil(world.route(from: .atNode(b, heading: .east), toStation: beta))

        try world.advance(ticks: 100)
        XCTAssertEqual(world.clock.now.minutes, 100)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))
        XCTAssertEqual(try position(of: first, in: world), .atNode(b, heading: .east))
        XCTAssertEqual(try movement(of: first, in: world).continuation, [])

        try world.buildTrack(at: c, connections: [.east, .west])
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(1))
        XCTAssertEqual(try position(of: first, in: world), .atNode(c, heading: .east))
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))

        // A station without a platform is never reached: the train waits.
        world = try makeServiceWorld([stop(alpha, 0, 0), stop(far, 1, 1)])
        try world.advance(ticks: 50)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))
        XCTAssertEqual(try position(of: first, in: world), .atNode(b, heading: .east))
    }

    /// A travelling train whose track ahead is removed waits for that track,
    /// like any train (decision 15); the service looks up no other route.
    func testATravellingTrainWaitsForRemovedTrackAndIsNotRerouted() throws {
        // Leaving at 0:42 at 512 a minute: 512 - 358 = 154 along by 1.
        var world = try makeServiceWorld([stop(alpha, 0, 0), stop(beta, 1, 1)], rate: 512)
        try world.advance(ticks: 1)
        XCTAssertEqual(try position(of: first, in: world), .onLink(from: b, to: c, offset: 154))

        try world.removeTrack(at: d)
        try world.advance(ticks: 5)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(1))
        XCTAssertEqual(try position(of: first, in: world), .atNode(c, heading: .east))
        XCTAssertEqual(try movement(of: first, in: world).continuation, [c, d])
        XCTAssertEqual(try movement(of: first, in: world).cursor, 1)

        try world.buildTrack(at: d, connections: [.east, .west])
        try world.advance(ticks: 2)
        XCTAssertEqual(world.clock.now.minutes, 8)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        XCTAssertEqual(try position(of: first, in: world), .atNode(d, heading: .east))
    }

    /// The last stop keeps its dwell: the service ends at the last stop's
    /// departure, and the train stays there with its timetable and rate.
    func testTheLastStopWaitsForItsDepartureThenTheServiceEnds() throws {
        let stops = [stop(alpha, 0, 0), stop(beta, 5, 9)]
        var world = try makeServiceWorld(stops)

        // Beta at 2:42; its doors close at 8:51 for the departure at 9.
        try world.advance(ticks: 3)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        try world.advance(ticks: 6)
        XCTAssertEqual(world.clock.now.minutes, 9)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))

        try world.advance(ticks: 1)
        XCTAssertNil(try execution(of: first, in: world))
        let train = try XCTUnwrap(world.train(id: first))
        XCTAssertEqual(train.position, .atNode(d, heading: .east))
        XCTAssertEqual(train.movement.rate, 1024)
        XCTAssertEqual(train.movement.continuation, [])
        XCTAssertEqual(train.timetable, stops)
        XCTAssertEqual(world.stationsStoppedAt(by: first), [beta])

        // No longer a service: manual commands work again.
        try world.reverseTrain(first)
        try world.setTrainTimetable(first, to: [])
    }

    /// The service sets the continuation, never the rate: at rate 0 the
    /// train gets its route when the departure comes and stays put.
    func testATrainWithRateZeroGetsItsRouteButDoesNotMove() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 2), stop(beta, 5, 5)], rate: 0)

        try world.advance(ticks: 3)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(1))
        XCTAssertEqual(try position(of: first, in: world), .atNode(b, heading: .east))
        XCTAssertEqual(try movement(of: first, in: world).continuation, [c, d])
        XCTAssertEqual(world.stationsStoppedAt(by: first), [])
        try world.advance(ticks: 10)
        XCTAssertEqual(try position(of: first, in: world), .atNode(b, heading: .east))

        try world.setTrainMovementRate(first, to: 1024)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.clock.now.minutes, 15)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(1))
        try world.advance(ticks: 1)
        XCTAssertNil(try execution(of: first, in: world))
    }

    // MARK: - Ownership

    /// While a service runs it owns the continuation and the timetable:
    /// giving a path, reversing, unplacing and replacing the timetable are
    /// refused, after the train's own checks and before the command's.
    func testAnActiveServiceRefusesManualControl() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 5), stop(beta, 8, 8)])
        try world.purchaseTrain(named: "Local 2")
        let before = world

        XCTAssertThrowsGameError(try world.setTrainContinuation(unknown, to: [c]), .unknownTrain(unknown))
        XCTAssertThrowsGameError(try world.setTrainContinuation(second, to: [c]), .trainNotPlaced(second))
        XCTAssertThrowsGameError(try world.setTrainContinuation(first, to: [c]), .trainServiceActive(first))
        XCTAssertThrowsGameError(try world.setTrainContinuation(first, to: [e]), .trainServiceActive(first))
        XCTAssertThrowsGameError(try world.setTrainContinuation(first, to: []), .trainServiceActive(first))
        XCTAssertThrowsGameError(try world.reverseTrain(first), .trainServiceActive(first))
        XCTAssertThrowsGameError(try world.reverseTrain(second), .trainNotPlaced(second))
        XCTAssertThrowsGameError(try world.unplaceTrain(first), .trainServiceActive(first))
        XCTAssertThrowsGameError(try world.setTrainTimetable(unknown, to: []), .unknownTrain(unknown))
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: []), .trainServiceActive(first))
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(alpha, 5, 0)]), .trainServiceActive(first))
        XCTAssertThrowsGameError(try world.setTrainTimetable(first, to: [stop(StationID(rawValue: 99), 0, 0)]), .trainServiceActive(first))
        // The track under the train is in use, as for any train.
        XCTAssertThrowsGameError(try world.removeTrack(at: b), .trackInUse(b))
        XCTAssertEqual(world, before)

        // The rate stays the player's.
        try world.setTrainMovementRate(first, to: 0)
        XCTAssertEqual(try movement(of: first, in: world).rate, 0)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))
    }

    /// Stopping ends only the automation: a travelling train keeps its
    /// continuation and rate, carries on to the stop, and stops there under
    /// manual control. A new service starts from the first stop again.
    func testStoppingKeepsEverythingButTheService() throws {
        let stops = [stop(alpha, 0, 0), stop(beta, 1, 1)]
        var world = try makeServiceWorld(stops, rate: 512)
        XCTAssertThrowsGameError(try world.stopTrainService(unknown), .unknownTrain(unknown))
        // Left at 0:42: 154 along by 1.
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(1))
        let before = try XCTUnwrap(world.train(id: first))

        try world.stopTrainService(first)

        let after = try XCTUnwrap(world.train(id: first))
        XCTAssertNil(after.execution)
        XCTAssertNil(after.times)
        XCTAssertEqual(after.position, .onLink(from: b, to: c, offset: 154))
        XCTAssertEqual(after.position, before.position)
        XCTAssertEqual(after.movement, before.movement)
        XCTAssertEqual(after.timetable, stops)
        XCTAssertThrowsGameError(try world.stopTrainService(first), .trainServiceNotActive(first))
        XCTAssertThrowsGameError(try world.startTrainService(first), .trainNotAtFirstStop(first))

        // 154 + 4 x 512 = 2202: at d, the end of its path, by 5.
        try world.advance(ticks: 4)
        XCTAssertEqual(try position(of: first, in: world), .atNode(d, heading: .east))
        XCTAssertEqual(world.stationsStoppedAt(by: first), [beta])
        XCTAssertNil(try execution(of: first, in: world))
        // At Beta, but the timetable starts at Alpha.
        XCTAssertThrowsGameError(try world.startTrainService(first), .trainNotAtFirstStop(first))

        // Stop, edit, start: the way to change a running timetable. Started
        // at 5, it holds until its departure at 6.
        try world.setTrainTimetable(first, to: [stop(beta, 4, 6), stop(gamma, 8, 8)])
        try world.startTrainService(first)
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(1))
    }

    // MARK: - Advancing in batches

    /// Two services, a route that appears only later, and long idle gaps:
    /// `advance(ticks: n)` is `n` single ticks, and a tick at 2x is two at
    /// 1x apart from the speed itself.
    func testBatchesSingleTicksAndDoubleSpeedAgree() throws {
        var start = try makeLineWorld(trainCount: 2)
        try start.placeTrain(first, at: .atNode(b, heading: .east))
        try start.setTrainMovementRate(first, to: 700)
        try start.setTrainTimetable(first, to: [stop(alpha, 0, 3), stop(beta, 4, 4), stop(beta, 4, 30), stop(gamma, 40, 90)])
        try start.startTrainService(first)
        try start.placeTrain(second, at: .atNode(f, heading: .west))
        try start.setTrainMovementRate(second, to: 300)
        try start.removeTrack(at: a)
        try start.setTrainTimetable(second, to: [stop(delta, 0, 10), stop(alpha, 20, 25), stop(beta, 60, 61)])
        try start.startTrainService(second)

        for ticks in [0, 1, 2, 3, 7, 10, 26, 45, 95, 200] {
            var batch = start
            var single = start
            try batch.advance(ticks: ticks)
            for _ in 0..<ticks {
                try single.advance(ticks: 1)
            }
            XCTAssertEqual(batch, single, "\(ticks) ticks")

            var double = start
            double.setSpeed(.double)
            var normal = start
            try double.advance(ticks: ticks)
            try normal.advance(ticks: 2 * ticks)
            double.setSpeed(.normal)
            XCTAssertEqual(double, normal, "\(ticks) ticks at 2x")
        }

        // Build the missing track mid-run: both ways still agree.
        var batch = start
        var single = start
        try batch.advance(ticks: 30)
        try single.advance(ticks: 30)
        try batch.buildTrack(at: a, connections: .east)
        try single.buildTrack(at: a, connections: .east)
        try batch.advance(ticks: 100)
        for _ in 0..<100 {
            try single.advance(ticks: 1)
        }
        XCTAssertEqual(batch, single)
    }

    /// Minutes that change nothing are skipped, but never past a second at
    /// which a dwell moves on: the doors close and the train leaves on time,
    /// all inside one batch. Here the train reaches Beta at 2:42 and holds
    /// for its departure at 5: idle through 3 and 4, its doors close at
    /// 4:51, it leaves at 5 and reaches Gamma at 7.
    func testADepartureAfterIdleMinutesIsMetInsideOneBatch() throws {
        let start = try makeServiceWorld([stop(alpha, 0, 0), stop(beta, 2, 5), stop(gamma, 10, 10)])
        var world = start

        try world.advance(ticks: 7)

        XCTAssertEqual(world.clock.now.minutes, 7)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(2))
        XCTAssertEqual(try position(of: first, in: world), .atNode(f, heading: .east))
        XCTAssertEqual(world.train(id: first)?.times, ServiceTimes(arrival: GameTime(minutes: 7), departure: GameTime(minutes: 5)))
        var single = start
        for _ in 0..<7 {
            try single.advance(ticks: 1)
        }
        XCTAssertEqual(single, world)
    }

    /// Idle time is still skipped at once, and a departure far ahead is met
    /// exactly: a train at 1 unit a minute is exactly 100 units along 100
    /// minutes after it left.
    func testAdvancingFarAheadStillMeetsTheDepartureExactly() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 5_000_000_000), stop(beta, 5_000_002_048, 5_000_002_048)], rate: 1)

        try world.advance(ticks: 5_000_000_100)

        XCTAssertEqual(world.clock.now.minutes, 5_000_000_100)
        XCTAssertEqual(try execution(of: first, in: world), .travellingToStop(1))
        XCTAssertEqual(try position(of: first, in: world), .onLink(from: b, to: c, offset: 100))
    }

    /// The clock may be before second 0 (a save can hold one): a departure
    /// further away than the largest `Int64` still stops nothing and
    /// overflows nothing (found by the save mutation campaign). The clock
    /// starts 5 minutes after the first whole minute after `Int64.min`
    /// seconds.
    func testADepartureFurtherAwayThanAnInt64CanCountIsWaitedFor() throws {
        let start = Int64.min + 8 + 5 * 60
        var world = try makeServiceWorld([stop(alpha, 0, 10), stop(beta, 20, 20)], seconds: start)

        try world.advance(ticks: 1_000)

        XCTAssertEqual(world.clock.now.seconds, start + 1_000 * 60)
        XCTAssertEqual(try execution(of: first, in: world), .waitingAtStop(0))
        XCTAssertEqual(try position(of: first, in: world), .atNode(b, heading: .east))
    }

    // MARK: - Saving

    /// A service is saved as `{"phase", "stop"}` with the train; a train
    /// without one has no key, as trains saved before services did.
    func testServicesAreSavedWithTheTrainAndOldSavesReadAsInactive() throws {
        var world = try makeServiceWorld([stop(alpha, 0, 0), stop(beta, 5, 5), stop(gamma, 9, 9)])
        try world.purchaseTrain(named: "Local 2")
        try world.setTrainTimetable(second, to: [stop(alpha, 0, 0)])
        var text = String(decoding: try encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""execution":{"phase":"waiting","stop":0}"#), text)
        XCTAssertEqual(text.components(separatedBy: #""execution""#).count, 2, "only the running train has a service")

        try world.advance(ticks: 1)
        text = String(decoding: try encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""execution":{"phase":"travelling","stop":1}"#), text)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: encode(world))
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try encode(loaded), try encode(world))

        // Trains saved before services existed: no "execution" key.
        let old = try JSONDecoder().decode(Train.self, from: Data(#"{"id": 1, "name": "A"}"#.utf8))
        XCTAssertNil(old.execution)
        XCTAssertThrowsError(try JSONDecoder().decode(Train.self, from: Data(#"{"id": 1, "name": "A", "execution": null}"#.utf8)))
    }

    /// Saving and loading at any point of a service changes nothing about
    /// how it carries on, including a train waiting for a route and one
    /// whose last track tile was removed before it got there.
    func testSavingMidServiceChangesNoOutcome() throws {
        var world = try makeLineWorld(trainCount: 2)
        try world.placeTrain(first, at: .atNode(b, heading: .east))
        try world.setTrainMovementRate(first, to: 600)
        try world.setTrainTimetable(first, to: [stop(alpha, 0, 1), stop(beta, 3, 3), stop(beta, 3, 7), stop(delta, 9, 12)])
        try world.startTrainService(first)
        try world.placeTrain(second, at: .atNode(f, heading: .west))
        try world.setTrainMovementRate(second, to: 1024)
        try world.setTrainTimetable(second, to: [stop(gamma, 0, 0), stop(far, 3, 3)])
        try world.startTrainService(second)

        for ticks in [1, 1, 2, 1, 3, 1, 5, 40] {
            try world.advance(ticks: ticks)
            var loaded = try JSONDecoder().decode(GameWorld.self, from: encode(world))
            XCTAssertEqual(loaded, world, "after \(world.clock.now.minutes)")
            var continued = world
            try continued.advance(ticks: 3)
            try loaded.advance(ticks: 3)
            XCTAssertEqual(loaded, continued, "after \(world.clock.now.minutes)")
        }
        XCTAssertNil(try execution(of: first, in: world))
        XCTAssertEqual(try position(of: first, in: world), .atNode(f, heading: .east))
        XCTAssertEqual(try execution(of: second, in: world), .waitingAtStop(0))

        // Travelling to Beta after d, its only platform, was removed.
        var removed = try makeServiceWorld([stop(alpha, 0, 0), stop(beta, 1, 1)], rate: 512)
        try removed.advance(ticks: 1)
        try removed.removeTrack(at: d)
        XCTAssertEqual(removed.platforms(of: beta), [])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: encode(removed)), removed)
    }

    /// Bad services are refused when loading, never moved to another stop,
    /// cancelled or otherwise repaired.
    func testMalformedServicesAreRejectedNotRepaired() throws {
        // Local 1 waits at Alpha (stop 0 of four); Local 2 travels from Beta
        // to Alpha on the link d -> c, with c and b still to enter.
        var world = try makeLineWorld(trainCount: 2)
        try world.placeTrain(first, at: .atNode(b, heading: .east))
        try world.setTrainMovementRate(first, to: 1024)
        try world.setTrainTimetable(first, to: [stop(alpha, 0, 5), stop(beta, 8, 10), stop(beta, 10, 10), stop(gamma, 12, 12)])
        try world.startTrainService(first)
        try world.placeTrain(second, at: .atNode(d, heading: .west))
        try world.setTrainMovementRate(second, to: 512)
        try world.setTrainTimetable(second, to: [stop(beta, 0, 0), stop(alpha, 3, 3), stop(gamma, 9, 9)])
        try world.startTrainService(second)
        try world.advance(ticks: 1)
        XCTAssertEqual(try execution(of: second, in: world), .travellingToStop(1))
        XCTAssertEqual(try position(of: second, in: world), .onLink(from: d, to: c, offset: 154))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(world)) as? [String: Any])

        func decode(_ change: (inout [[String: Any]]) -> Void) throws -> GameWorld {
            var object = saved
            var trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
            change(&trains)
            object["trains"] = trains
            return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        }

        XCTAssertEqual(try decode { _ in }, world)
        let malformed: [(String, Any)] = [
            ("null", NSNull()),
            ("empty", [String: Any]()),
            ("a string", "waiting"),
            ("no stop", ["phase": "waiting"]),
            ("no phase", ["stop": 0]),
            ("unknown phase", ["phase": "parked", "stop": 0]),
            ("stop as a string", ["phase": "waiting", "stop": "0"]),
            ("fractional stop", ["phase": "waiting", "stop": 0.5]),
            ("negative stop", ["phase": "waiting", "stop": -1]),
            ("stop past the end", ["phase": "waiting", "stop": 4]),
            // Stop 1 is Beta, but the train is stopped at Alpha.
            ("the wrong station", ["phase": "waiting", "stop": 1]),
            // Nothing travels to the first stop.
            ("travelling to stop 0", ["phase": "travelling", "stop": 0]),
            // A journey that has ended is an arrival, not travel.
            ("travelling but stopped", ["phase": "travelling", "stop": 1]),
        ]
        for (what, value) in malformed {
            XCTAssertThrowsError(try decode { $0[0]["execution"] = value }, what)
        }
        // Local 2 is on a link, heading for c then b (Alpha's platform).
        let malformedTravel: [(String, Any)] = [
            ("waiting on a link", ["phase": "waiting", "stop": 1]),
            ("travelling to stop 0", ["phase": "travelling", "stop": 0]),
            // Stop 2 is Gamma, but the journey ends at b.
            ("a journey that ends elsewhere", ["phase": "travelling", "stop": 2]),
        ]
        for (what, value) in malformedTravel {
            XCTAssertThrowsError(try decode { $0[1]["execution"] = value }, what)
        }
        // Not without a timetable, a placed train, or with a path left while waiting.
        XCTAssertThrowsError(try decode { $0[0]["timetable"] = nil })
        XCTAssertThrowsError(try decode { trains in
            trains[0]["position"] = nil
            trains[0]["movement"] = nil
        })
        XCTAssertThrowsError(try decode { $0[0]["movement"] = ["rate": 1024, "continuation": [["x": 2, "y": 1]], "cursor": 0] })
        // Stage W2b: a service has its times, and they fit what it does and
        // the clock (1:00): Local 1's doors opened at 8 s and close at 4:51,
        // Local 2 left Beta at 42 s.
        XCTAssertEqual(world.train(id: first)?.times, ServiceTimes(arrival: .zero, exchangeEnd: GameTime(seconds: 8)))
        XCTAssertEqual(world.train(id: second)?.times, ServiceTimes(arrival: .zero, departure: GameTime(seconds: 42)))
        let badTimes: [(String, Int, Any?)] = [
            ("a service without times", 0, nil),
            ("explicit null", 0, NSNull()),
            ("no arrival", 0, ["exchangeEnd": 8]),
            ("closing without an exchange", 0, ["arrival": 0, "closing": 30]),
            ("an exchange before the doors open", 0, ["arrival": 0, "exchangeEnd": 7]),
            ("closing before the exchange ends", 0, ["arrival": 0, "exchangeEnd": 20, "closing": 19]),
            ("left the stop before after arriving here", 0, ["arrival": 0, "exchangeEnd": 8, "departure": 1]),
            ("arriving after the clock", 0, ["arrival": 61, "exchangeEnd": 69]),
            ("the doors open after the clock", 0, ["arrival": 55, "exchangeEnd": 63]),
            ("closing after the clock", 0, ["arrival": 0, "exchangeEnd": 8, "closing": 61]),
            ("travelling without leaving", 1, ["arrival": 0]),
            ("travelling with a dwell", 1, ["arrival": 0, "exchangeEnd": 8, "departure": 42]),
            ("leaving before arriving", 1, ["arrival": 10, "departure": 9]),
            ("leaving after the clock", 1, ["arrival": 0, "departure": 61]),
        ]
        for (what, index, value) in badTimes {
            XCTAssertThrowsError(try decode { $0[index]["times"] = value }, what)
        }
        // Without the keys, the same trains load without a service; times
        // without a service are refused.
        let inactive = try decode { trains in
            trains[0]["execution"] = nil
            trains[0]["times"] = nil
            trains[1]["execution"] = nil
            trains[1]["times"] = nil
        }
        XCTAssertEqual(inactive.trains.map(\.execution), [nil, nil])
        XCTAssertThrowsError(try decode { $0[0]["execution"] = nil })
    }
}
