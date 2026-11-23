@testable import GameCore
import XCTest

/// TYMC-REBUILT-DEADLOCK: a following train's claim does not bind a train
/// holding track that fouls the claim's route.
///
///   w ──────e1────── J ──────e2────── e        B, from W on e1 to E on e2
///   W                 ╲e3             E
///                      ╲── y          Y        A, on e3 a little way out
///
/// A stands on the branch e3 where it has not yet parted from e2 (the two
/// are closer than the track spacing there), past the junction, bound for
/// Y at the end of e3. B comes up e1, bound for E over e2, following: its
/// claim waits for e2, which no train holds. Before, the spans of e2 beside
/// A fouled the spans A stood on, so B's claim kept A where it was, and A
/// kept B from e2: neither moved again. (On the Taoyuan Airport MRT
/// rebuilt, an empty run out of Airport Terminal 2 for the depot stood on
/// the crossover to the other line, all of it beside the line an empty run
/// from the depot came up; 26 trains stood behind the two for a day and
/// more.) Now A, ahead as surely as a train on B's route, goes on, and B
/// after it.
final class FoulingClaimTests: XCTestCase {
    private func makeWorld() throws -> (world: GameWorld, a: TrainID, b: TrainID, stations: [String: StationID]) {
        var world = try GameWorld(bounds: WorldBounds(width: 462_848, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
                                  clock: GameClock(speed: .normal))
        func node(_ x: Int64, _ y: Int64) throws -> TrackNodeID { try world.buildTrackNode(at: WorldCoordinate(x: x, y: y)) }
        let w = try node(1_024, 8_192), j = try node(131_072, 8_192), e = try node(262_144, 8_192), y = try node(196_608, 12_032)
        try world.buildTrackEdge(from: w, to: j)
        try world.buildTrackEdge(from: j, to: e)
        try world.buildTrackEdge(from: j, to: y, curve: .cubic(.init(x: 163_840, y: 8_192), .init(x: 163_840, y: 12_032)))
        let e2 = try XCTUnwrap(world.trackEdge(.edge(2))?.length), e3 = try XCTUnwrap(world.trackEdge(.edge(3))?.length)
        var stations: [String: StationID] = [:]
        for (name, edge, start, x, y) in [("W", 1, Int64(2_048), Int64(4_096), Int64(5_120)), ("E", 2, e2 - 8_192, 249_856, 5_120),
                                          ("Y", 3, e3 - 8_192, 196_608, 15_360)] {
            let station = try world.buildStation(named: name, at: PlanPoint(x: x, y: y)).id
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: start + 4_096)
            stations[name] = station
        }
        // B first: of two following trains the lower number goes first.
        let b = try world.purchaseTrain(named: "B").id, a = try world.purchaseTrain(named: "A").id
        for (id, edge, offset) in [(b, 1, Int64(98_304)), (a, 3, Int64(6_144))] {
            try world.setTrainCars(id, to: 1)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: .forward), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
        }
        try world.setTrafficControl(true)
        // Both hold their routes only a little way: each follows.
        for (id, from, to, edges, end) in [(b, "W", "E", [TrackEdgeID.edge(2)], e2 - 4_096), (a, "W", "Y", [], e3 - 4_096)] {
            var train = try XCTUnwrap(world.train(id: id))
            train.timetable = [
                ScheduledStop(station: stations[from]!, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 0)),
                ScheduledStop(station: stations[to]!, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
            ]
            train.isDeadheading = true
            train.execution = .travellingToStop(1, cycle: 0)
            train.movement.edges = edges
            train.movement.end = end
            train.movement.cursor = 0
            train.reservation = world.authorityEnvelope(of: train, to: 1_024).sorted()
            world = world.replacing(train)
        }
        return (world, a, b, stations)
    }

    /// The scene is the one described: A's track fouls B's route, without
    /// being of it, and both follow.
    func testTheTrainOnTheBranchFoulsTheFollowersRoute() throws {
        let (world, a, b, _) = try makeWorld()
        let route = try XCTUnwrap(world.claim(of: try XCTUnwrap(world.train(id: b)))).route
        let held = Set(world.heldResources(of: a))
        XCTAssertTrue(held.isDisjoint(with: route), "A holds none of B's route")
        XCTAssertTrue(world.network.fouls(held, route), "A's track fouls B's route")
        XCTAssertTrue(world.isFollowing(try XCTUnwrap(world.train(id: a))))
    }

    /// A is not kept by B's claim; second by second no train stands
    /// deadlocked, and both reach their stations.
    func testATrainFoulingAFollowersRouteGoesOn() throws {
        var (world, a, b, stations) = try makeWorld()
        XCTAssertNotEqual(world.trainHoldingRoute(of: a), b, "A does not wait for B's claim")
        world.setSpeed(.x1)
        for _ in 0..<300 {
            try world.advance(ticks: 1)
            XCTAssertEqual(world.deadlockedTrains(), [], "at \(world.clock.now.seconds) s")
        }
        world.setSpeed(.normal)
        var arrived: Set<TrainID> = []
        for _ in 0..<90 {
            try world.advance(ticks: 1)
            XCTAssertEqual(world.deadlockedTrains(), [])
            XCTAssertEqual(WorldInvariants.violations(in: world), [])
            for (id, station) in [(a, "Y"), (b, "E")] where world.stationsStoppedAt(by: id).contains(stations[station]!) {
                arrived.insert(id)
            }
        }
        XCTAssertEqual(arrived, [a, b])
    }

    /// A batch of minutes ends where minute by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var minutes = try makeWorld().world
        var batch = try makeWorld().world
        for _ in 0..<30 { try minutes.advance(ticks: 1) }
        try batch.advance(ticks: 30)
        XCTAssertEqual(minutes, batch)
    }
}
