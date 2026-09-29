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
    // The line of `TrainServiceTests`, dead ends at both ends:
    //
    //   Alpha(1,0)  Beta(3,0)  Gamma(5,0)
    //       |           |          |
    //   a - b - c - d - e - f - g
    //                          |
    //                      Delta(5,2)        Far(7,3): no platform
    //
    // Alpha to Gamma is four links, b to f, so four minutes each way at the
    // default rate; with two minutes at each end a round trip is 12.
    private let b = GridPosition(x: 1, y: 1)
    private let c = GridPosition(x: 2, y: 1)
    private let d = GridPosition(x: 3, y: 1)
    private let e = GridPosition(x: 4, y: 1)
    private let f = GridPosition(x: 5, y: 1)
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

    private func makeLineWorld(minute: Int64 = 0) throws -> GameWorld {
        var world = try GameWorld(
            width: 8, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: .east)
        for tile in [b, c, d, e, f] {
            try world.buildTrack(at: tile, connections: [.east, .west])
        }
        try world.buildTrack(at: GridPosition(x: 6, y: 1), connections: .west)
        try world.buildStation(named: "Alpha", at: GridPosition(x: 1, y: 0))
        try world.buildStation(named: "Beta", at: GridPosition(x: 3, y: 0))
        try world.buildStation(named: "Gamma", at: GridPosition(x: 5, y: 0))
        try world.buildStation(named: "Delta", at: GridPosition(x: 5, y: 2))
        try world.buildStation(named: "Far", at: GridPosition(x: 7, y: 3))
        return world
    }

    /// The line world with line 1 Alpha to Gamma running all day, and
    /// `count` trains bought, standing at Alpha facing east at one link a
    /// minute, and assigned to it.
    private func makeDispatchWorld(trains count: Int, running: TrainsInService, minute: Int64 = 0) throws -> GameWorld {
        var world = try makeLineWorld(minute: minute)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: running)
        for index in 1...count {
            let train = try world.purchaseTrain(named: "T\(index)")
            try world.placeTrain(train.id, at: .atNode(b, heading: .east))
            try world.setTrainMovementRate(train.id, to: 1024)
            try world.assignTrain(train.id, to: main)
        }
        return world
    }

    private func stop(_ station: StationID, _ arrival: Int64, _ departure: Int64, reverses: Bool = false) -> ScheduledStop {
        ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: departure), reverses: reverses)
    }

    /// Alpha to Gamma and back, leaving Alpha at `minute` facing east.
    private func trip(_ minute: Int64) -> [ScheduledStop] {
        [stop(alpha, minute, minute), stop(gamma, minute + 4, minute + 6, reverses: true), stop(alpha, minute + 10, minute + 10, reverses: true)]
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
        try world.placeTrain(three, at: .atNode(b, heading: .east))
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
        try world.setTrainContinuation(one, to: [GridPosition(x: 0, y: 1)])
        try world.unplaceTrain(one)
        try world.placeTrain(one, at: .atNode(f, heading: .west))
        XCTAssertEqual(world.assignedLine(of: one), main)
    }

    // MARK: - Target headways

    /// Targets are checked after the line, from 2 to 1440 minutes. At a
    /// level with a target the line runs the fewest trains that keep to it
    /// and the target is the headway; other levels run their count.
    func testTargetHeadwaysSetTheTrainsAndTheHeadway() throws {
        var world = try makeLineWorld()
        try world.createLine(named: "Main", stops: [alpha, gamma])
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
    /// each on a round trip that leaves in the same step, turns round at
    /// Gamma, comes back to Alpha 10 minutes after it left, turns round and
    /// waits there to be sent out again.
    func testALineSendsTrainsOutAHeadwayApartAndBringsThemBack() throws {
        var world = try makeDispatchWorld(trains: 2, running: TrainsInService(peak: 2, offPeak: 2, low: 2))
        XCTAssertEqual(world.lineHeadway(main, at: .low), 6)

        try advance(&world, 1)
        var first = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(first.timetable, trip(0))
        XCTAssertNil(first.timetablePeriod)
        XCTAssertEqual(first.execution, .travellingToStop(1))
        XCTAssertEqual(first.position, .atNode(c, heading: .east))
        XCTAssertEqual(first.movement.continuation, [c, d, e, f])
        XCTAssertEqual(first.movement.cursor, 1)
        XCTAssertEqual(world.train(id: two)?.execution, nil, "one train per headway")
        XCTAssertEqual(world.train(id: two)?.timetable, [])
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 0))

        // Gamma at 4; waits there until 6.
        try advance(&world, 5)
        first = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(world.clock.now, GameTime(minutes: 6))
        XCTAssertEqual(first.execution, .waitingAtStop(1))
        XCTAssertEqual(first.position, .atNode(f, heading: .east))
        XCTAssertNil(world.train(id: two)?.execution)

        // At 6 the second train goes, and the first turns round at Gamma.
        try advance(&world, 1)
        first = try XCTUnwrap(world.train(id: one))
        var second = try XCTUnwrap(world.train(id: two))
        XCTAssertEqual(second.timetable, trip(6))
        XCTAssertEqual(second.execution, .travellingToStop(1))
        XCTAssertEqual(second.position, .atNode(c, heading: .east))
        XCTAssertEqual(first.execution, .travellingToStop(2))
        XCTAssertEqual(first.position, .atNode(e, heading: .west))
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 6))

        // At 10 the first is back at Alpha and the second at Gamma.
        try advance(&world, 3)
        first = try XCTUnwrap(world.train(id: one))
        second = try XCTUnwrap(world.train(id: two))
        XCTAssertEqual(first.execution, .waitingAtStop(2))
        XCTAssertEqual(first.position, .atNode(b, heading: .west))
        XCTAssertEqual(second.execution, .waitingAtStop(1))

        // Its service ends at 10: turned round, keeping the trip's timetable.
        try advance(&world, 1)
        first = try XCTUnwrap(world.train(id: one))
        XCTAssertNil(first.execution)
        XCTAssertEqual(first.position, .atNode(b, heading: .east))
        XCTAssertEqual(first.timetable, trip(0))
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 6), "not due again until 12")

        // At 12 it goes again.
        try advance(&world, 2)
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
        XCTAssertEqual(world.train(id: one)?.position, .atNode(b, heading: .west))

        try advance(&world, 1)
        let train = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(train.timetable, [stop(alpha, 0, 0, reverses: true)] + trip(0).dropFirst())
        XCTAssertEqual(train.position, .atNode(c, heading: .east))
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
        try world.placeTrain(three, at: .atNode(d, heading: .east))
        let before = world
        try advance(&world, 30)
        XCTAssertEqual(world.trains, before.trains, "no train was ready")
        XCTAssertNil(world.line(id: main)?.lastDispatch)

        // Moving towards Alpha, it is not ready until it stops there.
        try world.reverseTrain(three)
        try world.setTrainContinuation(three, to: [c, b])
        try world.setTrainMovementRate(three, to: 1024)
        try advance(&world, 1)
        XCTAssertNil(world.train(id: three)?.execution)
        XCTAssertEqual(world.train(id: three)?.position, .atNode(c, heading: .west))
        // It reaches Alpha at 32 and goes in the next step, turned round.
        try advance(&world, 1)
        XCTAssertEqual(world.train(id: three)?.position, .atNode(b, heading: .west))
        XCTAssertNil(world.train(id: three)?.execution)
        try advance(&world, 1)
        XCTAssertEqual(world.train(id: three)?.timetable.first, stop(alpha, 32, 32, reverses: true))
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 32))

        // A train that could not drive the trip is not sent out: with e
        // gone neither way reaches Gamma.
        var cut = try makeDispatchWorld(trains: 1, running: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try cut.removeTrack(at: e)
        let still = cut
        try advance(&cut, 20)
        XCTAssertEqual(cut.trains, still.trains)
        XCTAssertNil(cut.lineJourney(main))
        // Rebuilt, the next call sends it out at once.
        try cut.buildTrack(at: e, connections: [.east, .west])
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
        // goes; at 36 train 1, back since 34.
        try advance(&world, 6)
        XCTAssertEqual(world.train(id: two)?.timetable, trip(30))
        XCTAssertEqual(world.train(id: two)?.execution, .travellingToStop(1))
        try advance(&world, 6)
        XCTAssertEqual(world.train(id: one)?.timetable, trip(36))

        // One train again: 12 minutes after 36, and none out by then.
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try advance(&world, 11)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 48))
        XCTAssertNil(world.train(id: one)?.execution, "back since 46")
        XCTAssertNil(world.train(id: two)?.execution, "back since 40, and waiting")
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
        XCTAssertNil(world.train(id: one)?.execution, "back at 10, waiting")
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
        try advance(&world, 8)
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(2), "on time at Alpha at 10")
        XCTAssertEqual(world.train(id: two)?.timetable, trip(6), "train 2 still goes at 6")
        try advance(&world, 5)
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
            ("a dispatch before minute 0", mutated { $0["lastDispatch"] = -1 }),
            ("a dispatch after the clock", mutated { $0["lastDispatch"] = 4 }),
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
