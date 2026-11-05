@testable import GameCore
import XCTest

/// Decision 556, continued (TYMCLIST8, tested by TYMCLIST9): decision
/// 577's way out of a deadlock for a train between runs (decision 133).
/// On the Taoyuan Airport MRT under the simple rules with traffic control,
/// a train with no service at the first airport terminal could take its
/// due run's route but for the track an empty train following others
/// towards it claimed (decision 56, point 6), and the empty train waited,
/// through the others, for the berth the first stood on. Decision 577
/// sends only a service already waiting at a stop past such a claim, and
/// TYMCLIST7's way out (``RunTrainCounterflowTests``) only a train with a
/// free berth against the planned way, so it stood.
///
/// The scene is ``FollowerClaimDeadlockTests``' with D, there a service at
/// P2 bound for K, a train between runs of a line from P2 to K whose run
/// is due at 0:01:
///
///                         ╭─e6── b1 ──e7── b2 ──e8─╮      the loop, P2 on e7
///   w0 ─e1─ wX ─e2─ wZ ─e3─ wY ──────────e4─────────── wP ─e5─ wR
///   K      ╱          ╲ e11                                R
///   a0 ─e9─ c          dp
///      Q
///
/// M stands at R bound for P2, where D stands; S at Q bound for R, over
/// the crossover, where M stands; the empty train F follows behind S,
/// bound for the depot over the crossover, e2 and e11, and claims e2,
/// which D's run needs. D waits for F's claim, F for S, S for M and M for
/// D.
final class RunTrainFollowerClaimTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    private struct Scene {
        var world: GameWorld
        let trains: [String: TrainID]
        let stations: [String: StationID]
    }

    private func makeScene() throws -> Scene {
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
        var stations: [String: StationID] = [:]
        for (name, edge, start, x, y) in [("K", 1, Int64(2_048), Int64(4_096), Int64(5_120)), ("P2", 7, 16_384, 249_856, 1_024),
                                          ("Q", 9, 45_056, 47_104, 15_360), ("R", 5, 98_304, 428_032, 5_120)] {
            let station = try world.buildStation(named: name, at: PlanPoint(x: x, y: y)).id
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: start + 4_096)
            stations[name] = station
        }
        var trains: [String: TrainID] = [:]
        for name in ["D", "M", "S", "F"] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            trains[name] = id
        }
        let e5 = try XCTUnwrap(world.trackEdge(.edge(5))?.length), e7 = try XCTUnwrap(world.trackEdge(.edge(7))?.length)
        for (name, traversal, offset) in [("D", backward(7), e7 - 16_384), ("M", backward(5), e5 - 98_304),
                                          ("S", forward(9), Int64(49_152)), ("F", forward(9), 16_384)] {
            let id = trains[name]!
            try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
        }
        // D: a line from P2 to K, one run at 0:01.
        let line = try world.createLine(named: "L", stops: [stations["P2"]!, stations["K"]!]).id
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 60, departure: 60), LineRunTime(arrival: 1_260, departure: 1_260)])])
        try world.assignTrain(trains["D"]!, to: line)
        for (name, from, to) in [("M", "R", "P2"), ("S", "Q", "R")] {
            try world.setTrainTimetable(trains[name]!, to: [
                ScheduledStop(station: stations[from]!, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
                ScheduledStop(station: stations[to]!, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
            ])
        }
        try world.setTrafficControl(true)
        // F sets off for the depot following S, as in decision 577's scene.
        var train = try XCTUnwrap(world.train(id: trains["F"]!))
        train.movement.edges = [.edge(10), .edge(2), .edge(11)]
        train.movement.end = try XCTUnwrap(world.trackEdge(.edge(11))?.length) - 2_048
        train.movement.cursor = 0
        train.reservation = world.authorityEnvelope(of: train, to: 2_048).sorted()
        world = world.replacing(train)
        for name in ["M", "S"] {
            try world.startTrainService(trains[name]!)
        }
        return Scene(world: world, trains: trains, stations: stations)
    }

    /// The scene is the one meant: at 0:01:30 D has no service, its run is
    /// due, and the four wait for each other, D for the track F claims.
    func testDWaitsBetweenRunsForTheTrackFClaims() throws {
        var scene = try makeScene()
        let (d, m, s, f) = (scene.trains["D"]!, scene.trains["M"]!, scene.trains["S"]!, scene.trains["F"]!)
        XCTAssertTrue(scene.world.isFollowing(try XCTUnwrap(scene.world.train(id: f))), "F follows S")
        scene.world.setSpeed(.x1)
        try scene.world.advance(ticks: 900)
        XCTAssertNil(scene.world.train(id: d)?.execution, "D has no service")
        XCTAssertEqual(scene.world.stationsStoppedAt(by: d), [scene.stations["P2"]!])
        XCTAssertEqual(scene.world.trainHoldingRoute(of: f), s)
        XCTAssertEqual(scene.world.trainHoldingRoute(of: s), m)
        XCTAssertEqual(scene.world.trainHoldingRoute(of: m), d)
        XCTAssertEqual(scene.world.deadlockedTrains(), [d, m, s, f])
    }

    /// Before, the four stood all day: D had no service for decision 577
    /// to send, and K no free berth for TYMCLIST7's way out. Now D is put
    /// on its run and leaves for K past F's claim, M takes its berth and S
    /// goes on to R.
    func testATrainBetweenRunsLeavesPastAFollowersClaim() throws {
        var scene = try makeScene()
        let (d, m, s) = (scene.trains["D"]!, scene.trains["M"]!, scene.trains["S"]!)
        var arrived: Set<TrainID> = []
        for _ in 0..<60 {
            try scene.world.advance(ticks: 1)
            for (id, station) in [(d, "K"), (m, "P2"), (s, "R")] where scene.world.stationsStoppedAt(by: id).contains(scene.stations[station]!) {
                arrived.insert(id)
            }
            XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
        }
        XCTAssertEqual(arrived, [d, m, s])
        XCTAssertEqual(scene.world.deadlockedTrains(), [])
    }

    /// A batch of minutes ends where minute by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var minutes = try makeScene()
        var batch = try makeScene()
        for _ in 0..<60 { try minutes.world.advance(ticks: 1) }
        try batch.world.advance(ticks: 60)
        XCTAssertEqual(minutes.world, batch.world)
    }
}
