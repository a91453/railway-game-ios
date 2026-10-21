@testable import GameCore
import XCTest

/// Decision 308: without block sections, a following train's claim (Stage
/// U2, decision 56) no longer keeps a train from the track it waits for
/// when that train holds track the train it follows needs. In the
/// high-speed demo THSR 19 stood at Tainan's main platform, its way out
/// south claimed by THSR 31, which followed THSR 3 towards the loop;
/// THSR 3 waited for THSR 19's platform. None of the three ever moved.
final class FollowerReleaseTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    //   n0 ──e1── P ──────e2────── Q ──e6── z
    //               ╲            ╱
    //                e3── e4 ──e5
    //
    // All east, each train following (Stage U2), holding only where it
    // stands. X stands on e2 just past P and goes on along e6. L, on e1,
    // goes to where X stands, so it can come no nearer than
    // ``GameWorld/followingGap`` behind X, short of P. A, on e1 behind L,
    // goes by the loop (e3, e4, e5) to Q and along e6: it waits for Q and e6,
    // which X needs too, and IDs A < L < X.
    private func makeWorld() throws -> (world: GameWorld, a: TrainID, l: TrainID, x: TrainID) {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
                                  clock: GameClock(speed: .normal))
        let n0 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let p = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: 8_192))
        let q = try world.buildTrackNode(at: WorldCoordinate(x: 98_304, y: 8_192))
        let r = try world.buildTrackNode(at: WorldCoordinate(x: 71_680, y: 8_704))
        let s = try world.buildTrackNode(at: WorldCoordinate(x: 88_064, y: 8_704))
        let z = try world.buildTrackNode(at: WorldCoordinate(x: 129_024, y: 8_192))
        try world.buildTrackEdge(from: n0, to: p) // e1
        try world.buildTrackEdge(from: p, to: q)  // e2
        try world.buildTrackEdge(from: p, to: r)  // e3
        try world.buildTrackEdge(from: r, to: s)  // e4
        try world.buildTrackEdge(from: s, to: q)  // e5
        try world.buildTrackEdge(from: q, to: z)  // e6
        let e1 = try XCTUnwrap(world.trackEdge(.edge(1))?.length)
        let e6 = try XCTUnwrap(world.trackEdge(.edge(6))?.length)
        var ids: [TrainID] = []
        for name in ["A", "L", "X"] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            ids.append(id)
        }
        let (a, l, x) = (ids[0], ids[1], ids[2])
        let length = try XCTUnwrap(world.train(id: l)?.length)
        let places: [(TrainID, Int, Int64)] = [(a, 1, e1 - 20_000 - length - 26_000), (l, 1, e1 - 20_000), (x, 2, 16_384)]
        for (id, edge, offset) in places {
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 16_384)
        }
        try world.setTrafficControl(true)
        for (id, edges, end) in [(a, [3, 4, 5, 6], Int64(12_288)), (l, [2], Int64(16_384)), (x, [6], e6 - 2_048)] {
            var train = try XCTUnwrap(world.train(id: id))
            train.movement.edges = edges.map { .edge($0) }
            train.movement.end = end
            train.movement.cursor = 0
            train.reservation = world.authorityEnvelope(of: train, to: 0).sorted()
            world = world.replacing(train)
        }
        return (world, a, l, x)
    }

    func testATrainInTheWayOfTheTrainAheadIsNotHeldByTheFollowersClaim() throws {
        var (world, a, l, x) = try makeWorld()
        for id in [a, l, x] {
            XCTAssertTrue(world.isFollowing(try XCTUnwrap(world.train(id: id))), "\(id) follows")
        }
        for minute in 0..<60 {
            try world.advance(ticks: 1)
            let held = [x, l, a].map { Set(world.heldResources(of: $0)) }
            XCTAssertTrue(held[0].isDisjoint(with: held[1]) && held[0].isDisjoint(with: held[2]) && held[1].isDisjoint(with: held[2]), "minute \(minute)")
        }
        let e6 = try XCTUnwrap(world.trackEdge(.edge(6))?.length)
        // Before, X waited for A's claim, L behind X, and A behind L, for
        // ever: a deadlock.
        XCTAssertEqual(world.train(id: x)?.position, .onEdge(forward(6), offset: e6 - 2_048))
        XCTAssertEqual(world.train(id: l)?.position, .onEdge(forward(2), offset: 16_384))
        XCTAssertEqual(world.train(id: a)?.position, .onEdge(forward(6), offset: 12_288))
        XCTAssertEqual(world.deadlockedTrains(), [])
    }

    /// A batch ends where minute by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        let start = try makeWorld().world
        var single = start
        for _ in 0..<60 { try single.advance(ticks: 1) }
        var batched = start
        try batched.advance(ticks: 60)
        XCTAssertEqual(batched, single)
    }
}
