import Foundation
import GameCore
import XCTest

/// Automatic dispatch (Phase 4 Stage Q2b, ARCHITECTURE decision 23): trains
/// assigned to a line, target headways, and the line sending its trains out
/// on round trips from its first stop, a headway apart, as many as its
/// level runs.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class LineDispatchTests: XCTestCase {
    // The line of `TrainServiceTests`, dead ends at both ends, on the track
    // network (Stage F3b, see `TestLine` and `ServiceLineTests`): a node at
    // each tile centre, edges 1 to 6 of 1024, platforms either side of b, d
    // and f, Delta's touching Gamma's past f, Far none:
    //
    //   Alpha(1,0)  Beta(3,0)  Gamma(5,0)
    //       |           |          |
    //   a - b - c - d - e - f - g
    //                          |
    //                      Delta(5,2)        Far(7,3): no platform
    //
    // Alpha to Gamma is four links, b to f. The line plans with a crawl
    // (Stage W2c, `crawl`), so each way takes four minutes; with two
    // minutes at each end a round trip is 12. Stage W2b: a train sent out at
    // T dwells 42 s at Alpha and leaves at T:42, and is back at T + 10:42,
    // its service ending once it has dwelt 42 s there, at T + 11:24. Its
    // own performance is the standard one, which keeps to the 240 s a leg
    // is given on a curve (`along(_:)`).
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let delta = StationID(rawValue: 4)
    private let main = LineID(rawValue: 1)
    private let other = LineID(rawValue: 2)
    private let unknownLine = LineID(rawValue: 9)
    private let one = TrainID(rawValue: 1)
    private let two = TrainID(rawValue: 2)
    private let three = TrainID(rawValue: 3)
    private let ghost = TrainID(rawValue: 99)
    /// The line's performance (Stage W2c): a crawl at 1 km/h, about a link
    /// a minute. It reaches 1 km/h in 8 s and stops from it in 10 s, so four
    /// links take 8 + 221.4 + 10 = 239.4 s, planned as 240.
    private let crawl = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)

    /// How far a train is along a 240 s leg of four links `elapsed` seconds
    /// after it left (Stage W2c): on its standard curve for them.
    private func along(_ elapsed: Int64) -> Int64 {
        runDistance(4 * 1024, in: 240, after: elapsed)
    }

    private func makeLineWorld(minute: Int64 = 0) throws -> GameWorld {
        var world = try GameWorld(
            width: 8, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let delta = try world.buildStation(named: "Delta", at: TestLine.centre(5, 2)).id
        try world.addTrackPlatform(delta, on: line.edge(6), from: 512, to: 1_024)
        try world.buildStation(named: "Far", at: TestLine.centre(7, 3))
        return world
    }

    /// The line world with line 1 Alpha to Gamma running all day, and
    /// `count` trains bought, standing at Alpha facing east at one link a
    /// minute, and assigned to it. The line plans with `crawl`.
    private func makeDispatchWorld(trains count: Int, running: TrainsInService, minute: Int64 = 0) throws -> GameWorld {
        var world = try makeLineWorld(minute: minute)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLinePerformance(main, to: crawl)
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: running)
        for index in 1...count {
            let train = try world.purchaseTrain(named: "T\(index)")
            try world.placeTrain(train.id, at: line.at(1, facingEast: true))
            try world.setTrainMovementRate(train.id, to: 1024)
            try world.assignTrain(train.id, to: main)
        }
        return world
    }

    private func stop(_ station: StationID, _ arrival: Int64, _ departure: Int64, reverses: Bool = false) -> ScheduledStop {
        ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: departure), reverses: reverses)
    }

    /// Alpha to Gamma and back for a train sent out at `minute` facing
    /// east: it arrives at Alpha then and leaves 42 s later (Stage W2b),
    /// reaches Gamma 240 s after leaving (`crawl`), stays 2 minutes and
    /// turns round, and is back at Alpha 240 s after that.
    private func trip(_ minute: Int64, reverses: Bool = false) -> [ScheduledStop] {
        let leaving = minute * 60 + 42
        func time(_ seconds: Int64) -> GameTime { GameTime(seconds: seconds) }
        return [
            ScheduledStop(station: alpha, arrival: GameTime(minutes: minute), departure: time(leaving), reverses: reverses),
            ScheduledStop(station: gamma, arrival: time(leaving + 240), departure: time(leaving + 360), reverses: true),
            ScheduledStop(station: alpha, arrival: time(leaving + 600), departure: time(leaving + 600), reverses: true),
        ]
    }

    private func advance(_ world: inout GameWorld, _ ticks: Int) throws {
        try world.advance(ticks: ticks)
    }

    // MARK: - Assigning trains

    /// Assigning checks the train, the line, that the train is on no line,
    /// and that it runs no service of its own, in that order; it keeps the
    /// line's trains in ID order and changes nothing else.
    func testAssigningChecksInOrderAndChangesOnlyTheLine() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.createLine(named: "Other", stops: [beta, gamma])
        for index in 1...3 {
            try world.purchaseTrain(named: "T\(index)")
        }
        try world.placeTrain(three, at: line.at(1, facingEast: true))
        try world.setTrainTimetable(three, to: [stop(alpha, 0, 5)])
        try world.startTrainService(three)

        var before = world
        XCTAssertThrowsGameError(try world.assignTrain(ghost, to: unknownLine), .unknownTrain(ghost))
        XCTAssertThrowsGameError(try world.assignTrain(one, to: unknownLine), .unknownLine(unknownLine))
        XCTAssertThrowsGameError(try world.assignTrain(three, to: main), .trainServiceActive(three))
        XCTAssertEqual(world, before, "refused commands change nothing")

        // Unplaced trains can be assigned; the line keeps them in ID order.
        try world.assignTrain(two, to: main)
        try world.assignTrain(one, to: main)
        XCTAssertEqual(world.line(id: main)?.trains, [one, two])
        XCTAssertEqual(world.line(id: other)?.trains, [])
        XCTAssertEqual(world.assignedLine(of: one), main)
        XCTAssertNil(world.assignedLine(of: three))
        XCTAssertNil(world.assignedLine(of: ghost))
        XCTAssertEqual(world.trains, before.trains, "assigning changes no train")
        XCTAssertEqual(world.clock, before.clock)
        XCTAssertEqual(world.economy, before.economy, "assigning is free")

        before = world
        XCTAssertThrowsGameError(try world.assignTrain(one, to: main), .trainOnLine(one))
        XCTAssertThrowsGameError(try world.assignTrain(one, to: other), .trainOnLine(one))
        // The line is checked before the train's line.
        XCTAssertThrowsGameError(try world.assignTrain(one, to: unknownLine), .unknownLine(unknownLine))
        XCTAssertEqual(world, before)

        XCTAssertThrowsGameError(try world.unassignTrain(ghost), .unknownTrain(ghost))
        XCTAssertThrowsGameError(try world.unassignTrain(three), .trainNotOnLine(three))
        XCTAssertEqual(world, before)
        try world.unassignTrain(one)
        XCTAssertEqual(world.line(id: main)?.trains, [two])
        XCTAssertNil(world.assignedLine(of: one))
        try world.assignTrain(one, to: other)
        XCTAssertEqual(world.line(id: other)?.trains, [one])
    }

    /// A line runs its trains' timetables and services: those commands are
    /// refused for its trains, after the train is found. Moving an idle
    /// train by hand is still allowed, to bring it to the first stop.
    func testALineOwnsItsTrainsTimetablesAndServices() throws {
        var world = try makeDispatchWorld(trains: 1, running: .none)
        let before = world
        XCTAssertThrowsGameError(try world.setTrainTimetable(ghost, to: []), .unknownTrain(ghost))
        XCTAssertThrowsGameError(try world.setTrainTimetable(one, to: [stop(alpha, 0, 0)]), .trainOnLine(one))
        // Before the timetable is checked.
        XCTAssertThrowsGameError(try world.setTrainTimetable(one, to: [stop(alpha, 5, 0)]), .trainOnLine(one))
        XCTAssertThrowsGameError(try world.startTrainService(one), .trainOnLine(one))
        XCTAssertThrowsGameError(try world.stopTrainService(one), .trainOnLine(one))
        XCTAssertThrowsGameError(try world.stopTrainService(ghost), .unknownTrain(ghost))
        XCTAssertEqual(world, before)

        try world.reverseTrain(one)
        try world.setTrainContinuation(one, along: [])
        try world.unplaceTrain(one)
        try world.placeTrain(one, at: line.at(5, facingEast: false))
        XCTAssertEqual(world.assignedLine(of: one), main)
    }

    // MARK: - Target headways

    /// Targets are checked after the line, from 2 to 1440 minutes. At a
    /// level with a target the line runs the fewest trains that keep to it
    /// and the target is the headway; other levels run their count.
    func testTargetHeadwaysSetTheTrainsAndTheHeadway() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLinePerformance(main, to: crawl)
        // The line plans from the end of Alpha's platform past b, 512 on: out
        // 3584 units (56 m: 8 s up to 1 km/h, 192.6 s at it, 10 s to stop,
        // 210.6, so 211 s), back 4096 (240 s); with the ends, 691 s, 12
        // minutes. A train sent out from b drives 4096 each way (`trip`).
        XCTAssertEqual(world.lineJourney(main)?.legs.map(\.seconds), [211, 240])
        XCTAssertEqual(world.lineJourney(main)?.roundTripSeconds, 691)
        XCTAssertEqual(world.lineJourney(main)?.roundTripMinutes, 12)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 4, offPeak: 0, low: 1))
        let before = world
        XCTAssertThrowsGameError(try world.setLineTargetHeadways(unknownLine, to: TargetHeadways(peak: 0)), .unknownLine(unknownLine))
        for bad: Int64 in [1, 0, -5, 1441, .max, .min] {
            XCTAssertThrowsGameError(try world.setLineTargetHeadways(main, to: TargetHeadways(offPeak: bad)), .invalidHeadway)
        }
        XCTAssertEqual(world, before)

        // Round trip 12, at most 6 trains. Counts: 4 trains, 3 minutes
        // apart; none; 1 train, 12 minutes.
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak), 4)
        XCTAssertEqual(world.lineHeadway(main, at: .peak), 3)
        XCTAssertEqual(world.lineTrainsInService(main, at: .offPeak), 0)
        XCTAssertNil(world.lineHeadway(main, at: .offPeak))

        // 12 / 5 rounded up is 3 trains; 12 / 3 is 4, shorter than 5.
        try world.setLineTargetHeadways(main, to: TargetHeadways(peak: 5, offPeak: 20))
        XCTAssertEqual(world.line(id: main)?.targetHeadways, TargetHeadways(peak: 5, offPeak: 20))
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak), 3)
        XCTAssertEqual(world.lineHeadway(main, at: .peak), 5)
        // One train makes a round trip in 12 and waits 8 for the next.
        XCTAssertEqual(world.lineTrainsInService(main, at: .offPeak), 1)
        XCTAssertEqual(world.lineHeadway(main, at: .offPeak), 20)
        // No target at low: the count as before.
        XCTAssertEqual(world.lineTrainsInService(main, at: .low), 1)
        XCTAssertEqual(world.lineHeadway(main, at: .low), 12)

        // The limits themselves: 2 gives the most trains, 1440 one.
        try world.setLineTargetHeadways(main, to: TargetHeadways(peak: 2, low: 1440))
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak), 6)
        XCTAssertEqual(world.lineHeadway(main, at: .peak), 2)
        XCTAssertEqual(world.lineTrainsInService(main, at: .low), 1)
        XCTAssertEqual(world.lineHeadway(main, at: .low), 1440)
        XCTAssertEqual(world.lineTrainsInService(main, at: .offPeak), 0, "back to the count, which is 0")

        try world.setLineTargetHeadways(main, to: .none)
        XCTAssertEqual(world.lineHeadway(main, at: .peak), 3)
        // Without a journey there is nothing to derive, target or not.
        try world.setLineStops(main, to: [alpha, StationID(rawValue: 5)])
        try world.setLineTargetHeadways(main, to: TargetHeadways(peak: 5))
        XCTAssertNil(world.lineTrainsInService(main, at: .peak))
        XCTAssertNil(world.lineHeadway(main, at: .peak))
    }

    // MARK: - Dispatch

    /// Two trains, round trip 12: the line sends one out every 6 minutes,
    /// each on a round trip that leaves 42 s later, turns round at Gamma,
    /// comes back to Alpha 10 minutes after it left, turns round and waits
    /// there to be sent out again.
    func testALineSendsTrainsOutAHeadwayApartAndBringsThemBack() throws {
        var world = try makeDispatchWorld(trains: 2, running: TrainsInService(peak: 2, offPeak: 2, low: 2))
        XCTAssertEqual(world.lineHeadway(main, at: .low), 6)

        try advance(&world, 1)
        var first = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(first.timetable, trip(0))
        XCTAssertNil(first.timetablePeriod)
        XCTAssertEqual(first.execution, .travellingToStop(1))
        XCTAssertEqual(first.position, line.between(1, 2, offset: along(18)))
        XCTAssertEqual(first.times?.run, ServiceRun(start: GameTime(seconds: 42), length: 4 * 1024, seconds: 240), "the leg's 240 s")
        XCTAssertEqual(first.movement.edges, [2, 3, 4, 5].map(line.edge))
        XCTAssertEqual(first.movement.cursor, 1)
        XCTAssertEqual(world.train(id: two)?.execution, nil, "one train per headway")
        XCTAssertEqual(world.train(id: two)?.timetable, [])
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 0))

        // Gamma at 4:42; waits there until 6:42.
        try advance(&world, 5)
        first = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(world.clock.now, GameTime(minutes: 6))
        XCTAssertEqual(first.execution, .waitingAtStop(1))
        XCTAssertEqual(first.position, line.at(5, facingEast: true))
        XCTAssertNil(world.train(id: two)?.execution)

        // At 6 the second train is sent out, and at 6:42 both leave, the
        // first turned round at Gamma.
        try advance(&world, 1)
        first = try XCTUnwrap(world.train(id: one))
        var second = try XCTUnwrap(world.train(id: two))
        XCTAssertEqual(second.timetable, trip(6))
        XCTAssertEqual(second.execution, .travellingToStop(1))
        XCTAssertEqual(second.position, line.between(1, 2, offset: along(18)))
        XCTAssertEqual(first.execution, .travellingToStop(2))
        XCTAssertEqual(first.position, line.between(5, 4, offset: along(18)))
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 6))

        // At 10:42 the first is back at Alpha and the second at Gamma.
        try advance(&world, 3)
        first = try XCTUnwrap(world.train(id: one))
        second = try XCTUnwrap(world.train(id: two))
        XCTAssertEqual(first.execution, .travellingToStop(2))
        XCTAssertEqual(first.position, line.between(2, 1, offset: along(198) - 3 * 1024))
        try advance(&world, 1)
        first = try XCTUnwrap(world.train(id: one))
        second = try XCTUnwrap(world.train(id: two))
        XCTAssertEqual(first.execution, .waitingAtStop(2))
        XCTAssertEqual(first.position, line.at(1, facingEast: false))
        XCTAssertEqual(second.execution, .waitingAtStop(1))

        // Its service ends at 11:24: turned round, keeping the trip's
        // timetable. It stopped at Alpha's platform past b going west, so
        // turned round it stands at the start of that platform's edge,
        // edge 2 forward at 0, its path ending there.
        try advance(&world, 1)
        first = try XCTUnwrap(world.train(id: one))
        XCTAssertNil(first.execution)
        XCTAssertNil(first.times)
        XCTAssertEqual(first.position, .onEdge(TrackTraversal(edge: line.edge(2), direction: .forward), offset: 0))
        XCTAssertEqual(first.timetable, trip(0))
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 6), "not due again until 12")

        // At 12 it is sent out again.
        try advance(&world, 1)
        first = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(first.timetable, trip(12))
        XCTAssertEqual(first.execution, .travellingToStop(1))
        XCTAssertEqual(world.train(id: two)?.execution, .travellingToStop(2))
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 12))
    }

    /// A ready train facing away from the way it can go is turned round as
    /// it leaves: its first stop is marked to.
    func testATrainFacingAwayTurnsRoundAsItLeaves() throws {
        var world = try makeDispatchWorld(trains: 1, running: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.reverseTrain(one)
        // At b facing west, at the start of edge 1 going back. Reversing
        // clears the path, so it would run on to a; a path that ends where it
        // stands keeps it stopped at Alpha.
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(TrackTraversal(edge: line.edge(1), direction: .backward), offset: 0))
        try world.setTrainContinuation(one, along: [], stoppingAt: 0)

        try advance(&world, 1)
        let train = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(train.timetable, trip(0, reverses: true))
        XCTAssertEqual(train.position, line.between(1, 2, offset: along(18)))
        XCTAssertEqual(train.execution, .travellingToStop(1))
    }

    /// Only a ready train goes: not a train with rate 0, an unplaced one,
    /// one elsewhere or still moving, or one that cannot drive the trip.
    /// The line sends none out meanwhile, and its last dispatch stays.
    func testOnlyAReadyTrainIsSentOut() throws {
        var world = try makeDispatchWorld(trains: 3, running: TrainsInService(peak: 3, offPeak: 3, low: 3))
        try world.setTrainMovementRate(one, to: 0)
        try world.unplaceTrain(two)
        try world.unplaceTrain(three)
        try world.placeTrain(three, at: line.at(3, facingEast: true))
        let before = world
        try advance(&world, 30)
        XCTAssertEqual(world.trains, before.trains, "no train was ready")
        XCTAssertNil(world.line(id: main)?.lastDispatch)

        // Moving towards Alpha, it is not ready until it stops there.
        try world.reverseTrain(three)
        try world.setTrainContinuation(three, along: line.path(from: 2, through: [1]))
        try world.setTrainMovementRate(three, to: 1024)
        try advance(&world, 1)
        XCTAssertNil(world.train(id: three)?.execution)
        XCTAssertEqual(world.train(id: three)?.position, line.at(2, facingEast: false))
        // It reaches Alpha at 32 and is sent out in the next step, to be
        // turned round as it leaves.
        try advance(&world, 1)
        XCTAssertEqual(world.train(id: three)?.position, line.at(1, facingEast: false))
        XCTAssertNil(world.train(id: three)?.execution)
        try advance(&world, 1)
        XCTAssertEqual(world.train(id: three)?.timetable, trip(32, reverses: true))
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 32))

        // A train that could not drive the trip is not sent out: with e
        // gone neither way reaches Gamma.
        var cut = try makeDispatchWorld(trains: 1, running: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try cut.removeTrackPlatform(beta, on: line.edge(4), from: 0)
        try cut.removeTrackEdge(line.edge(4))
        let still = cut
        try advance(&cut, 20)
        XCTAssertEqual(cut.trains, still.trains)
        XCTAssertNil(cut.lineJourney(main))
        // Rebuilt (a new edge, 7), the next call sends it out at once.
        try cut.buildTrackEdge(from: line.node(3), to: line.node(4))
        try advance(&cut, 1)
        XCTAssertEqual(cut.train(id: one)?.timetable, trip(20))
    }

    /// Fewer trains at a level: the line sends none out while as many as
    /// the level runs are out, so trains coming back wait at the first
    /// stop, the lowest ID going first when one is due. More trains: the
    /// waiting ones go, a headway apart.
    func testTheLevelSetsHowManyTrainsAreOut() throws {
        var world = try makeDispatchWorld(trains: 2, running: TrainsInService(peak: 2, offPeak: 2, low: 1))
        // Low until 00:30, then peak.
        try world.setServiceDay(ServiceDay(bands: [ServiceDay.Band(start: 0, level: .low), ServiceDay.Band(start: 30, level: .peak)]))

        // Low: one train, every 12 minutes, and it is always train 1.
        for minute: Int64 in [0, 12, 24] {
            try advance(&world, Int(minute - world.clock.now.minutes) + 1)
            XCTAssertEqual(world.train(id: one)?.timetable, trip(minute))
            XCTAssertNil(world.train(id: two)?.execution)
            XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: minute))
        }
        // Peak at 30: 6 minutes after 24, and one train out, so train 2
        // goes; at 36 train 1, back since 34:42 and its service over at
        // 35:24.
        try advance(&world, 6)
        XCTAssertEqual(world.train(id: two)?.timetable, trip(30))
        XCTAssertEqual(world.train(id: two)?.execution, .travellingToStop(1))
        try advance(&world, 6)
        XCTAssertEqual(world.train(id: one)?.timetable, trip(36))

        // One train again: 12 minutes after 36, and none out by then.
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try advance(&world, 11)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 48))
        XCTAssertNil(world.train(id: one)?.execution, "back since 46:42, done at 47:24")
        XCTAssertNil(world.train(id: two)?.execution, "back since 40:42, and waiting")
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 36))
        try advance(&world, 1)
        XCTAssertEqual(world.train(id: one)?.timetable, trip(48))
        XCTAssertNil(world.train(id: two)?.execution)
        XCTAssertEqual(world.train(id: two)?.timetable, trip(30))

        // None at all: nobody goes, however long.
        try world.setLineTrainsInService(main, to: .none)
        try advance(&world, 200)
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 48))
    }

    /// A target longer than the round trip: one train, which waits at the
    /// first stop for the rest of the headway.
    func testATargetHeadwayKeepsATrainWaitingAtTheFirstStop() throws {
        var world = try makeDispatchWorld(trains: 2, running: .none)
        try world.setLineTargetHeadways(main, to: TargetHeadways(peak: 20, offPeak: 20, low: 20))
        try advance(&world, 1)
        XCTAssertEqual(world.train(id: one)?.timetable, trip(0))
        try advance(&world, 19)
        XCTAssertNil(world.train(id: one)?.execution, "back at 10:42, done at 11:24, waiting")
        XCTAssertNil(world.train(id: two)?.execution, "one train keeps to 20 minutes")
        try advance(&world, 1)
        XCTAssertEqual(world.train(id: one)?.timetable, trip(20))
        try advance(&world, 20)
        XCTAssertEqual(world.train(id: one)?.timetable, trip(40))
        XCTAssertEqual(world.train(id: two)?.timetable, [])
    }

    /// The line's window: nothing leaves while it is closed; the first
    /// train goes the minute it opens. Nothing leaves before minute 0.
    func testTheWindowAndMinuteZero() throws {
        var world = try makeDispatchWorld(trains: 1, running: TrainsInService(peak: 1, offPeak: 1, low: 1), minute: 300)
        try world.setLineServiceWindow(main, to: .hours(open: 360, close: 1440))
        try advance(&world, 60)
        XCTAssertNil(world.train(id: one)?.execution)
        XCTAssertNil(world.line(id: main)?.lastDispatch)
        try advance(&world, 1)
        XCTAssertEqual(world.train(id: one)?.timetable, trip(360))

        var early = try makeDispatchWorld(trains: 1, running: TrainsInService(peak: 1, offPeak: 1, low: 1), minute: -5)
        try advance(&early, 5)
        XCTAssertNil(early.train(id: one)?.execution)
        try advance(&early, 1)
        XCTAssertEqual(early.train(id: one)?.timetable, trip(0))
    }

    /// Taking a train off the line, or removing the line, ends only the
    /// assignment: the trip carries on as an ordinary service, which can
    /// then be stopped, and nothing more is sent out.
    func testTakingATrainOffKeepsItsTrip() throws {
        var world = try makeDispatchWorld(trains: 2, running: TrainsInService(peak: 2, offPeak: 2, low: 2))
        try advance(&world, 2)
        try world.unassignTrain(one)
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1))
        try advance(&world, 9)
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(2), "on time at Alpha at 10:42")
        XCTAssertEqual(world.train(id: two)?.timetable, trip(6), "train 2 still goes at 6")
        try advance(&world, 4)
        XCTAssertNil(world.train(id: one)?.execution)
        XCTAssertEqual(world.train(id: one)?.timetable, trip(0), "not sent out again")

        try world.removeLine(main)
        XCTAssertNil(world.assignedLine(of: two))
        XCTAssertEqual(world.train(id: two)?.execution, .travellingToStop(2))
        try world.stopTrainService(two)
        XCTAssertNil(world.train(id: two)?.execution)
    }

    /// The shortcut over steps where nothing changes stops at every minute
    /// a line could send a train out: a long batch is the same as single
    /// ticks, across level changes, targets and the window.
    func testLongBatchesMatchSingleTicks() throws {
        var world = try makeDispatchWorld(trains: 3, running: TrainsInService(peak: 3, offPeak: 2, low: 1), minute: 1400)
        try world.setLineServiceWindow(main, to: .hours(open: 360, close: 1500))
        try world.setLineTargetHeadways(main, to: TargetHeadways(offPeak: 45))
        var single = world
        try world.advance(ticks: 3000)
        for _ in 0..<3000 {
            try single.advance(ticks: 1)
        }
        XCTAssertEqual(world, single)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 4400))
        XCTAssertNotNil(world.line(id: main)?.lastDispatch)
    }

    // MARK: - Saving

    /// Lines save their targets, trains and last dispatch only when they
    /// have them; saves without them read as having none; bad values are
    /// rejected, not repaired.
    func testSavingKeepsTheLinesTrainsAndDispatch() throws {
        var world = try makeDispatchWorld(trains: 2, running: TrainsInService(peak: 2, offPeak: 2, low: 2))
        try world.setLineTargetHeadways(main, to: TargetHeadways(peak: 7))
        try world.createLine(named: "Other", stops: [beta, gamma])
        try advance(&world, 3)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        XCTAssertEqual(try encoder.encode(JSONDecoder().decode(GameWorld.self, from: data)), data)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lines = try XCTUnwrap(json["lines"] as? [[String: Any]])
        XCTAssertEqual(lines[0]["trains"] as? [Int], [1, 2])
        XCTAssertEqual(lines[0]["lastDispatch"] as? Int, 0)
        XCTAssertEqual(lines[0]["targetHeadways"] as? [String: Int], ["peak": 7])
        XCTAssertNil(lines[1]["trains"], "written only when there are trains")
        XCTAssertNil(lines[1]["lastDispatch"])
        XCTAssertNil(lines[1]["targetHeadways"])

        func mutated(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var copy = json
            var line = lines[0]
            change(&line)
            copy["lines"] = [line, lines[1]]
            return try JSONSerialization.data(withJSONObject: copy)
        }
        for (what, bad) in try [
            ("unsorted trains", mutated { $0["trains"] = [2, 1] }),
            ("a train twice", mutated { $0["trains"] = [1, 1] }),
            ("an unknown train", mutated { $0["trains"] = [1, 2, 7] }),
            ("a null train list", mutated { $0["trains"] = NSNull() }),
            ("a dispatch before second 0", mutated { $0["lastDispatch"] = -1 }),
            // Stage W2a: saved times are seconds; the clock is at 180.
            ("a dispatch after the clock", mutated { $0["lastDispatch"] = 4 * 60 }),
            ("a null dispatch", mutated { $0["lastDispatch"] = NSNull() }),
            ("a target of 1", mutated { $0["targetHeadways"] = ["peak": 1] }),
            ("a target over a day", mutated { $0["targetHeadways"] = ["low": 1441] }),
            ("a null target", mutated { $0["targetHeadways"] = ["low": NSNull()] }),
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: bad), what)
        }
        // A train on two lines.
        var both = json
        var second = lines[1]
        second["trains"] = [2]
        both["lines"] = [lines[0], second]
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: both)))

        // Without the new keys, a line reads as having none of them.
        var old = json
        old["lines"] = lines.map { line in line.filter { !["trains", "lastDispatch", "targetHeadways"].contains($0.key) } }
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(loaded.line(id: main)?.trains, [])
        XCTAssertNil(loaded.line(id: main)?.lastDispatch)
        XCTAssertEqual(loaded.line(id: main)?.targetHeadways, TargetHeadways.none)
    }
}
