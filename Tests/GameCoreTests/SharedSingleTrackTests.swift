import Foundation
@testable import GameCore
import XCTest

/// Two lines sharing a single track with no passing place (decision 255,
/// docs/research/CORE_LOOP_2026-10-16.md §1.2): C ── A ── B, a shuttle
/// between A and B, and a second line from C through A to B. The second
/// line's train can never pass the shuttle, so it cannot reach B while the
/// shuttle runs; under traffic control the two used to stand face to face
/// for good.
final class SharedSingleTrackTests: XCTestCase {
    static let c = StationID(rawValue: 1)
    static let a = StationID(rawValue: 2)
    static let b = StationID(rawValue: 3)

    /// The track, the stations and both lines, each with its train at its
    /// first stop: the shuttle at A heading for B, the other at C heading
    /// for A.
    func world() throws -> (world: GameWorld, shuttle: TrainID, through: TrainID) {
        var world = try GameWorld(bounds: WorldBounds(width: 36_864, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal))
        for x in [Int64(1_024), 17_408, 33_792] { _ = try world.buildTrackNode(at: WorldCoordinate(x: x, y: 4_096)) }
        // e1: A → B, e2: A → C.
        _ = try world.buildTrackEdge(from: .node(2), to: .node(3))
        _ = try world.buildTrackEdge(from: .node(2), to: .node(1))
        for (name, x) in [("C", Int64(3_072)), ("A", 17_408), ("B", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 6_144))
        }
        let length = try XCTUnwrap(world.trackEdge(.edge(1))?.length)
        try world.addTrackPlatform(Self.a, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(Self.b, on: .edge(1), from: length - 3_072, to: length - 1_024)
        try world.addTrackPlatform(Self.c, on: .edge(2), from: length - 3_072, to: length - 1_024)
        try world.setTrafficControl(true)
        let shuttle = try line(&world, stops: [Self.a, Self.b], at: TrackTraversal(edge: .edge(1), direction: .forward))
        let through = try line(&world, stops: [Self.c, Self.a, Self.b], at: TrackTraversal(edge: .edge(2), direction: .backward))
        return (world, shuttle, through)
    }

