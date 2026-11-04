@testable import GameCore
import XCTest

/// Decision 577: a train following others (Stage U2) claims the rest of its
/// route, which no other train may take (decision 56, point 6), as far as
/// its route goes, even over track it crosses against the way other trains
/// run. On the Taoyuan Airport MRT under simple rules with traffic control
/// (decision 556, continued), an empty train bound for Luzhu depot, still
/// past Linkou behind trains waiting for a service at Kengkou, claimed the
/// track it would cross into the depot, which that service needed to leave
/// Kengkou: each waited for the other all day. Once nothing else frees such
/// a deadlock, the service takes its route whole all the same.
final class FollowerClaimDeadlockTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    //                         ╭─e6── b1 ──e7── b2 ──e8─╮      the loop, P2 on e7
    //   w0 ─e1─ wX ─e2─ wZ ─e3─ wY ──────────e4─────────── wP ─e5─ wR   y = 8192
    //   K      ╱          ╲ e11                                R
    //   a0 ─e9─ c          dp                                           y = 12032
    //      Q
    //
    // e10 crosses over from c to wX; e11 leads from wZ to a depot, dp. The
    // service D stands at P2 heading west for K, over e2. M stands at R
    // heading west for P2, where D stands. S stands at Q bound for R, over
    // the crossover, where M stands. The empty train F follows behind S,
    // bound for the depot over the crossover, e2 and e11: it claims e2,
    // which D needs. Each waits for the next: D for F, F for S, S for M
    // and M for D. Only F's claim keeps D, and F does not follow M (as in
    // decision 308): it is not on F's way.
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
        // D and M head west from the near ends of their platforms, S east;
        // F stands behind S on e9.
        for (name, traversal, offset) in [("D", backward(7), e7 - 16_384), ("M", backward(5), e5 - 98_304),
                                          ("S", forward(9), Int64(49_152)), ("F", forward(9), 16_384)] {
            let id = trains[name]!
            try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
        }
        for (name, from, to) in [("D", "P2", "K"), ("M", "R", "P2"), ("S", "Q", "R")] {
            try world.setTrainTimetable(trains[name]!, to: [
                ScheduledStop(station: stations[from]!, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
                ScheduledStop(station: stations[to]!, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
            ])
        }
        try world.setTrafficControl(true)
        // F sets off for the depot following S, holding its route only a
        // little way: what a departure behind S would have left it.
        var train = try XCTUnwrap(world.train(id: trains["F"]!))
        train.movement.edges = [.edge(10), .edge(2), .edge(11)]
        train.movement.end = try XCTUnwrap(world.trackEdge(.edge(11))?.length) - 2_048
        train.movement.cursor = 0
        train.reservation = world.authorityEnvelope(of: train, to: 2_048).sorted()
        world = world.replacing(train)
        for name in ["D", "M", "S"] {
            try world.startTrainService(trains[name]!)
        }
        return (world, trains, stations)
    }

    func testAServiceAFollowersClaimKeepsInADeadlockLeavesAllTheSame() throws {
        var (world, trains, stations) = try makeWorld()
        let (d, m, s, f) = (trains["D"]!, trains["M"]!, trains["S"]!, trains["F"]!)
        XCTAssertTrue(world.isFollowing(try XCTUnwrap(world.train(id: f))), "F follows S")
        // 0:01:30, second by second: all three are due, and F has come up
        // behind S. D waits for the track F claims, F for S, S for M and M
        // for D: a deadlock, with no passing place, spare or short turn.
        world.setSpeed(.x1)
        try world.advance(ticks: 900)
        XCTAssertEqual(world.trainHoldingRoute(of: d), f)
        XCTAssertEqual(world.trainHoldingRoute(of: f), s)
        XCTAssertEqual(world.trainHoldingRoute(of: s), m)
        XCTAssertEqual(world.trainHoldingRoute(of: m), d)
        XCTAssertEqual(world.deadlockedTrains(), [d, m, s, f])
        world.setSpeed(.normal)
        var arrived: Set<TrainID> = []
        for _ in 0..<60 {
            try world.advance(ticks: 1)
            for (id, station) in [(d, "K"), (m, "P2"), (s, "R")] where world.stationsStoppedAt(by: id).contains(stations[station]!) {
                arrived.insert(id)
            }
        }
        XCTAssertEqual(arrived, [d, m, s], "D leaves P2 for K, M takes its berth, S goes on to R")
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertFalse(world.isFollowing(try XCTUnwrap(world.train(id: f))), "F has its whole route")
    }
}
