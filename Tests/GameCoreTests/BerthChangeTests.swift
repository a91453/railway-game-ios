import Foundation
@testable import GameCore
import XCTest

/// Decision 278: a train following others (Stage U2) towards a berth that
/// a train without a service has come to stand on changes, once a minute,
/// to another berth of the same station. The high-speed demo with traffic
/// control and block sections lost seven sets this way at 08:17: they ran
/// out of Zuoying's depot one behind the other towards the berth the first
/// of them stopped on, and none of the eight moved again all day.
///
///                               ┌──e2── P1 (T)
///   R ──e0── n1 ──e1── J ───────┼──e3── P2 (T)
///         (S on e1)             └──e4───────────── U
///
/// X runs from S to U along e4; F, from R to T, follows it as far as n1,
/// its route ending at P1. Then I, a train without a service, is placed at
/// P1: F can never go on to it.
final class BerthChangeTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let follower: TrainID
        let idle: TrainID
        let t: StationID
    }

    private func makeScene(blocks: Bool) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 106_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let junction = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: 8_192))
        let p1 = try world.buildTrackNode(at: WorldCoordinate(x: 81_920, y: 10_240))
        let p2 = try world.buildTrackNode(at: WorldCoordinate(x: 81_920, y: 6_144))
        let far = try world.buildTrackNode(at: WorldCoordinate(x: 102_400, y: 8_192))
        try world.buildTrackEdge(from: start, to: n1)     // e0
        try world.buildTrackEdge(from: n1, to: junction)  // e1
        try world.buildTrackEdge(from: junction, to: p1)  // e2
        try world.buildTrackEdge(from: junction, to: p2)  // e3
        try world.buildTrackEdge(from: junction, to: far) // e4
        let r = try world.buildStation(named: "R", at: PlanPoint(x: 4_096, y: 6_144)).id
        try world.addTrackPlatform(r, on: .edge(1), from: 1_024, to: 5_120)
        let s = try world.buildStation(named: "S", at: PlanPoint(x: 24_576, y: 6_144)).id
        try world.addTrackPlatform(s, on: .edge(2), from: 4_096, to: 8_192)
        let t = try world.buildStation(named: "T", at: PlanPoint(x: 77_824, y: 8_192)).id
        try world.addTrackPlatform(t, on: .edge(3), from: 28_672, to: 36_864)
        try world.addTrackPlatform(t, on: .edge(4), from: 30_720, to: 38_912)
        let u = try world.buildStation(named: "U", at: PlanPoint(x: 98_304, y: 6_144)).id
        let e4 = try XCTUnwrap(world.trackEdge(.edge(5))?.length)
        try world.addTrackPlatform(u, on: .edge(5), from: e4 - 6_144, to: e4 - 2_048)
        world.setBlockSections(blocks)

        func train(_ name: String, at traversal: TrackTraversal, offset: Int64, from: StationID, to: StationID, leaving minute: Int64) throws -> TrainID {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.setTrainTimetable(id, to: [
                ScheduledStop(station: from, arrival: GameTime(minutes: minute), departure: GameTime(minutes: minute)),
                ScheduledStop(station: to, arrival: GameTime(minutes: minute + 30), departure: GameTime(minutes: minute + 30)),
            ])
            return id
        }
        let leader = try train("X", at: forward(2), offset: 8_192, from: s, to: u, leaving: 1)
        let follower = try train("F", at: forward(1), offset: 5_120, from: r, to: t, leaving: 1)
        try world.setTrafficControl(true)
        try world.startTrainService(leader)
        try world.startTrainService(follower)
        // X takes its whole way first; F follows it.
        while !(world.train(id: follower)?.reservation.isEmpty == false && world.isFollowing(world.train(id: follower)!)) {
            try world.advance(ticks: 1)
            XCTAssertLessThan(world.clock.now, GameTime(minutes: 10), "F sets off following X")
        }
        XCTAssertEqual(world.train(id: follower)?.movement.edges.last, .edge(3), "F's route ends at P1")
        // I comes to stand at P1, without a service.
        let idle = try world.purchaseTrain(named: "I").id
        try world.setTrainCars(idle, to: 2)
        try world.placeTrain(idle, at: .onEdge(forward(3), offset: 36_864))
        return Scene(world: world, follower: follower, idle: idle, t: t)
    }

    /// Before decision 278 F stopped short of I and stayed there: I has no
    /// service and never leaves. Now F goes over to P2 and calls at T.
    func testAFollowerKeptFromItsBerthByATrainWithoutAServiceGoesToAnother() throws {
        var scene = try makeScene(blocks: true)
        var arrived = false
        for _ in 0..<60 {
            try scene.world.advance(ticks: 1)
            if scene.world.stationsStoppedAt(by: scene.follower) == [scene.t] {
                arrived = true
                break
            }
            XCTAssertTrue(Set(scene.world.heldResources(of: scene.follower)).isDisjoint(with: Set(scene.world.heldResources(of: scene.idle))))
        }
        XCTAssertTrue(arrived, "F calls at T")
        guard case .onEdge(let traversal, _)? = scene.world.train(id: scene.follower)?.position else { return XCTFail("F is placed") }
        XCTAssertEqual(traversal.edge, .edge(4), "at P2")
        XCTAssertEqual(scene.world.train(id: scene.idle)?.position, .onEdge(forward(3), offset: 36_864), "I has not moved")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The berth changes at a whole minute, so the whole hour in one call
    /// ends where minute by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        let scene = try makeScene(blocks: true)
        var single = scene.world
        for _ in 0..<60 { try single.advance(ticks: 1) }
        var batched = scene.world
        try batched.advance(ticks: 60)
        XCTAssertEqual(batched, single)
    }
}