    private func line(_ world: inout GameWorld, stops: [StationID], at traversal: TrackTraversal) throws -> TrainID {
        let line = try world.createLine(named: "L\(world.lines.count + 1)", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try SingleTrackMeet.stand(&world, edge: traversal, offset: 3_072)
        try world.assignTrain(train, to: line)
        return train
    }

    /// Over a day both trains keep making calls: in every three hours
    /// the shuttle and the other train each come to a stop again and
    /// again (an empty list of deadlocked trains alone would not show it:
    /// a train held to a timetable makes no calls either).
    func testTwoLinesSharingASingleTrackKeepRunning() throws {
        var (world, shuttle, through) = try world()
        var last: [TrainID: TimetableExecution?] = [:]
        var arrivals: [TrainID: [Int]] = [shuttle: [], through: []]
        var calls: [TrainID: Set<StationID>] = [:]
        for minute in 0..<1_440 {
            try world.advance(ticks: 1)
            for id in [shuttle, through] {
                let execution = world.train(id: id)?.execution
                if case .waitingAtStop? = execution, execution != last[id] ?? nil {
                    arrivals[id]!.append(minute)
                }
                last[id] = execution
                calls[id, default: []].formUnion(world.stationsStoppedAt(by: id))
            }
        }
        for window in stride(from: 0, to: 1_440, by: 180) {
            for id in [shuttle, through] {
                let made = arrivals[id]!.filter { (window..<window + 180).contains($0) }.count
                XCTAssertGreaterThanOrEqual(made, 4, "train \(id.rawValue) made \(made) calls from minute \(window)")
            }
        }
        XCTAssertEqual(calls[shuttle], [Self.a, Self.b])
        XCTAssertEqual(calls[through], [Self.c, Self.a], "it never reaches B past the shuttle")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// Minute 4: the shuttle waits at B for A, where the other train
    /// waits for B. Minute 5: the dispatcher turns that one back at A, as
    /// its timetable comes back there from B, leaving B out; it waits at
    /// A again, turned round, until it is due to leave for C, and the
    /// shuttle is no longer stuck. A save there loads as it was.
    func testTheThroughTrainTurnsBackShortAtTheSharedStation() throws {
        var (world, shuttle, through) = try world()
        try world.advance(ticks: 4)
        XCTAssertEqual(world.deadlockedTrains(), [shuttle, through])
        XCTAssertEqual(world.train(id: through)?.execution, .waitingAtStop(1))
        XCTAssertEqual(world.train(id: through)?.timetable.map(\.station), [Self.c, Self.a, Self.b, Self.a, Self.c])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(world.train(id: through)?.execution, .waitingAtStop(3))
        XCTAssertEqual(world.stationsStoppedAt(by: through), [Self.a])
        XCTAssertNil(WorldInvariants.roundTripProblem(of: world))
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// A save made just before the turn loads and runs on to the same
    /// world, minute by minute, as the world it was made from.
    func testASaveBeforeTheTurnRunsOnAlike() throws {
        var (world, _, _) = try world()
        try world.advance(ticks: 4)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        for _ in 0..<120 {
            try world.advance(ticks: 1)
            try loaded.advance(ticks: 1)
            XCTAssertEqual(loaded, world)
        }
    }

    /// The other train carries a hundred riders from C to B. When it turns
    /// back at A they get off there, abandoned, and are counted getting
    /// off at A, its doors taking as long for them as at any call. The
    /// turn runs nowhere: no departure, distance or load is counted for
    /// it.
    func testRidersForTheCallLeftOutGetOffWhereItTurns() throws {
        var (world, _, through) = try world()
        world.setEconomyMode(.management)
        world.setLineAccounts(true)
        for station in [Self.c, Self.a, Self.b] {
            try world.setStationDemand(station, to: StationDemand(kind: .office, dailyTrips: 0))
        }
        let line = try XCTUnwrap(world.assignedLine(of: through))
        let record = try XCTUnwrap(world.passengers.firstIndex { $0.station == Self.c })
        world.passengers[record].release(100, to: Self.b, along: PassengerTrip(line: line, direction: .outbound), at: .zero)
        try world.advance(ticks: 4)
        XCTAssertEqual(world.riderCount(of: through), 100)
        let before = world.accounts.pending
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: through)?.execution, .waitingAtStop(3))
        XCTAssertEqual(world.riderCount(of: through), 0)
        XCTAssertEqual(world.passengerLedger(of: Self.c).abandoned, 100)
        XCTAssertEqual(world.stationFlow(Self.a, onDay: 0)?.alighted, 100)
        let after = world.accounts.pending
        XCTAssertEqual(after.departures, before.departures)
        XCTAssertEqual(after.trainDistance, before.trainDistance)
        XCTAssertEqual(after.passengers, before.passengers)
        XCTAssertEqual(after.seats, before.seats)
        let times = try XCTUnwrap(world.train(id: through)?.times)
        let seconds = try XCTUnwrap(world.train(id: through)).exchangeSeconds(100, crowd: 0)
        XCTAssertGreaterThan(seconds, 0)
        XCTAssertEqual(times.exchangeEnd, GameTime(seconds: times.arrival.seconds + ServiceDwell.doorOpening + seconds))
        XCTAssertNil(WorldInvariants.roundTripProblem(of: world))
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// Decision 288 (TestFlight 74.1): the calls left out take no time. As
    /// it turns at A, the rest of its trip comes forward to now, each call
    /// keeping its dwell, and it leaves A for C after its usual dwell, not
    /// at the time it would have come back from B. The calls before the
    /// turn keep their times; B, left out, is due as it turns.
    func testATrainTurnedShortLeavesAfterItsDwellNotWhenItWouldHaveComeBack() throws {
        var (world, _, through) = try world()
        try world.advance(ticks: 4)
        let planned = try XCTUnwrap(world.train(id: through)?.timetable)
        XCTAssertEqual(planned.map(\.station), [Self.c, Self.a, Self.b, Self.a, Self.c])
        // The turn comes in the step from minute 4 to 5.
        let turnedAt = world.clock.now
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: through)?.execution, .waitingAtStop(3))
        let turned = try XCTUnwrap(world.train(id: through)?.timetable)
        let early = planned[3].arrival.seconds - turnedAt.seconds
        XCTAssertGreaterThan(early, 0, "it would have come back from B later")
        XCTAssertEqual(Array(turned.prefix(2)), Array(planned.prefix(2)), "the calls made keep their times")
        XCTAssertEqual(turned[2], ScheduledStop(station: Self.b, arrival: turnedAt, departure: turnedAt, reverses: true), "B, left out, is due as it turns")
        for index in 3..<planned.count {
            XCTAssertEqual(turned[index].station, planned[index].station)
            XCTAssertEqual(turned[index].reverses, planned[index].reverses)
            XCTAssertEqual(turned[index].arrival.seconds, planned[index].arrival.seconds - early)
            XCTAssertEqual(turned[index].departure.seconds, planned[index].departure.seconds - early)
        }
        XCTAssertEqual(turned[3].arrival, turnedAt, "due back at A as it turns")
        // A minute on it has left A for C, where it would still have stood
        // until the time it would have come back from B.
        try world.advance(ticks: 1)
        XCTAssertGreaterThan(planned[3].departure.seconds, world.clock.now.seconds)
        XCTAssertNotEqual(world.train(id: through)?.execution, .waitingAtStop(3), "gone from A")
        XCTAssertNil(WorldInvariants.roundTripProblem(of: world))
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// Decision 288, a later fix (Codex's review of #823, R2): a save made
    /// in any second after the turn loads again. The doors open as at any
    /// arrival, so in the seconds before they have opened no exchange has
    /// started (a save checks that one never starts before the doors open).
    func testASaveInTheSecondsAfterATurnLoadsAgain() throws {
        var (world, _, through) = try world()
        world.setSpeed(.x10)
        for _ in 0..<600 {
            try world.advance(ticks: 1)
            if case .waitingAtStop(3, _)? = world.train(id: through)?.execution { break }
        }
        XCTAssertEqual(world.train(id: through)?.execution, .waitingAtStop(3))
        let turned = try XCTUnwrap(world.train(id: through)?.times?.arrival)
        for seconds in [1, 7, 8, 9, 30] {
            var probe = world
            try probe.advance(ticks: Int(turned.seconds) + seconds - Int(probe.clock.now.seconds))
            XCTAssertEqual(probe.clock.now.seconds, turned.seconds + Int64(seconds))
            let data = try JSONEncoder().encode(SavedGame(world: probe))
            let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
            XCTAssertTrue(loaded == probe, "\(seconds) s after the turn")
            XCTAssertNil(WorldInvariants.roundTripProblem(of: probe), "\(seconds) s after the turn")
        }
        // The riders change in the step at which the doors have opened, as
        // at any call.
        var opened = world
        try opened.advance(ticks: Int(turned.seconds) + Int(ServiceDwell.doorOpening) - Int(opened.clock.now.seconds))
        XCTAssertNil(opened.train(id: through)?.times?.exchangeEnd, "not before the doors open")
        try opened.advance(ticks: 1)
        XCTAssertNotNil(opened.train(id: through)?.times?.exchangeEnd)
    }

    /// Decision 288, a later fix (R1): the trip log's scheduled arrival
    /// comes forward with the timetable, so a trip turned short and then
    /// held is late both in the log and in its line's punctuality.
    func testATripTurnedShortIsLateByTheTimesItsLineCounts() throws {
        var (world, _, through) = try world()
        world.setEconomyMode(.management)
        world.setLineAccounts(true)
        world.setRealisticOperation(true)
        let line = try XCTUnwrap(world.assignedLine(of: through))
        var planned: [ScheduledStop] = []
        for _ in 0..<60 {
            if let train = world.train(id: through), !train.timetable.isEmpty, planned.isEmpty { planned = train.timetable }
            try world.advance(ticks: 1)
            if case .waitingAtStop(3, _)? = world.train(id: through)?.execution { break }
        }
        let turned = try XCTUnwrap(world.train(id: through))
        XCTAssertEqual(turned.execution, .waitingAtStop(3))
        XCTAssertNotEqual(turned.timetable, planned, "the timetable came forward")
        XCTAssertEqual(world.trips(of: through).first?.scheduledArrival, turned.timetable.last?.arrival)
        // Held past the new arrival by more than the punctual margin, it
        // arrives late by both counts; a save on the way changes nothing.
        var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertTrue(loaded == world)
        try world.setTrainMovementRate(through, to: 0)
        try loaded.setTrainMovementRate(through, to: 0)
        let release = try XCTUnwrap(turned.timetable.last?.arrival.seconds) + 300
        while world.clock.now.seconds < release {
            try world.advance(ticks: 1)
            try loaded.advance(ticks: 1)
        }
        try world.setTrainMovementRate(through, to: 1_024)
        try loaded.setTrainMovementRate(through, to: 1_024)
        for _ in 0..<10 where world.trips(of: through).first?.arrival == nil {
            try world.advance(ticks: 1)
            try loaded.advance(ticks: 1)
        }
        XCTAssertTrue(loaded == world)
        let trip = try XCTUnwrap(world.trips(of: through).first)
        XCTAssertNotNil(trip.arrival)
        XCTAssertEqual(trip.isLate, true)
        let tally = world.lineDays(line).map(\.tally) + [world.lineAccounts?.records(of: line)?.pending ?? LineTally()]
        XCTAssertEqual(tally.reduce(0) { $0 + $1.lateTrips }, 1, "the line counts it late too")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }
}
