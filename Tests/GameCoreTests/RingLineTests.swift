import Foundation
@testable import GameCore
import XCTest

/// Ring lines (ARCHITECTURE decision 49, after the `Ci/` metro game's
/// `isRing`): a line whose trains go on from its last stop back to the
/// first, never turning round, half of them each way; laps planned with a
/// dwell at every stop and no terminal; pairs of trains; passengers taken
/// from both ways' queues for a station the train reaches before its lap
/// ends.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class RingLineTests: XCTestCase {
    // A loop of track-network track (Stage F3b), clockwise from the top,
    // the loop of the golden `ring-line.json`: nodes 1 (2560, 1536), 2
    // (3584, 1536) and 3 (4608, 1536) along the top and 5 (4608, 3584), 6
    // (3584, 3584) and 7 (2560, 3584) along the bottom, joined by straight
    // edges of 1024 (1, 2, 5 and 6), and at each corner one cubic edge 2048
    // long (3 to node 4 (5632, 2560), 4, 7 to node 8 (1536, 2560), and 8),
    // the length of the grid's two links round the corner: edges join at a
    // node only where they leave it in opposite directions, so a corner
    // must be a curve.
    //
    //        A(3,0)
    //   (2,1) (3,1) (4,1)
    //   (1,2)             (5,2) B(6,2)
    //   (2,3) (3,3) (4,3)
    //  D(0,2)       C(3,4)
    //
    // Each station has one platform, the last 512 of the edge that leads
    // clockwise into its node (A edge 1, B edge 3, C edge 5, D edge 7), so a
    // train stops at the node going clockwise and 512 before it going
    // anticlockwise; either way from each to the next round the loop is
    // 3072, 48 m. The ring plans with a crawl (as `LineDispatchTests`): 1
    // km/h, reached in 8 s (1.111 m) and stopped from in 10 s (1.389 m),
    // so a leg of 48 m takes 8 + 45.5 / 0.27778 + 10 = 181.8 s, planned as
    // 182. A lap is four legs and a minute at each of the four stops, 968
    // s, planned as 17 minutes.
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let delta = StationID(rawValue: 4)
    private let ring = LineID(rawValue: 1)
    private let unknownLine = LineID(rawValue: 9)
    /// Alpha's berths: going clockwise (the inner way) at node 2, the end
    /// of edge 1; going anticlockwise (the outer way) 512 along edge 1
    /// backward.
    private let clockwise = TrainPosition.onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 1_024)
    private let anticlockwise = TrainPosition.onEdge(TrackTraversal(edge: .edge(1), direction: .backward), offset: 512)
    private let crawl = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)
    private let leg: Int64 = 182
    private let lap: Int64 = 968

    private func makeLoopWorld(minute: Int64 = 0) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 7_168, height: 5_120), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        let corner: Int64 = 1_338
        let nodes: [(Int64, Int64)] = [(2_560, 1_536), (3_584, 1_536), (4_608, 1_536), (5_632, 2_560), (4_608, 3_584), (3_584, 3_584), (2_560, 3_584), (1_536, 2_560)]
        for (x, y) in nodes {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        let curves: [TrackCurve] = [
            .straight, .straight,
            .cubic(PlanPoint(x: 4_608 + corner, y: 1_536), PlanPoint(x: 5_632, y: 2_560 - corner)),
            .cubic(PlanPoint(x: 5_632, y: 2_560 + corner), PlanPoint(x: 4_608 + corner, y: 3_584)),
            .straight, .straight,
            .cubic(PlanPoint(x: 2_560 - corner, y: 3_584), PlanPoint(x: 1_536, y: 2_560 + corner)),
            .cubic(PlanPoint(x: 1_536, y: 2_560 - corner), PlanPoint(x: 2_560 - corner, y: 1_536)),
        ]
        for (index, curve) in curves.enumerated() {
            try world.buildTrackEdge(from: .node(index + 1), to: .node((index + 1) % 8 + 1), curve: curve)
        }
        for (name, x, y, edge, length) in [("Alpha", 3, 0, 1, 1_024), ("Beta", 6, 2, 3, 2_048), ("Gamma", 3, 4, 5, 1_024), ("Delta", 0, 2, 7, 2_048)] as [(String, Int, Int, Int, Int64)] {
            let station = try world.buildStation(named: name, at: TestLine.centre(x, y)).id
            try world.addTrackPlatform(station, on: .edge(edge), from: length - 512, to: length)
        }
        return world
    }

    /// The loop with ring 1 calling at Alpha, Beta, Gamma and Delta all day
    /// with `running` trains, and `count` trains standing at Alpha, the
    /// first facing east (the inner way, Alpha to Beta), the second west
    /// (the outer way, Alpha to Delta), and so on, assigned to it.
    private func makeRingWorld(trains count: Int, running: TrainsInService, minute: Int64 = 0) throws -> GameWorld {
        var world = try makeLoopWorld(minute: minute)
        try world.createLine(named: "Ring", stops: [alpha, beta, gamma, delta])
        try world.setLineRing(ring, to: true)
        try world.setLinePerformance(ring, to: crawl)
        try world.setLineServiceWindow(ring, to: .allDay)
        try world.setLineTrainsInService(ring, to: running)
        for index in 1...count {
            let train = try world.purchaseTrain(named: "T\(index)")
            try world.placeTrain(train.id, at: index % 2 == 1 ? clockwise : anticlockwise)
            if index % 2 == 0 {
                // A placed train with no path runs to the end of its edge:
                // the outer way's train keeps to its berth, mid-edge.
                try world.setTrainContinuation(train.id, along: [], stoppingAt: 512)
            }
            try world.setTrainMovementRate(train.id, to: 1024)
            try world.assignTrain(train.id, to: ring)
        }
        return world
    }

    private func pairs(_ count: Int) -> TrainsInService {
        TrainsInService(peak: count, offPeak: count, low: count)
    }

    func testPassengerRouteEndsAtTheRingLapBoundary() throws {
        let world = try makeRingWorld(trains: 2, running: pairs(2))
        let routes = world.passengerRoutes(from: beta, to: delta)

        XCTAssertEqual(routes.first?.legs.map(\.direction), [.outbound])
        XCTAssertEqual(routes.first?.legs.map(\.from), [beta])
        XCTAssertEqual(routes.first?.legs.map(\.to), [delta])
        XCTAssertFalse(routes.contains { route in
            route.legs.contains { $0.direction == .inbound && $0.from == beta && $0.to == delta }
        }, "\(routes)")
        XCTAssertTrue(routes.contains { route in
            route.legs.map(\.direction) == [.inbound, .inbound] &&
            route.legs.map(\.from) == [beta, alpha] &&
            route.legs.map(\.to) == [alpha, delta] && route.waitMinutes == 18
        }, "crossing the lap must start a new ride and wait again: \(routes)")
    }

    func testPlannedPassengerChangesLapsAndArrivesWithoutLosingOrigin() throws {
        var world = try makeRingWorld(trains: 2, running: pairs(2))
        world.setPassengerRoutingMode(.network)
        try world.setStationDemand(beta, to: StationDemand(kind: .residential, dailyTrips: 0))
        let route = try XCTUnwrap(world.passengerRoutes(from: beta, to: delta).first {
            $0.legs.map(\.direction) == [.inbound, .inbound]
        })
        let journey = try XCTUnwrap(PassengerJourney(origin: beta, route: route))
        world.passengers[0].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 17)
        XCTAssertEqual(world.passengerLedger(of: beta).waiting, 5)
        XCTAssertEqual(world.waitingPassengers(at: alpha).first?.journey?.current, 1)
        XCTAssertEqual(world.passengerLedger(of: beta).abandoned, 0)
        var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        try world.advance(ticks: 20)
        for _ in 0..<20 { try loaded.advance(ticks: 1) }
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(world.passengerLedger(of: beta).arrived, 5)
        XCTAssertEqual(world.passengerLedger(of: beta).waiting + world.passengerLedger(of: beta).riding, 0)
        XCTAssertEqual(world.passengerLedger(of: beta).abandoned, 0)
    }

    // MARK: - Making a ring

    /// A ring needs three stops or more, not the same station first and
    /// last, and no patterns; making one makes its counts even, down, and
    /// it refuses patterns and odd counts from then on. Making it a line
    /// again forgets its outer dispatch. Refused commands change nothing.
    func testMakingARingChecksItsStopsAndPatterns() throws {
        var world = try makeLoopWorld()
        try world.createLine(named: "Ring", stops: [alpha, beta, gamma, delta])
        try world.createLine(named: "Short", stops: [alpha, beta])
        try world.createLine(named: "Back", stops: [alpha, beta, alpha])
        try world.setLineTrainsInService(ring, to: TrainsInService(peak: 5, offPeak: 2, low: 1))

        let before = world
        XCTAssertThrowsGameError(try world.setLineRing(unknownLine, to: true), .unknownLine(unknownLine))
        XCTAssertThrowsGameError(try world.setLineRing(LineID(rawValue: 2), to: true), .invalidLineStops)
        XCTAssertThrowsGameError(try world.setLineRing(LineID(rawValue: 3), to: true), .invalidLineStops)
        try world.addLinePattern(ring, calling: [0, 1])
        XCTAssertThrowsGameError(try world.setLineRing(ring, to: true), .invalidLinePattern)
        try world.removeLinePattern(ring, at: 0)
        XCTAssertEqual(world, before)

        try world.setLineRing(ring, to: true)
        var line = try XCTUnwrap(world.line(id: ring))
        XCTAssertTrue(line.isRing)
        XCTAssertEqual(line.trainsInService, TrainsInService(peak: 4, offPeak: 2, low: 0), "counts made even, down")
        XCTAssertEqual(world.economy, before.economy, "free")

        let ringWorld = world
        XCTAssertThrowsGameError(try world.addLinePattern(ring, calling: [0, 1]), .invalidLinePattern)
        XCTAssertThrowsGameError(try world.setLineStops(ring, to: [alpha, beta]), .invalidLineStops)
        XCTAssertThrowsGameError(try world.setLineStops(ring, to: [alpha, beta, gamma, alpha]), .invalidLineStops)
        XCTAssertEqual(world, ringWorld)
        try world.setLineStops(ring, to: [alpha, gamma, beta])
        try world.setLineTrainsInService(ring, to: TrainsInService(peak: 7, offPeak: 3, low: 2))
        line = try XCTUnwrap(world.line(id: ring))
        XCTAssertEqual(line.trainsInService, TrainsInService(peak: 6, offPeak: 2, low: 2))

        // Only a ring has directions; a line again has no outer dispatch.
        XCTAssertNil(world.line(id: LineID(rawValue: 2))?.ringDirection(of: TrainID(rawValue: 1)))
        try world.setLineRing(ring, to: false)
        line = try XCTUnwrap(world.line(id: ring))
        XCTAssertFalse(line.isRing)
        XCTAssertNil(line.outerLastDispatch)
        XCTAssertEqual(line.trainsInService, TrainsInService(peak: 6, offPeak: 2, low: 2), "counts stay as they are")
        try world.addLinePattern(ring, calling: [0, 1])
    }

    /// The trains run alternately the inner and the outer way, in ID order;
    /// taking one off shifts those after it.
    func testDirectionsAlternateInIDOrder() throws {
        var world = try makeRingWorld(trains: 3, running: .none)
        let ids = (1...3).map { TrainID(rawValue: $0) }
        var line = try XCTUnwrap(world.line(id: ring))
        XCTAssertEqual(ids.map { line.ringDirection(of: $0) }, [.inner, .outer, .inner])
        XCTAssertNil(line.ringDirection(of: TrainID(rawValue: 9)))
        try world.unassignTrain(ids[0])
        line = try XCTUnwrap(world.line(id: ring))
        XCTAssertEqual(ids.map { line.ringDirection(of: $0) }, [nil, .inner, .outer])
    }

    // MARK: - The lap and its plan

    /// The ring's journey is its lap the inner way: four legs of three
    /// links, the last back from Delta to Alpha, never turning round, and a
    /// minute at each stop: 968 s, 17 minutes. It runs at most eight trains
    /// each way (17 / 2), sixteen in all; with a pair each way the headway
    /// is 9 (17 / 2 rounded up), with one each way 17. A target of 5 runs
    /// four each way (17 / 5 rounded up) at 5 minutes. Every segment,
    /// Delta to Alpha included, carries a day's trains at the headway.
    func testTheLapPlansTheRing() throws {
        let world = try makeRingWorld(trains: 1, running: pairs(4))
        let journey = try XCTUnwrap(world.lineJourney(ring))
        XCTAssertTrue(journey.isRing)
        XCTAssertEqual(journey.legs.map { [$0.from, $0.to] }, [[0, 1], [1, 2], [2, 3], [3, 0]])
        XCTAssertEqual(journey.legs.map(\.seconds), [leg, leg, leg, leg])
        XCTAssertEqual(journey.legs.map(\.path.distance), [3_072, 3_072, 3_072, 3_072])
        XCTAssertEqual(journey.roundTripSeconds, lap)
        XCTAssertEqual(journey.roundTripMinutes, 17)
        XCTAssertEqual(world.lineMaximumTrains(ring), 16)
        XCTAssertEqual(world.lineTrainsInService(ring, at: .peak), 4)
        XCTAssertEqual(world.lineHeadway(ring, at: .peak), 9)
        XCTAssertEqual(world.lineSegmentLoads(ring, at: .peak), [160, 160, 160, 160], "1440 / 9 rounded up")

        var targets = world
        try targets.setLineTrainsInService(ring, to: pairs(2))
        XCTAssertEqual(targets.lineHeadway(ring, at: .peak), 17)
        try targets.setLineTargetHeadways(ring, to: TargetHeadways(peak: 5))
        XCTAssertEqual(targets.lineTrainsInService(ring, at: .peak), 8)
        XCTAssertEqual(targets.lineHeadway(ring, at: .peak), 5)
        XCTAssertEqual(targets.lineTrainsInService(ring, at: .low), 2, "no target: the count")
        try targets.setLineTrainsInService(ring, to: pairs(40))
        XCTAssertEqual(targets.lineTrainsInService(ring, at: .low), 16, "never past the maximum")

        // Without the track from Delta back to Alpha (the corner, edge 8)
        // there is no lap.
        var open = world
        try open.removeTrackEdge(.edge(8))
        XCTAssertNil(open.lineJourney(ring))
        XCTAssertNil(open.lineMaximumTrains(ring))
    }

    // MARK: - Dispatch

    /// Sent out together, the inner train goes Alpha, Beta, Gamma, Delta and
    /// back to Alpha, the outer Alpha, Delta, Gamma, Beta, Alpha, neither
    /// turning round: each leaves Alpha after the least dwell, 36 s (no
    /// terminal on a ring), and each stop is a leg (182 s) and a minute
    /// after the one before. Back at Alpha at 944 s, each dwells its 36 s
    /// and its lap is over at 980 s; each way is sent out again a headway,
    /// 17 minutes, after it last was.
    func testEachWaySendsItsTrainOutOnLaps() throws {
        var world = try makeRingWorld(trains: 2, running: pairs(2))
        try world.advance(ticks: 1)
        let (inner, outer) = (TrainID(rawValue: 1), TrainID(rawValue: 2))
        func call(_ station: StationID, _ arrival: Int64, _ departure: Int64) -> ScheduledStop {
            ScheduledStop(station: station, arrival: GameTime(seconds: arrival), departure: GameTime(seconds: departure))
        }
        let times: [(Int64, Int64)] = [(0, 36), (218, 278), (460, 520), (702, 762), (944, 944)]
        let innerStops = [alpha, beta, gamma, delta, alpha], outerStops = [alpha, delta, gamma, beta, alpha]
        XCTAssertEqual(world.train(id: inner)?.timetable, zip(innerStops, times).map { call($0, $1.0, $1.1) })
        XCTAssertEqual(world.train(id: outer)?.timetable, zip(outerStops, times).map { call($0, $1.0, $1.1) })
        var line = try XCTUnwrap(world.line(id: ring))
        XCTAssertEqual(line.lastDispatch, GameTime(minutes: 0))
        XCTAssertEqual(line.outerLastDispatch, GameTime(minutes: 0))

        // The first leg: each left Alpha after its 36 s.
        XCTAssertEqual(world.train(id: inner)?.times?.departure, GameTime(seconds: 36))
        XCTAssertEqual(world.train(id: outer)?.times?.departure, GameTime(seconds: 36))
        XCTAssertEqual(world.train(id: inner)?.execution, .travellingToStop(1))

        // Back at Alpha the lap is over at 980 s: by 17:00, before that
        // minute's dispatch, both stand idle, facing the way they came round.
        try world.advance(ticks: 16)
        XCTAssertNil(world.train(id: inner)?.execution)
        XCTAssertNil(world.train(id: outer)?.execution)
        XCTAssertEqual(world.train(id: inner)?.position, clockwise)
        XCTAssertEqual(world.train(id: outer)?.position, anticlockwise)
        try world.advance(ticks: 1)
        line = try XCTUnwrap(world.line(id: ring))
        XCTAssertEqual(line.lastDispatch, GameTime(minutes: 17))
        XCTAssertEqual(line.outerLastDispatch, GameTime(minutes: 17))
        XCTAssertEqual(world.train(id: inner)?.timetable.map(\.station), innerStops)
    }

    /// Each way runs half the count: with two pairs and three trains, the
    /// inner way has two trains and sends them 9 minutes apart; the outer
    /// way has one, sent once a lap at most.
    func testEachWayRunsHalfTheCount() throws {
        var world = try makeRingWorld(trains: 3, running: pairs(4))
        try world.advance(ticks: 1)
        let ids = (1...3).map { TrainID(rawValue: $0) }
        XCTAssertEqual(ids.map { world.train(id: $0)?.execution != nil }, [true, true, false], "one each way at minute 0")
        try world.advance(ticks: 9)
        XCTAssertEqual(ids.map { world.train(id: $0)?.execution != nil }, [true, true, true], "the second inner train 9 minutes later")
        XCTAssertEqual(world.train(id: ids[2])?.timetable.first?.arrival, GameTime(minutes: 9))
        XCTAssertEqual(world.line(id: ring)?.lastDispatch, GameTime(minutes: 9))
        XCTAssertEqual(world.line(id: ring)?.outerLastDispatch, GameTime(minutes: 0))
    }

    // MARK: - Passengers

    /// A ring's train takes passengers waiting either way, for a station it
    /// reaches before its lap ends: from Beta to Delta only the inner train
    /// (Beta, Gamma, Delta), from Delta to Beta only the outer (Delta,
    /// Gamma, Beta); nobody rides past Alpha, so nobody is abandoned there.
    func testPassengersRideTheWayThatReachesThemInTheLap() throws {
        var world = try makeRingWorld(trains: 2, running: pairs(2), minute: 480)
        try world.setStationDemand(beta, to: StationDemand(kind: .residential, dailyTrips: 200_000))
        try world.setStationDemand(delta, to: StationDemand(kind: .office, dailyTrips: 200_000))
        let (inner, outer) = (TrainID(rawValue: 1), TrainID(rawValue: 2))
        // Sent out at 08:00; at 08:05 both have left their second stop
        // (218 + 60 s): the inner one Beta, the outer one Delta.
        try world.advance(ticks: 5)
        XCTAssertEqual(world.train(id: inner)?.execution, .travellingToStop(2))
        let innerRiders = world.riders(of: inner)
        let outerRiders = world.riders(of: outer)
        XCTAssertFalse(innerRiders.isEmpty)
        XCTAssertFalse(outerRiders.isEmpty)
        XCTAssertTrue(innerRiders.allSatisfy { $0.origin == beta && $0.destination == delta })
        XCTAssertTrue(outerRiders.allSatisfy { $0.origin == delta && $0.destination == beta })
        // Both laps end at 08:16:20 with everyone off where they were going.
        try world.advance(ticks: 12)
        XCTAssertEqual(world.riderCount(of: inner), 0)
        XCTAssertEqual(world.riderCount(of: outer), 0)
        XCTAssertGreaterThan(world.passengerLedger(of: beta).arrived, 0)
        XCTAssertGreaterThan(world.passengerLedger(of: delta).arrived, 0)
        XCTAssertEqual(world.passengerLedger(of: beta).abandoned + world.passengerLedger(of: delta).abandoned, 0)
    }

    // MARK: - Saving

    /// A ring saves `"ring": true` and, once it has sent a train out the
    /// outer way, `"outerLastDispatch"` (as `"lastDispatch"`); a line has
    /// neither. Loading refuses a ring of two stops, the same
    /// station first and last, with patterns or odd counts, a `false`, and
    /// an outer dispatch on a line.
    func testARingSavesAndLoadsAndBadRingsAreRefused() throws {
        var world = try makeRingWorld(trains: 2, running: pairs(2))
        try world.advance(ticks: 1)
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lines = try XCTUnwrap(object["lines"] as? [[String: Any]])
        XCTAssertEqual(lines[0]["ring"] as? Bool, true)
        XCTAssertNotNil(lines[0]["outerLastDispatch"])

        func load(_ change: (inout [String: Any]) -> Void) -> GameWorld? {
            var saved = object
            var line = lines[0]
            change(&line)
            saved["lines"] = [line]
            return try? JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: saved))
        }
        XCTAssertNotNil(load { _ in })
        XCTAssertNil(load { $0["stops"] = [1, 2] }, "two stops")
        XCTAssertNil(load { $0["stops"] = [1, 2, 3, 1] }, "the same first and last")
        XCTAssertNil(load { $0["trainsInService"] = ["peak": 3, "offPeak": 2, "low": 2] }, "an odd count")
        XCTAssertNil(load { $0["patterns"] = [["calls": [0, 1], "trainsInService": ["peak": 0, "offPeak": 0, "low": 0]]] }, "a pattern")
        XCTAssertNil(load { $0["ring"] = false }, "false is never written")
        XCTAssertNil(load { $0["ring"] = nil }, "an outer dispatch on a line")
        XCTAssertNotNil(load { $0["ring"] = nil; $0["outerLastDispatch"] = nil }, "a line")
    }
}
