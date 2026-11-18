@testable import GameCore
import XCTest

/// Decision 850 (TCL-DEPOT-CLAIM): an empty run's claim does not bind a
/// service due to leave the berth the service it follows is due for.
/// ``FollowerClaimDeadlockTests``' track, with a depot Dp on e11:
///
///                         ╭─e6── b1 ──e7── b2 ──e8─╮      the loop, P2 on e7
///   w0 ─e1─ wX ─e2─ wZ ─e3─ wY ──────────e4─────────── wP ─e5─ wR
///   K      ╱          ╲ e11
///   a0 ─e9─ c          Dp
///      Q
///
/// The service D stands at P2 bound for K, over e2. S stands at Q bound
/// for P2, over the crossover and e2, where D stands. The empty run F
/// (decision 209's, Q to Dp) follows behind S, bound for the depot over
/// the crossover, e2 and e11, and claims e2. Before, D waited for F's
/// claim, F for S and S for D, a deadlock until decision 577 sent D all
/// the same: on Hong Kong's Tung Chung Line the services at Tung Chung
/// bound for Hong Kong waited so for an empty run to Siu Ho Wan 25 km
/// away. Now D leaves when it is due, and no train stands deadlocked.
final class EmptyRunClaimDueServiceTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    private func makeWorld() throws -> (world: GameWorld, trains: [String: TrainID], stations: [String: StationID]) {
        var world = try GameWorld(bounds: WorldBounds(width: 462_848, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
                                  clock: GameClock(speed: .normal))
        func node(_ x: Int64, _ y: Int64) throws -> TrackNodeID { try world.buildTrackNode(at: WorldCoordinate(x: x, y: y)) }
        func bend(_ x: Int64, _ fromY: Int64, _ toY: Int64) -> TrackCurve { .cubic(.init(x: x, y: fromY), .init(x: x, y: toY)) }
        let w0 = try node(1_024, 8_192), wX = try node(131_072, 8_192), wZ = try node(163_840, 8_192), wY = try node(196_608, 8_192)
        let wP = try node(327_680, 8_192), wR = try node(458_752, 8_192), b1 = try node(229_376, 4_352), b2 = try node(294_912, 4_352)
        let a0 = try node(1_024, 12_032), c = try node(65_536, 12_032), dp = try node(229_376, 12_032)
        for (from, to, curve) in [(w0, wX, nil), (wX, wZ, nil), (wZ, wY, nil), (wY, wP, nil), (wP, wR, nil),
                                  (wY, b1, bend(212_992, 8_192, 4_352)), (b1, b2, nil), (b2, wP, bend(311_296, 4_352, 8_192)),
                                  (a0, c, nil), (c, wX, bend(98_304, 12_032, 8_192)), (wZ, dp, bend(196_608, 8_192, 12_032))] as [(TrackNodeID, TrackNodeID, TrackCurve?)] {
            if let curve { try world.buildTrackEdge(from: from, to: to, curve: curve) } else { try world.buildTrackEdge(from: from, to: to) }
        }
        let e11 = try XCTUnwrap(world.trackEdge(.edge(11))?.length)
        var stations: [String: StationID] = [:]
        for (name, edge, start, x, y) in [("K", 1, Int64(2_048), Int64(4_096), Int64(5_120)), ("P2", 7, 16_384, 249_856, 1_024),
                                          ("Q", 9, 45_056, 47_104, 15_360),
                                          ("Dp", 11, e11 - 6_144, 229_376, 15_360)] {
            let station = try world.buildStation(named: name, at: PlanPoint(x: x, y: y)).id
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: start + 4_096)
            stations[name] = station
        }
        var trains: [String: TrainID] = [:]
        for name in ["D", "S", "F"] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            trains[name] = id
        }
        let e7 = try XCTUnwrap(world.trackEdge(.edge(7))?.length)
        for (name, traversal, offset) in [("D", backward(7), e7 - 16_384),
                                          ("S", forward(9), Int64(49_152)), ("F", forward(9), 16_384)] {
            let id = trains[name]!
            try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
        }
        for (name, from, to) in [("D", "P2", "K"), ("S", "Q", "P2")] {
            try world.setTrainTimetable(trains[name]!, to: [
                ScheduledStop(station: stations[from]!, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
                ScheduledStop(station: stations[to]!, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
            ])
        }
        try world.setTrafficControl(true)
        // F, an empty run to the depot, sets off following S, holding its
        // route only a little way, as in decision 577's scene.
        var train = try XCTUnwrap(world.train(id: trains["F"]!))
        train.timetable = [
            ScheduledStop(station: stations["Q"]!, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 0)),
            ScheduledStop(station: stations["Dp"]!, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
        ]
        train.isDeadheading = true
        train.execution = .travellingToStop(1, cycle: 0)
        train.movement.edges = [.edge(10), .edge(2), .edge(11)]
        train.movement.end = e11 - 2_048
        train.movement.cursor = 0
        train.reservation = world.authorityEnvelope(of: train, to: 2_048).sorted()
        world = world.replacing(train)
        for name in ["D", "S"] {
            try world.startTrainService(trains[name]!)
        }
        return (world, trains, stations)
    }

    /// Second by second to 0:01:30, when both services are due and F has
    /// come up behind S: D does not wait for F's claim, and no train
    /// stands deadlocked; then D reaches K, S P2 and F the depot.
    func testADueServiceLeavesPastAnEmptyRunsClaim() throws {
        var (world, trains, stations) = try makeWorld()
        let (d, s, f) = (trains["D"]!, trains["S"]!, trains["F"]!)
        XCTAssertTrue(world.isFollowing(try XCTUnwrap(world.train(id: f))), "F follows S")
        XCTAssertEqual(world.train(id: f)?.isDeadheading, true)
        world.setSpeed(.x1)
        for _ in 0..<900 {
            try world.advance(ticks: 1)
            XCTAssertEqual(world.deadlockedTrains(), [], "at \(world.clock.now.seconds) s")
        }
        XCTAssertNotEqual(world.trainHoldingRoute(of: d), f, "D does not wait for F's claim")
        world.setSpeed(.normal)
        var arrived: Set<TrainID> = []
        for _ in 0..<60 {
            try world.advance(ticks: 1)
            XCTAssertEqual(world.deadlockedTrains(), [])
            XCTAssertEqual(WorldInvariants.violations(in: world), [])
            for (id, station) in [(d, "K"), (s, "P2"), (f, "Dp")] where world.stationsStoppedAt(by: id).contains(stations[station]!) {
                arrived.insert(id)
            }
        }
        XCTAssertEqual(arrived, [d, s, f])
    }

    /// A batch of minutes ends where minute by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var minutes = try makeWorld()
        var batch = try makeWorld()
        for _ in 0..<60 { try minutes.world.advance(ticks: 1) }
        try batch.world.advance(ticks: 60)
        XCTAssertEqual(minutes.world, batch.world)
    }
}
