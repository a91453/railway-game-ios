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
}
