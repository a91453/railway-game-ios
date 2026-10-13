@testable import GameCore
import XCTest

/// Two trains that follow the same train (Stage U2) on routes that meet
/// (decision 56, point 6, as amended 2026-10-13): each one's claim, the
/// rest of its route that no train holds, kept the other from the track
/// where they meet, so neither ever took it and both waited for ever. The
/// lower ID now goes first; the other follows it.
final class FollowerDeadlockTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    //   j0 ──s── J ──a── A      s: (1024, 8192) to J (65536, 8192), 64512
    //             ╲
    //              b── B        b: J to (131072, 12032), 1 in 17 off a
    //
    // a and b both join s at J but not each other: their ends at J foul
    // it. The leader runs west along s from just past J; the two others
    // come west along a and b behind it, to J and on along s.
    private func makeWorld() throws -> (world: GameWorld, leader: TrainID, first: TrainID, second: TrainID) {
        var world = try GameWorld(bounds: WorldBounds(width: 135_168, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
                                  clock: GameClock(speed: .normal))
        let j0 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let junction = try world.buildTrackNode(at: WorldCoordinate(x: 65_536, y: 8_192))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 131_072, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 131_072, y: 12_032))
        try world.buildTrackEdge(from: j0, to: junction)
        try world.buildTrackEdge(from: junction, to: a)
        try world.buildTrackEdge(from: junction, to: b)
        var ids: [TrainID] = []
        for name in ["L", "F", "G"] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            ids.append(id)
        }
        let (leader, first, second) = (ids[0], ids[1], ids[2])
        let length = try XCTUnwrap(world.train(id: leader)?.length)
        let a2 = try XCTUnwrap(world.trackEdge(.edge(2))?.length), b3 = try XCTUnwrap(world.trackEdge(.edge(3))?.length)
        // The leader's tail just past J; the others 30000 short of it.
        try world.placeTrain(leader, at: .onEdge(backward(1), offset: length + 512))
        try world.placeTrain(first, at: .onEdge(backward(2), offset: a2 - 30_000))
        try world.placeTrain(second, at: .onEdge(backward(3), offset: b3 - 30_000))
        // Standing, traffic control takes nothing they share.
        try world.setTrainContinuation(first, along: [], stoppingAt: a2 - 30_000)
        try world.setTrainContinuation(second, along: [], stoppingAt: b3 - 30_000)
        try world.setTrainContinuation(leader, along: [], stoppingAt: 63_000)
        for id in ids {
            try world.setTrainMovementRate(id, to: 4_096)
        }
        try world.setTrafficControl(true)
        // Then each sets off along s following the leader, holding its
        // route only part of the way, short of J: what a departure behind
        // the leader would have left them.
        for (id, stop) in [(first, Int64(34_000)), (second, Int64(2_048))] {
            var train = try XCTUnwrap(world.train(id: id))
            train.movement.edges = [.edge(1)]
            train.movement.end = stop
            train.movement.cursor = 0
            train.reservation = world.authorityEnvelope(of: train, to: 2_048).sorted()
            world = world.replacing(train)
        }
        return (world, leader, first, second)
    }

    func testTwoTrainsFollowingOneWhoseRoutesMeetBothGoOn() throws {
        var (world, leader, first, second) = try makeWorld()
        for id in [first, second] {
            XCTAssertTrue(world.isFollowing(try XCTUnwrap(world.train(id: id))), "\(id) follows")
            XCTAssertFalse(world.reservedResources(of: id).contains(.node(.node(2))), "\(id) holds short of J")
        }
        // Minute by minute: no two trains ever hold the same track, and
        // the lower ID takes J first.
        var firstAtJunction: TrainID?
        for minute in 0..<90 {
            try world.advance(ticks: 1)
            let held = [leader, first, second].map { Set(world.heldResources(of: $0)) }
            XCTAssertTrue(held[0].isDisjoint(with: held[1]) && held[0].isDisjoint(with: held[2]) && held[1].isDisjoint(with: held[2]), "minute \(minute)")
            if firstAtJunction == nil, let holder = [first, second].first(where: { world.heldResources(of: $0).contains(.node(.node(2))) }) {
                firstAtJunction = holder
            }
        }
        XCTAssertEqual(firstAtJunction, first, "the lower ID goes first")
        XCTAssertEqual(world.train(id: leader)?.position, .onEdge(backward(1), offset: 63_000))
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(backward(1), offset: 34_000))
        XCTAssertEqual(world.train(id: second)?.position, .onEdge(backward(1), offset: 2_048))
    }
}
