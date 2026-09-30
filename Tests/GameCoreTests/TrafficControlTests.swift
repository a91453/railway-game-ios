import Foundation
import GameCore
import XCTest

/// Route reservation under traffic control (Phase 4.6 Stage T, ARCHITECTURE
/// decision 32): turning traffic control on and off, what a route
/// reserves on the grid and on the track network (spans, partial edges,
/// where a path ends, long trains, curves, levels and platforms), junctions
/// and fouling, refused commands and infrastructure changes, services and
/// lines that wait for their routes, and saves.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run. Span boundaries follow S3A: an edge `L`
/// long is cut into `n = ⌈L ÷ 1024⌉` parts at `⌊k × L ÷ n⌋`, and again at
/// its platforms' ends.
final class TrafficControlTests: XCTestCase {
    private func p(_ x: Int, _ y: Int) -> GridPosition {
        GridPosition(x: x, y: y)
    }

    private func tile(_ x: Int, _ y: Int) -> TrackResource {
        .tile(p(x, y))
    }

    private func link(_ a: (Int, Int), _ b: (Int, Int)) -> TrackResource {
        .link(between: p(a.0, a.1), and: p(b.0, b.1))
    }

    private func node(_ number: Int) -> TrackResource {
        .node(.node(number))
    }

    private func span(_ edge: Int, _ start: Int64, _ end: Int64) -> TrackResource {
        .span(TrackSpan(edge: .edge(edge), start: start, end: end))
    }

    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    private func buy(_ world: inout GameWorld, cars: Int = 1) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T\(world.trains.count + 1)").id
        try world.setTrainCars(id, to: cars)
        return id
    }

    /// Places a train on the network and stops it where it is placed (a
    /// path ending at its head; none at the end of an edge).
    private func stand(_ world: inout GameWorld, cars: Int = 1, at traversal: TrackTraversal, _ offset: Int64) throws -> TrainID {
        let id = try buy(&world, cars: cars)
        try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
        let length = try XCTUnwrap(world.trackEdge(traversal.edge)?.length)
        try world.setTrainContinuation(id, along: [], stoppingAt: offset < length ? offset : nil)
        return id
    }

    // MARK: - The grid line
    //
    //   row 0:  .  A  .  .  .  .  B  .
    //   row 1:  o - o - o - o - o - o - o - o     dead ends at (0,1) and (7,1)
    //
    // A's platform is (1,1), B's is (6,1).

    private func makeGridWorld() throws -> (world: GameWorld, a: StationID, b: StationID) {
        var world = try GameWorld(
            width: 8, height: 3, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal)
        )
        try world.buildTrack(at: p(0, 1), connections: .east)
        for x in 1...6 {
            try world.buildTrack(at: p(x, 1), connections: [.east, .west])
        }
        try world.buildTrack(at: p(7, 1), connections: .west)
        let a = try world.buildStation(named: "A", at: p(1, 0)).id
        let b = try world.buildStation(named: "B", at: p(6, 0)).id
        return (world, a, b)
    }

    private func place(_ world: inout GameWorld, at position: TrainPosition, cars: Int = 1) throws -> TrainID {
        let id = try buy(&world, cars: cars)
        try world.placeTrain(id, at: position)
        return id
    }

    /// Off (the default): trains stand on the same track and pass through
    /// each other as in Stage S5; nothing is reserved or saved.
    func testWithoutTrafficControlTrainsShareTrackAsBefore() throws {
        var (world, _, _) = try makeGridWorld()
        XCTAssertFalse(world.isTrafficControlEnabled)
        let one = try place(&world, at: .atNode(p(2, 1), heading: .east))
        let two = try place(&world, at: .atNode(p(2, 1), heading: .west))
        try world.setTrainContinuation(one, to: [p(3, 1), p(4, 1)])
        try world.setTrainContinuation(two, to: [p(1, 1)])
        XCTAssertEqual(world.occupancyConflicts(), [TrackConflict(resource: tile(2, 1), trains: [one, two])])
        XCTAssertEqual(world.reservedResources(of: one), [])
        XCTAssertEqual(world.heldResources(of: one), [tile(2, 1)])
        XCTAssertNil(world.trainHoldingRoute(of: one))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNil(json["trafficControl"])
        let trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        XCTAssertTrue(trains.allSatisfy { $0["reservation"] == nil })
    }

    /// On: every train with a way to go takes all of it at once; off drops
    /// every reservation and changes nothing else; on twice is on.
    func testTurningTrafficControlOnAndOff() throws {
        var (world, _, _) = try makeGridWorld()
        let one = try place(&world, at: .atNode(p(2, 1), heading: .east))
        try world.setTrainContinuation(one, to: [p(3, 1), p(4, 1)])
        let two = try place(&world, at: .atNode(p(5, 1), heading: .west))
        let off = world

        try world.setTrafficControl(true)
        XCTAssertTrue(world.isTrafficControlEnabled)
        // Its tile, the two links it runs along and the tiles they lead to.
        let route = [tile(2, 1), tile(3, 1), tile(4, 1), link((2, 1), (3, 1)), link((3, 1), (4, 1))]
        XCTAssertEqual(world.reservedResources(of: one), route)
        XCTAssertEqual(world.train(id: one)?.reservation, route)
        XCTAssertEqual(world.heldResources(of: one), route)
        // Standing: it holds its tile and reserves nothing.
        XCTAssertEqual(world.reservedResources(of: two), [])
        XCTAssertEqual(world.heldResources(of: two), [tile(5, 1)])
        let on = world
        try world.setTrafficControl(true)
        XCTAssertEqual(world, on)

        try world.setTrafficControl(false)
        XCTAssertEqual(world, off)
        XCTAssertEqual(world.reservedResources(of: one), [])
    }

    /// On is refused, with nothing changed, while two trains stand on the
    /// same track: the first train to share with an earlier one, and the
    /// earliest it shares with.
    func testTrafficControlCannotBeTurnedOnOverSharedTrack() throws {
        var (world, _, _) = try makeGridWorld()
        _ = try place(&world, at: .atNode(p(1, 1), heading: .east))
        let two = try place(&world, at: .atNode(p(5, 1), heading: .east))
        let three = try place(&world, at: .atNode(p(5, 1), heading: .west))
        let before = world
        XCTAssertThrowsGameError(try world.setTrafficControl(true), .trainsShareTrack(two, three))
        XCTAssertEqual(world, before)
    }

    /// ... and while a train's way ahead meets another train, even one that
    /// only stands there. A way that stops short of it is fine.
    func testTrafficControlCannotBeTurnedOnOverMeetingRoutes() throws {
        var (world, _, _) = try makeGridWorld()
        let one = try place(&world, at: .atNode(p(4, 1), heading: .west))
        let two = try place(&world, at: .atNode(p(1, 1), heading: .east))
        try world.setTrainContinuation(two, to: [p(2, 1), p(3, 1), p(4, 1)])
        let before = world
        XCTAssertThrowsGameError(try world.setTrafficControl(true), .trainsShareTrack(one, two))
        XCTAssertEqual(world, before)
        XCTAssertTrue(world.reservedResources(of: two).isEmpty)

        try world.setTrainContinuation(two, to: [p(2, 1), p(3, 1)])
        try world.setTrafficControl(true)
        XCTAssertEqual(world.reservedResources(of: two), [tile(1, 1), tile(2, 1), tile(3, 1), link((1, 1), (2, 1)), link((2, 1), (3, 1))])
    }

    /// Under traffic control a route is taken whole or not at all; placing,
    /// sending and removing track another train holds are refused with that
    /// train named; the reservation stays for the whole trip and ends with
    /// it, after which the train's tile still protects it.
    func testGridRoutesAreTakenWholeAndKeptForTheTrip() throws {
        var (world, _, _) = try makeGridWorld()
        try world.setTrafficControl(true)
        let one = try place(&world, at: .atNode(p(2, 1), heading: .east))
        XCTAssertEqual(world.reservedResources(of: one), [])
        try world.setTrainContinuation(one, to: [p(3, 1), p(4, 1)])
        let route = [tile(2, 1), tile(3, 1), tile(4, 1), link((2, 1), (3, 1)), link((3, 1), (4, 1))]
        XCTAssertEqual(world.reservedResources(of: one), route)

        let two = try buy(&world)
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .atNode(p(4, 1), heading: .west)), .trackReserved(one))
        // On the link from (5,1) to (4,1) it would run on to (4,1).
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .onLink(from: p(5, 1), to: p(4, 1), offset: 512)), .trackReserved(one))
        try world.placeTrain(two, at: .atNode(p(5, 1), heading: .west))
        var before = world
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(4, 1)]), .trackReserved(one))
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, along: [.link(from: p(5, 1), to: p(4, 1))]), .trackReserved(one))
        XCTAssertThrowsGameError(try world.removeTrack(at: p(4, 1)), .trackReserved(one))
        XCTAssertThrowsGameError(try world.removeTrack(at: p(3, 1)), .trackReserved(one))
        // Physical use comes first, as before traffic control.
        XCTAssertThrowsGameError(try world.removeTrack(at: p(5, 1)), .trackInUse(p(5, 1)))
        XCTAssertEqual(world, before)
        try world.removeTrack(at: p(7, 1))

        // Rate 0 and a new rate keep the reservation.
        try world.setTrainMovementRate(one, to: 0)
        XCTAssertEqual(world.reservedResources(of: one), route)
        try world.setTrainMovementRate(one, to: 1_024)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(3, 1), heading: .east))
        // Not released behind the train: (2,1) is still its.
        XCTAssertEqual(world.reservedResources(of: one), route)
        before = world
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(4, 1)]), .trackReserved(one))
        XCTAssertEqual(world, before)

        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(4, 1), heading: .east))
        XCTAssertEqual(world.reservedResources(of: one), [])
        XCTAssertEqual(world.heldResources(of: one), [tile(4, 1)])
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(4, 1)]), .trackReserved(one))
        try world.removeTrack(at: p(2, 1))
    }

    /// A train on a link runs to its end by itself, so placing it there,
    /// or turning it round there, takes that end too; one turned round at a
    /// node stands.
    func testALinkRunsOnToItsEnd() throws {
        var (world, _, _) = try makeGridWorld()
        try world.setTrafficControl(true)
        let one = try place(&world, at: .onLink(from: p(6, 1), to: p(5, 1), offset: 256))
        XCTAssertEqual(world.reservedResources(of: one), [tile(5, 1), link((5, 1), (6, 1))])
        let two = try place(&world, at: .atNode(p(6, 1), heading: .east))
        let before = world
        XCTAssertThrowsGameError(try world.reverseTrain(one), .trackReserved(two))
        XCTAssertEqual(world, before)

        try world.unplaceTrain(two)
        XCTAssertEqual(world.reservedResources(of: two), [])
        try world.reverseTrain(one)
        XCTAssertEqual(world.train(id: one)?.position, .onLink(from: p(5, 1), to: p(6, 1), offset: 768))
        XCTAssertEqual(world.reservedResources(of: one), [tile(6, 1), link((5, 1), (6, 1))])

        let three = try place(&world, at: .atNode(p(2, 1), heading: .east))
        try world.setTrainContinuation(three, to: [p(3, 1)])
        try world.reverseTrain(three)
        XCTAssertEqual(world.train(id: three)?.position, .atNode(p(2, 1), heading: .west))
        XCTAssertEqual(world.reservedResources(of: three), [])
        XCTAssertEqual(world.heldResources(of: three), [tile(2, 1)])
    }

    /// A train of three cars holds its whole body and reserves everything
    /// its whole length covers, kept until the trip ends.
    func testALongGridTrainReservesItsWholeLength() throws {
        var (world, _, _) = try makeGridWorld()
        try world.setTrafficControl(true)
        let one = try place(&world, at: .atNode(p(4, 1), heading: .east), cars: 3)
        XCTAssertEqual(world.train(id: one)?.trail, [p(3, 1), p(2, 1)])
        let body = [tile(2, 1), tile(3, 1), tile(4, 1), link((2, 1), (3, 1)), link((3, 1), (4, 1))]
        XCTAssertEqual(world.heldResources(of: one), body)
        XCTAssertEqual(world.reservedResources(of: one), [])
        try world.setTrainContinuation(one, to: [p(5, 1), p(6, 1)])
        XCTAssertEqual(world.reservedResources(of: one), [
            tile(2, 1), tile(3, 1), tile(4, 1), tile(5, 1), tile(6, 1),
            link((2, 1), (3, 1)), link((3, 1), (4, 1)), link((4, 1), (5, 1)), link((5, 1), (6, 1)),
        ])
        let two = try place(&world, at: .atNode(p(1, 1), heading: .east))
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(2, 1)]), .trackReserved(one))

        try world.setTrainMovementRate(one, to: 1_024)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.trail, [p(4, 1), p(3, 1)])
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(2, 1)]), .trackReserved(one))
        try world.advance(ticks: 1)
        XCTAssertEqual(world.reservedResources(of: one), [])
        XCTAssertEqual(world.heldResources(of: one), [tile(4, 1), tile(5, 1), tile(6, 1), link((4, 1), (5, 1)), link((5, 1), (6, 1))])
        try world.setTrainContinuation(two, to: [p(2, 1), p(3, 1)])
        XCTAssertEqual(world.reservedResources(of: two), [tile(1, 1), tile(2, 1), tile(3, 1), link((1, 1), (2, 1)), link((2, 1), (3, 1))])
    }

    /// A train following another the same way waits until the first has
    /// finished its whole route: Stage T releases nothing behind a train.
    func testAFollowerWaitsForTheWholeRouteAhead() throws {
        var (world, _, _) = try makeGridWorld()
        try world.setTrafficControl(true)
        let one = try place(&world, at: .atNode(p(1, 1), heading: .east))
        try world.setTrainContinuation(one, to: [p(2, 1), p(3, 1), p(4, 1), p(5, 1), p(6, 1)])
        try world.setTrainMovementRate(one, to: 1_024)
        let two = try place(&world, at: .atNode(p(0, 1), heading: .east))
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(1, 1)]), .trackReserved(one))
        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(4, 1), heading: .east))
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(1, 1)]), .trackReserved(one))
        try world.advance(ticks: 2)
        XCTAssertEqual(world.reservedResources(of: one), [])
        try world.setTrainContinuation(two, to: [p(1, 1), p(2, 1), p(3, 1), p(4, 1), p(5, 1)])
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(1, 1), p(2, 1), p(3, 1), p(4, 1), p(5, 1), p(6, 1)]), .trackReserved(one))
    }

    /// A level crossing and a turnout are one tile: routes across or
    /// through them meet there.
    func testGridCrossingsAndTurnoutsAreOneTile() throws {
        var world = try GameWorld(width: 5, height: 5, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try world.buildTrack(at: p(0, 2), connections: .east)
        try world.buildTrack(at: p(1, 2), connections: [.east, .west])
        try world.buildCrossing(at: p(2, 2))
        try world.buildTrack(at: p(3, 2), connections: [.east, .west])
        try world.buildTrack(at: p(4, 2), connections: .west)
        try world.buildTrack(at: p(2, 0), connections: .south)
        try world.buildTrack(at: p(2, 1), connections: [.north, .south])
        try world.buildTrack(at: p(2, 3), connections: [.north, .south])
        try world.buildTrack(at: p(2, 4), connections: .north)
        try world.setTrafficControl(true)
        let one = try place(&world, at: .atNode(p(1, 2), heading: .east))
        try world.setTrainContinuation(one, to: [p(2, 2), p(3, 2)])
        let two = try place(&world, at: .atNode(p(2, 1), heading: .south))
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(2, 2), p(2, 3)]), .trackReserved(one))

        // A turnout: stem west, branches east and south.
        var turnout = try GameWorld(width: 5, height: 5, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try turnout.buildTrack(at: p(0, 2), connections: .east)
        try turnout.buildTrack(at: p(1, 2), connections: [.east, .west])
        try turnout.buildTurnout(at: p(2, 2), connections: [.west, .east, .south], stem: .west)
        try turnout.buildTrack(at: p(3, 2), connections: [.east, .west])
        try turnout.buildTrack(at: p(4, 2), connections: .west)
        try turnout.buildTrack(at: p(2, 3), connections: [.north, .south])
        try turnout.buildTrack(at: p(2, 4), connections: .north)
        try turnout.setTrafficControl(true)
        let east = try place(&turnout, at: .atNode(p(3, 2), heading: .west))
        try turnout.setTrainContinuation(east, to: [p(2, 2), p(1, 2)])
        let south = try place(&turnout, at: .atNode(p(2, 4), heading: .north))
        // Its route ends on the turnout: the tile is all the two share.
        XCTAssertThrowsGameError(try turnout.setTrainContinuation(south, to: [p(2, 3), p(2, 2)]), .trackReserved(east))
        try turnout.setTrainContinuation(south, to: [p(2, 3)])
        XCTAssertEqual(turnout.reservedResources(of: south), [tile(2, 3), tile(2, 4), link((2, 3), (2, 4))])
    }

    /// A service due to leave takes its whole route to the next stop, or
    /// waits at its stop and tries again at every step; the train holding
    /// the route is reported. Stopping the service keeps the reservation.
    func testAServiceWaitsForItsRoute() throws {
        var (world, a, b) = try makeGridWorld()
        try world.setTrafficControl(true)
        let one = try place(&world, at: .atNode(p(1, 1), heading: .east))
        try world.setTrainMovementRate(one, to: 1_024)
        try world.setTrainTimetable(one, to: [
            ScheduledStop(station: a, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: b, arrival: GameTime(minutes: 10), departure: GameTime(minutes: 10)),
        ])
        try world.startTrainService(one)
        let blocker = try place(&world, at: .atNode(p(4, 1), heading: .west))
        // Not yet due.
        XCTAssertNil(world.trainHoldingRoute(of: one))

        try world.advance(ticks: 3)
        XCTAssertEqual(world.clock.now.minutes, 3)
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(0, cycle: 0))
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(1, 1), heading: .east))
        XCTAssertEqual(world.reservedResources(of: one), [])
        XCTAssertEqual(world.trainHoldingRoute(of: one), blocker)
        XCTAssertNil(world.trainHoldingRoute(of: blocker))

        try world.unplaceTrain(blocker)
        XCTAssertNil(world.trainHoldingRoute(of: one))
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(2, 1), heading: .east))
        let route = [
            tile(1, 1), tile(2, 1), tile(3, 1), tile(4, 1), tile(5, 1), tile(6, 1),
            link((1, 1), (2, 1)), link((2, 1), (3, 1)), link((3, 1), (4, 1)), link((4, 1), (5, 1)), link((5, 1), (6, 1)),
        ]
        XCTAssertEqual(world.reservedResources(of: one), route)
        try world.stopTrainService(one)
        XCTAssertEqual(world.reservedResources(of: one), route)
        try world.advance(ticks: 4)
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(6, 1), heading: .east))
        XCTAssertEqual(world.reservedResources(of: one), [])
    }

    /// A stop marked to turn round turns the train only if the route from
    /// there can be taken: a refused departure leaves it as it was.
    func testARefusedDepartureDoesNotTurnTheTrainRound() throws {
        var (world, a, b) = try makeGridWorld()
        let one = try place(&world, at: .atNode(p(6, 1), heading: .east))
        try world.setTrainMovementRate(one, to: 1_024)
        try world.setTrainTimetable(one, to: [
            ScheduledStop(station: b, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1), reverses: true),
            ScheduledStop(station: a, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
        ])
        try world.startTrainService(one)
        let blocker = try place(&world, at: .atNode(p(3, 1), heading: .east))
        try world.setTrafficControl(true)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(6, 1), heading: .east))
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(0, cycle: 0))
        XCTAssertEqual(world.trainHoldingRoute(of: one), blocker)

        try world.unplaceTrain(blocker)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(5, 1), heading: .west))
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1, cycle: 0))
    }

    /// A line does not send out a train whose first route is held: no
    /// timetable, no service, no dispatch recorded; it goes at the first
    /// step the route is free.
    func testALineWaitsToSendATrainOut() throws {
        var (world, a, b) = try makeGridWorld()
        let one = try place(&world, at: .atNode(p(1, 1), heading: .east))
        try world.setTrainMovementRate(one, to: 1_024)
        let line = try world.createLine(named: "L", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(one, to: line)
        let blocker = try place(&world, at: .atNode(p(4, 1), heading: .west))
        try world.setTrafficControl(true)
        // The plan does not see the blocker.
        XCTAssertEqual(world.lineJourney(line)?.roundTripMinutes, 14)
        XCTAssertEqual(world.trainHoldingRoute(of: one), blocker)

        try world.advance(ticks: 2)
        XCTAssertNil(world.line(id: line)?.lastDispatch)
        XCTAssertNil(world.train(id: one)?.execution)
        XCTAssertEqual(world.train(id: one)?.timetable, [])
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(1, 1), heading: .east))

        try world.unplaceTrain(blocker)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.line(id: line)?.lastDispatch, GameTime(minutes: 2))
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(2, 1), heading: .east))
        XCTAssertNil(world.trainHoldingRoute(of: one))
    }

    /// A train already waiting for removed track when traffic control is
    /// turned on reserves the gap too, so it can go on once it is rebuilt.
    func testATrainWaitingForRemovedTrackKeepsItsWayThroughTheGap() throws {
        var (world, _, _) = try makeGridWorld()
        let one = try place(&world, at: .atNode(p(1, 1), heading: .east))
        try world.setTrainContinuation(one, to: [p(2, 1), p(3, 1), p(4, 1)])
        try world.setTrainMovementRate(one, to: 1_024)
        try world.removeTrack(at: p(3, 1))
        try world.setTrafficControl(true)
        XCTAssertEqual(world.reservedResources(of: one), [
            tile(1, 1), tile(2, 1), tile(3, 1), tile(4, 1), link((1, 1), (2, 1)), link((2, 1), (3, 1)), link((3, 1), (4, 1)),
        ])
        XCTAssertNil(WorldInvariants.roundTripProblem(of: world))
        let two = try buy(&world)
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .atNode(p(4, 1), heading: .west)), .trackReserved(one))

        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(2, 1), heading: .east))
        XCTAssertEqual(world.reservedResources(of: one).count, 7)
        try world.buildTrack(at: p(3, 1), connections: [.east, .west])
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(4, 1), heading: .east))
        XCTAssertEqual(world.reservedResources(of: one), [])
    }

    // MARK: - The straight network
    //
    //   n1 ──e1── n2 ──e2── n3     y = 1024, on the surface
    //
    // e1 is 5120 long: five spans of 1024. e2 is 3000 long: three spans cut
    // at 1000 and 2000. n2 is plain track, n1 and n3 dead ends.

    private func makeLineWorld() throws -> GameWorld {
        var world = try GameWorld(width: 12, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 1_024))
        let n2 = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 1_024))
        let n3 = try world.buildTrackNode(at: WorldCoordinate(x: 9_144, y: 1_024))
        try world.buildTrackEdge(from: n1, to: n2)
        try world.buildTrackEdge(from: n2, to: n3)
        return world
    }

    /// Trains on one long edge take only the spans they need; spans another
    /// train holds are refused. A train placed part of the way along an
    /// edge runs on to its end by itself, and takes that.
    func testTrainsReserveTheSpansOfAnEdgeTheyNeed() throws {
        var world = try makeLineWorld()
        XCTAssertEqual(world.trackSpans(of: .edge(2)).map(\.end), [1_000, 2_000, 3_000])
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 500))
        XCTAssertEqual(world.reservedResources(of: one), [
            node(2), span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120),
        ])
        try world.setTrainContinuation(one, along: [], stoppingAt: 1_500)
        XCTAssertEqual(world.reservedResources(of: one), [span(1, 0, 1_024), span(1, 1_024, 2_048)])

        let two = try buy(&world)
        try world.placeTrain(two, at: .onEdge(forward(1), offset: 3_000))
        try world.setTrainContinuation(two, along: [], stoppingAt: 4_000)
        XCTAssertEqual(world.reservedResources(of: two), [span(1, 2_048, 3_072), span(1, 3_072, 4_096)])

        let three = try buy(&world)
        let before = world
        XCTAssertThrowsGameError(try world.placeTrain(three, at: .onEdge(forward(1), offset: 1_800)), .trackReserved(one))
        XCTAssertEqual(world, before)
        try world.placeTrain(three, at: .onEdge(forward(2), offset: 100))
        XCTAssertEqual(world.reservedResources(of: three), [node(3), span(2, 0, 1_000), span(2, 1_000, 2_000), span(2, 2_000, 3_000)])
    }

    /// The rest of the train's edge, the edges between whole, the last up
    /// to where the path stops; held for the trip and released when the
    /// head gets there.
    func testAPathTakesPartsOfItsFirstAndLastEdges() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        let route = [node(2), span(1, 4_096, 5_120), span(2, 0, 1_000), span(2, 1_000, 2_000)]
        XCTAssertEqual(world.reservedResources(of: one), route)
        try world.setTrainMovementRate(one, to: 1_024)
        // 520 to n2, then 504 along e2.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 504))
        XCTAssertEqual(world.reservedResources(of: one), route)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 1_500))
        XCTAssertEqual(world.reservedResources(of: one), [])
        XCTAssertEqual(world.heldResources(of: one), [span(2, 1_000, 2_000)])
    }

    /// A path that stops on a span boundary takes the spans on both sides,
    /// as a train standing there holds both: nothing is left for another
    /// train to slip into.
    func testAPathEndingOnABoundaryTakesBothSides() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 1_000))
        try world.setTrainContinuation(one, along: [], stoppingAt: 2_048)
        XCTAssertEqual(world.reservedResources(of: one), [span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072)])
        try world.setTrainMovementRate(one, to: 1_024)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(1), offset: 2_048))
        XCTAssertEqual(world.heldResources(of: one), [span(1, 1_024, 2_048), span(1, 2_048, 3_072)])
        let two = try buy(&world)
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .onEdge(forward(1), offset: 2_500)), .trackReserved(one))
    }

    /// A long train reserves from its tail: its body's spans are part of
    /// its route.
    func testALongNetworkTrainReservesFromItsTail() throws {
        var world = try makeLineWorld()
        try world.setTrafficControl(true)
        // Three cars, 2048 long, head at 3000: the body covers 952 to 3000.
        let one = try buy(&world, cars: 3)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 3_000))
        try world.setTrainContinuation(one, along: [], stoppingAt: 4_500)
        let all = [span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120)]
        XCTAssertEqual(world.reservedResources(of: one), all)
        XCTAssertEqual(world.occupiedResources(of: one), Array(all.prefix(3)))
        // Backward from 4700 is chainage 420; placed there a train runs on
        // to n1, over span 0–1024, which holds the long train's tail.
        let two = try buy(&world)
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .onEdge(backward(1), offset: 4_700)), .trackReserved(one))
    }

    // MARK: - Curves, levels and an underground platform
    //
    // - e1: the quarter curve of network-service.json, (12288, 4096) to
    //   (16384, 8192), 6346 long: seven spans cut at ⌊k × 6346 ÷ 7⌋ = 906,
    //   1813, 2719, 3626, 4532, 5439.
    // - e2: a viaduct 512 up from (2048, 12288) to (10240, 12288), 8192.
    // - e3: a tunnel 512 down from (2048, 16384) to (10240, 16384), 8192,
    //   with Deep's platform from 1500 to 5596: its spans are the eight of
    //   1024 cut again at 1500 and 5596.

    private func makeLevelsWorld() throws -> (world: GameWorld, deep: StationID) {
        var world = try GameWorld(width: 20, height: 20, economy: GameEconomy(balance: 10_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let c1 = try world.buildTrackNode(at: WorldCoordinate(x: 12_288, y: 4_096))
        let c2 = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        try world.buildTrackEdge(from: c1, to: c2, curve: .cubic(PlanPoint(x: 14_336, y: 4_096), PlanPoint(x: 16_384, y: 6_144)))
        let v1 = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 12_288, z: 512))
        let v2 = try world.buildTrackNode(at: WorldCoordinate(x: 10_240, y: 12_288, z: 512))
        try world.buildTrackEdge(from: v1, to: v2, structure: .elevated)
        let t1 = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 16_384, z: -512))
        let t2 = try world.buildTrackNode(at: WorldCoordinate(x: 10_240, y: 16_384, z: -512))
        try world.buildTrackEdge(from: t1, to: t2, structure: .tunnel)
        let deep = try world.buildStation(named: "Deep", at: p(1, 1)).id
        try world.addTrackPlatform(deep, on: .edge(3), from: 1_500, to: 5_596)
        return (world, deep)
    }

    /// Curves and levels change nothing: only the integer chainage counts.
    func testCurvedElevatedAndUndergroundTrackReserveBySpan() throws {
        var (world, deep) = try makeLevelsWorld()
        XCTAssertEqual(world.trackEdge(.edge(1))?.length, 6_346)
        try world.setTrafficControl(true)
        let curve = try buy(&world)
        try world.placeTrain(curve, at: .onEdge(forward(1), offset: 1_000))
        try world.setTrainContinuation(curve, along: [], stoppingAt: 3_000)
        XCTAssertEqual(world.reservedResources(of: curve), [span(1, 906, 1_813), span(1, 1_813, 2_719), span(1, 2_719, 3_626)])

        let viaduct = try buy(&world)
        try world.placeTrain(viaduct, at: .onEdge(forward(2), offset: 100))
        try world.setTrainContinuation(viaduct, along: [], stoppingAt: 2_000)
        XCTAssertEqual(world.reservedResources(of: viaduct), [span(2, 0, 1_024), span(2, 1_024, 2_048)])

        // Three cars into the tunnel to Deep's forward berth, 5596, its body
        // from 952: the spans from 0 to the berth, and the one beyond it
        // that the head touches there.
        let mole = try buy(&world, cars: 3)
        try world.placeTrain(mole, at: .onEdge(forward(3), offset: 3_000))
        let path = try XCTUnwrap(world.path(from: .onEdge(forward(3), offset: 3_000), toStation: deep, length: 2_048))
        XCTAssertEqual(path, TrainPath(traversals: [], end: 5_596, distance: 2_596))
        try world.setTrainContinuation(mole, along: path.traversals, stoppingAt: path.end)
        XCTAssertEqual(world.reservedResources(of: mole), [
            span(3, 0, 1_024), span(3, 1_024, 1_500), span(3, 1_500, 2_048), span(3, 2_048, 3_072),
            span(3, 3_072, 4_096), span(3, 4_096, 5_120), span(3, 5_120, 5_596), span(3, 5_596, 6_144),
        ])
        try world.setTrainMovementRate(mole, to: 2_048)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.stationsBesideWholeTrain(mole), [deep])
        XCTAssertEqual(world.reservedResources(of: mole), [])
        XCTAssertEqual(world.heldResources(of: mole), [span(3, 3_072, 4_096), span(3, 4_096, 5_120), span(3, 5_120, 5_596), span(3, 5_596, 6_144)])
    }

    /// The backward berth of an underground platform: the head stops at
    /// its start, 8192 − 1500 = 6692 along the way it runs.
    func testABackwardBerthIsReservedToThePlatformsStart() throws {
        var (world, deep) = try makeLevelsWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(backward(3), offset: 100))
        let path = try XCTUnwrap(world.path(from: .onEdge(backward(3), offset: 100), toStation: deep))
        XCTAssertEqual(path, TrainPath(traversals: [], end: 6_692, distance: 6_592))
        try world.setTrainContinuation(one, along: path.traversals, stoppingAt: path.end)
        // Chainage 8092 back to 1500, touching the boundary at 1500.
        XCTAssertEqual(world.reservedResources(of: one), [
            span(3, 1_024, 1_500), span(3, 1_500, 2_048), span(3, 2_048, 3_072), span(3, 3_072, 4_096), span(3, 4_096, 5_120),
            span(3, 5_120, 5_596), span(3, 5_596, 6_144), span(3, 6_144, 7_168), span(3, 7_168, 8_192),
        ])
    }

    // MARK: - A turnout on the network
    //
    //   j0 ──s── J ──a── A      a: J (7168, 8192) east to (15360, 8192), 8192
    //             ╲
    //              b── B        b: J to (15872, 8720), 8720 (a 1088-66-1090
    //                           triangle times 8), 1 in 16.5 off a
    //
    // s (5120, five spans) arrives at J from the west; a and b both join it
    // there but not each other, so a's and b's ends at J are fouling ends
    // and s's is not. b's spans are cut at ⌊k × 8720 ÷ 9⌋: 968, 1937, ...

    private func makeJunctionWorld() throws -> GameWorld {
        var world = try GameWorld(width: 20, height: 12, economy: GameEconomy(balance: 10_000_000, costs: testCosts))
        let j0 = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 8_192))
        let junction = try world.buildTrackNode(at: WorldCoordinate(x: 7_168, y: 8_192))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 15_872, y: 8_720))
        try world.buildTrackEdge(from: j0, to: junction)
        try world.buildTrackEdge(from: junction, to: a)
        try world.buildTrackEdge(from: junction, to: b)
        return world
    }

    /// Routes onto either branch meet at the junction node.
    func testRoutesThroughATurnoutMeetAtItsNode() throws {
        var world = try makeJunctionWorld()
        XCTAssertEqual(world.transitions(after: forward(1)), [forward(2), forward(3)])
        XCTAssertEqual(world.trackEdge(.edge(3))?.length, 8_720)
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 1_000))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 2_000)
        XCTAssertEqual(world.reservedResources(of: one), [
            node(2), span(1, 0, 1_024), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120),
            span(2, 0, 1_024), span(2, 1_024, 2_048),
        ])
        // Back along b from chainage 1720 to J: alone, it takes J and two
        // spans of b, so all it shares with the first route is J.
        var alone = try makeJunctionWorld()
        try alone.setTrafficControl(true)
        let lone = try buy(&alone)
        try alone.placeTrain(lone, at: .onEdge(backward(3), offset: 7_000))
        XCTAssertEqual(alone.reservedResources(of: lone), [node(2), span(3, 0, 968), span(3, 968, 1_937)])
        let two = try buy(&world)
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .onEdge(backward(3), offset: 7_000)), .trackReserved(one))
    }

    /// A train standing on a branch within 1024 of the junction fouls it:
    /// it holds the node, and no route may pass there; one on the stem
    /// does not.
    func testATrainNearAJunctionFoulsIt() throws {
        var world = try makeJunctionWorld()
        // Placed facing the junction, a train would run on to it: these two
        // stand before traffic control is on.
        let one = try stand(&world, at: forward(1), 1_000)
        let branch = try stand(&world, at: forward(2), 300)
        try world.setTrafficControl(true)
        XCTAssertEqual(world.occupiedResources(of: branch), [span(2, 0, 1_024)])
        XCTAssertEqual(world.heldResources(of: branch), [node(2), span(2, 0, 1_024)])
        XCTAssertEqual(world.heldResources(of: one), [span(1, 0, 1_024)])
        // On the stem, 320 short of J: no fouling end there.
        var stemWorld = try makeJunctionWorld()
        let stem = try stand(&stemWorld, at: forward(1), 4_800)
        XCTAssertEqual(stemWorld.heldResources(of: stem), [span(1, 4_096, 5_120)])

        let before = world
        XCTAssertThrowsGameError(try world.setTrainContinuation(one, along: [forward(3)], stoppingAt: 4_000), .trackReserved(branch))
        XCTAssertEqual(world, before)
        // Past the zone the branch is free to share the junction.
        try world.unplaceTrain(branch)
        let far = try stand(&world, at: forward(2), 1_024)
        XCTAssertEqual(world.heldResources(of: far), [span(2, 0, 1_024), span(2, 1_024, 2_048)])
        try world.setTrainContinuation(one, along: [forward(3)], stoppingAt: 4_000)

        // Two trains within the zone on the two branches cannot both stand
        // there under traffic control.
        var both = try makeJunctionWorld()
        let first = try stand(&both, at: forward(2), 300)
        let second = try stand(&both, at: forward(3), 300)
        XCTAssertThrowsGameError(try both.setTrafficControl(true), .trainsShareTrack(first, second))
    }

    /// A new edge at a junction a train holds, or is close to, would change
    /// who fouls it: refused. Elsewhere building goes on.
    func testTrackCannotBeAddedAtAHeldJunction() throws {
        var world = try makeJunctionWorld()
        try world.setTrafficControl(true)
        let branch = try stand(&world, at: forward(2), 300)
        let spur = try world.buildTrackNode(at: WorldCoordinate(x: 7_168, y: 11_264))
        let before = world
        XCTAssertThrowsGameError(try world.buildTrackEdge(from: .node(2), to: spur), .trackReserved(branch))
        XCTAssertEqual(world, before)
        let far = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 11_264))
        try world.buildTrackEdge(from: far, to: spur)
        try world.unplaceTrain(branch)
        try world.buildTrackEdge(from: .node(2), to: spur)
    }

    // MARK: - A level crossing and a flyover on the network
    //
    // A diamond at C (6144, 8192): w (4096 long) from the west, e east, n
    // from the north, s south; w and e join, n and s join, the two lines do
    // not. A viaduct g 512 up runs north–south over e at x = 8192.

    private func makeCrossingWorld() throws -> GameWorld {
        var world = try GameWorld(width: 16, height: 16, economy: GameEconomy(balance: 10_000_000, costs: testCosts))
        let w = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 8_192))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 8_192))
        let e = try world.buildTrackNode(at: WorldCoordinate(x: 10_240, y: 8_192))
        let n = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 4_096))
        let s = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 12_288))
        try world.buildTrackEdge(from: w, to: c)
        try world.buildTrackEdge(from: c, to: e)
        try world.buildTrackEdge(from: n, to: c)
        try world.buildTrackEdge(from: c, to: s)
        let g1 = try world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: 4_096, z: 512))
        let g2 = try world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: 12_288, z: 512))
        try world.buildTrackEdge(from: g1, to: g2, structure: .elevated)
        return world
    }

    /// Both lines of a level crossing need its node; a train waiting just
    /// short of it fouls it. A flyover shares nothing with the line below.
    func testALevelCrossingIsSharedAndAFlyoverIsNot() throws {
        var world = try makeCrossingWorld()
        try world.setTrafficControl(true)
        // Each placed facing C runs on to it by itself until stopped.
        let down = try stand(&world, at: forward(3), 500)
        let across = try stand(&world, at: forward(1), 1_000)
        try world.setTrainContinuation(across, along: [forward(2)], stoppingAt: 1_000)
        XCTAssertThrowsGameError(try world.setTrainContinuation(down, along: [forward(4)], stoppingAt: 2_000), .trackReserved(across))
        try world.unplaceTrain(across)
        let waiting = try stand(&world, at: forward(1), 3_500)
        XCTAssertEqual(world.heldResources(of: waiting), [node(2), span(1, 3_072, 4_096)])
        XCTAssertThrowsGameError(try world.setTrainContinuation(down, along: [forward(4)], stoppingAt: 2_000), .trackReserved(waiting))

        var flyover = try makeCrossingWorld()
        let over = try stand(&flyover, at: forward(5), 4_096)
        let under = try stand(&flyover, at: forward(2), 2_048)
        try flyover.setTrafficControl(true)
        XCTAssertEqual(flyover.heldResources(of: over), [span(5, 3_072, 4_096), span(5, 4_096, 5_120)])
        XCTAssertEqual(flyover.heldResources(of: under), [span(2, 1_024, 2_048), span(2, 2_048, 3_072)])
    }

    // MARK: - Infrastructure

    /// Under traffic control the spans of an edge a train holds keep their
    /// meaning: no platform comes or goes there, and a reserved edge stays.
    /// Other edges change as before.
    func testHeldEdgesKeepTheirSpans() throws {
        var world = try makeLineWorld()
        let station = try world.buildStation(named: "P", at: p(1, 3)).id
        try world.addTrackPlatform(station, on: .edge(2), from: 100, to: 1_100)
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 500))
        try world.setTrainContinuation(one, along: [], stoppingAt: 1_500)
        let before = world
        XCTAssertThrowsGameError(try world.addTrackPlatform(station, on: .edge(1), from: 3_000, to: 4_000), .trackReserved(one))
        XCTAssertEqual(world, before)
        try world.removeTrackPlatform(station, on: .edge(2), from: 100)
        try world.addTrackPlatform(station, on: .edge(2), from: 2_000, to: 3_000)

        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_000)
        XCTAssertThrowsGameError(try world.removeTrackPlatform(station, on: .edge(2), from: 2_000), .trackReserved(one))
        XCTAssertThrowsGameError(try world.removeTrackEdge(.edge(2)), .trackEdgeHasPlatform(.edge(2)))
        // Standing at its end it still holds the spans it stands on.
        try world.setTrainMovementRate(one, to: 8_192)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.reservedResources(of: one), [])
        XCTAssertThrowsGameError(try world.removeTrackPlatform(station, on: .edge(2), from: 2_000), .trackReserved(one))
        try world.unplaceTrain(one)
        try world.removeTrackPlatform(station, on: .edge(2), from: 2_000)

        // A reserved edge cannot be removed, though no train is on it yet.
        let two = try buy(&world)
        try world.placeTrain(two, at: .onEdge(forward(1), offset: 4_000))
        try world.setTrainContinuation(two, along: [forward(2)], stoppingAt: 500)
        XCTAssertThrowsGameError(try world.removeTrackEdge(.edge(2)), .trackReserved(two))
    }

    // MARK: - Services on the network

    /// A timetable on the network waits for its route and turns round only
    /// once it can go.
    func testANetworkServiceWaitsAndTurnsRoundOnlyToGo() throws {
        var world = try GameWorld(width: 20, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        let nodes = try [1_024, 9_216, 17_408].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: 1_024)) }
        try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        let west = try world.buildStation(named: "W", at: p(1, 3)).id
        let east = try world.buildStation(named: "E", at: p(2, 3)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: .edge(2), from: 3_072, to: 7_168)
        // At E's forward berth, 7168 along e2; back to W's backward berth on
        // e1, 8192 − 1024 = 7168 along e1 run backward.
        let one = try stand(&world, at: forward(2), 7_168)
        try world.setTrainMovementRate(one, to: 1_024)
        try world.setTrainTimetable(one, to: [
            ScheduledStop(station: east, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1), reverses: true),
            ScheduledStop(station: west, arrival: GameTime(minutes: 30), departure: GameTime(minutes: 30)),
        ])
        try world.startTrainService(one)
        let blocker = try stand(&world, at: forward(1), 3_000)
        try world.setTrafficControl(true)
        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(forward(2), offset: 7_168))
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(0, cycle: 0))
        XCTAssertEqual(world.trainHoldingRoute(of: one), blocker)

        try world.unplaceTrain(blocker)
        try world.advance(ticks: 1)
        // Turned round (1024 along e2 backward), then 1024 on.
        XCTAssertEqual(world.train(id: one)?.position, .onEdge(backward(2), offset: 2_048))
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1, cycle: 0))
        // From chainage 7168 back along e2 to n2, and e1 back to 7168 along
        // it: chainage 1024.
        XCTAssertEqual(world.reservedResources(of: one), [
            node(2), span(1, 1_024, 2_048), span(1, 2_048, 3_072), span(1, 3_072, 4_096), span(1, 4_096, 5_120), span(1, 5_120, 6_144),
            span(1, 6_144, 7_168), span(1, 7_168, 8_192), span(1, 0, 1_024),
            span(2, 0, 1_024), span(2, 1_024, 2_048), span(2, 2_048, 3_072), span(2, 3_072, 4_096), span(2, 4_096, 5_120),
            span(2, 5_120, 6_144), span(2, 6_144, 7_168), span(2, 7_168, 8_192),
        ].sorted())
    }

    // MARK: - Saves

    private func encoded(_ world: GameWorld) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(world)) as? [String: Any])
    }

    private func decode(_ json: [String: Any]) throws -> GameWorld {
        try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// Traffic control and reservations are saved only when used; they read
    /// back exactly, including track a train has passed but still holds.
    func testSavesKeepTrafficControlAndReservations() throws {
        var world = try makeLineWorld()
        let grid = try GameWorld(width: 4, height: 4, economy: GameEconomy(balance: 1_000, costs: testCosts))
        XCTAssertNil(try encoded(grid)["trafficControl"])
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 4_600))
        try world.setTrainContinuation(one, along: [forward(2)], stoppingAt: 1_500)
        try world.setTrainMovementRate(one, to: 1_024)
        try world.advance(ticks: 1)
        let json = try encoded(world)
        XCTAssertEqual(json["trafficControl"] as? Bool, true)
        let trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        let saved = try XCTUnwrap(trains[0]["reservation"] as? [[String: Any]])
        XCTAssertEqual(saved.count, 4)
        XCTAssertEqual(saved[0]["node"] as? Int, 2)
        XCTAssertEqual(saved[1]["edge"] as? Int, 1)
        XCTAssertEqual(saved[1]["start"] as? Int, 4_096)
        XCTAssertEqual(try decode(json), world)

        // A grid reservation reads back too.
        var (gridWorld, _, _) = try makeGridWorld()
        try gridWorld.setTrafficControl(true)
        let train = try place(&gridWorld, at: .onLink(from: p(2, 1), to: p(3, 1), offset: 100))
        let gridJSON = try encoded(gridWorld)
        let gridTrains = try XCTUnwrap(gridJSON["trains"] as? [[String: Any]])
        let resources = try XCTUnwrap(gridTrains[0]["reservation"] as? [[String: Any]])
        XCTAssertEqual(resources.count, 2)
        XCTAssertNotNil(resources[0]["tile"])
        XCTAssertNotNil(resources[1]["link"])
        XCTAssertEqual(try decode(gridJSON).reservedResources(of: train), [tile(3, 1), link((2, 1), (3, 1))])
    }

    /// Saves that break a Stage T rule are refused, never repaired.
    func testBrokenTrafficSavesAreRefused() throws {
        var world = try makeLineWorld()
        // e2's platform cuts it at 100 and 1100: its spans are 0–100,
        // 100–1000, 1000–1100, 1100–2000 and 2000–3000.
        let station = try world.buildStation(named: "P", at: p(1, 3)).id
        try world.addTrackPlatform(station, on: .edge(2), from: 100, to: 1_100)
        try world.setTrafficControl(true)
        let one = try buy(&world)
        try world.placeTrain(one, at: .onEdge(forward(1), offset: 500))
        try world.setTrainContinuation(one, along: [], stoppingAt: 1_500)
        let two = try stand(&world, at: forward(1), 3_000)
        let json = try encoded(world)
        XCTAssertNoThrow(try decode(json))

        func mutated(_ change: (inout [String: Any], inout [[String: Any]]) -> Void) -> [String: Any] {
            var copy = json
            var trains = copy["trains"] as! [[String: Any]]
            change(&copy, &trains)
            copy["trains"] = trains
            return copy
        }
        let valid: [[String: Any]] = [["edge": 1, "start": 0, "end": 1_024], ["edge": 1, "start": 1_024, "end": 2_048]]
        let cases: [(String, [String: Any])] = [
            ("null flag", mutated { world, _ in world["trafficControl"] = NSNull() }),
            ("flag not a Bool", mutated { world, _ in world["trafficControl"] = "yes" }),
            ("reserved while off", mutated { world, _ in world["trafficControl"] = false }),
            ("null reservation", mutated { _, trains in trains[0]["reservation"] = NSNull() }),
            ("unsorted", mutated { _, trains in trains[0]["reservation"] = valid.reversed() }),
            ("repeated", mutated { _, trains in trains[0]["reservation"] = [valid[0], valid[0], valid[1]] }),
            ("start after end", mutated { _, trains in trains[0]["reservation"] = [["edge": 1, "start": 1_024, "end": 0], valid[1]] }),
            ("two tags", mutated { _, trains in trains[0]["reservation"] = [["edge": 1, "start": 0, "end": 1_024, "node": 1], valid[1]] }),
            ("no tag", mutated { _, trains in trains[0]["reservation"] = [[String: Any](), valid[1]] }),
            ("unknown edge", mutated { _, trains in trains[0]["reservation"] = valid + [["edge": 9, "start": 0, "end": 1_024]] }),
            ("unknown node", mutated { _, trains in trains[0]["reservation"] = [["node": 9]] + valid }),
            ("not a span of the edge", mutated { _, trains in trains[0]["reservation"] = [["edge": 1, "start": 0, "end": 2_048]] }),
            ("short of the route", mutated { _, trains in trains[0]["reservation"] = [valid[0]] }),
            ("over another train's track", mutated { _, trains in trains[0]["reservation"] = valid + [["edge": 1, "start": 2_048, "end": 3_072]] }),
            ("on a standing train", mutated { _, trains in trains[1]["reservation"] = [["edge": 1, "start": 2_048, "end": 3_072]] }),
            ("unplaced", mutated { _, trains in trains[1]["position"] = nil; trains[1]["movement"] = nil; trains[1]["reservation"] = [["node": 1]] }),
            ("link not neighbours", mutated { _, trains in trains[0]["reservation"] = [["link": [["x": 0, "y": 0], ["x": 2, "y": 0]]]] + valid }),
            ("the platform moved to e1, cutting it again", mutated { world, _ in
                var network = world["network"] as! [String: Any]
                network["platforms"] = [["station": station.rawValue, "edge": 1, "start": 700, "end": 900]]
                world["network"] = network
            }),
        ]
        for (name, broken) in cases {
            XCTAssertThrowsError(try decode(broken), name)
        }
        // More than the route needs is a lock, not an error.
        let extra = mutated { _, trains in trains[0]["reservation"] = valid + [["edge": 2, "start": 2_000, "end": 3_000]] }
        XCTAssertEqual(try decode(extra).reservedResources(of: one), [span(1, 0, 1_024), span(1, 1_024, 2_048), span(2, 2_000, 3_000)])
        _ = two
    }
}
