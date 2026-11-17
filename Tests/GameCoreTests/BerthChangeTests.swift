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

    /// `spare` (decision 810): I is a train of a line calling at S and T
    /// that runs none of its trains now, the line's spare.
    private func makeScene(blocks: Bool, spare: Bool = false) throws -> Scene {
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
        if spare {
            try world.setTrainContinuation(idle, along: [], stoppingAt: 36_864)
            try world.setTrainMovementRate(idle, to: 4_096)
            let line = try world.createLine(named: "L", stops: [s, t]).id
            try world.assignTrain(idle, to: line)
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: .none)
            XCTAssertTrue(world.isSpare(try XCTUnwrap(world.train(id: idle))), "I is its line's spare")
        }
        return Scene(world: world, follower: follower, idle: idle, t: t)
    }

    /// Decision 810: where the train on its berth is a spare of its line,
    /// F changes berth while still on its way, at the dispatcher's next
    /// look, and never stops short of T; where it is only a train without
    /// a service (which a player may yet move), F runs on to where its way
    /// ends first, as before (decision 278).
    func testAFollowerBoundForASparesBerthChangesBerthOnItsWay() throws {
        var early = try makeScene(blocks: true, spare: true)
        var late = try makeScene(blocks: true)
        XCTAssertEqual(early.world.clock.now, late.world.clock.now)
        var stoodShort = false, changedMoving = false
        for _ in 0..<60 {
            let before = early.world.train(id: early.follower)
            try early.world.advance(ticks: 1)
            try late.world.advance(ticks: 1)
            XCTAssertEqual(early.world.deadlockedTrains(), [], "at \(early.world.clock.now)")
            let after = try XCTUnwrap(early.world.train(id: early.follower))
            if before?.movement.edges.last == .edge(3), after.movement.edges.last == .edge(4), case .travellingToStop? = after.execution {
                changedMoving = after.position != before?.position
            }
            if case .travellingToStop? = after.execution, after.position == before?.position { stoodShort = true }
            XCTAssertEqual(WorldInvariants.violations(in: early.world), [])
            if early.world.stationsStoppedAt(by: early.follower) == [early.t] { break }
        }
        XCTAssertTrue(changedMoving, "F's way changed to P2 while it was moving")
        XCTAssertFalse(stoodShort, "F never stood short of T")
        XCTAssertEqual(early.world.stationsStoppedAt(by: early.follower), [early.t], "F calls at T")
        guard case .onEdge(let traversal, _)? = early.world.train(id: early.follower)?.position else { return XCTFail("F is placed") }
        XCTAssertEqual(traversal.edge, .edge(4), "at P2")
        XCTAssertEqual(early.world.train(id: early.idle)?.position, .onEdge(forward(3), offset: 36_864), "I has not moved")
        // No later than where it stopped first.
        XCTAssertNotEqual(late.world.stationsStoppedAt(by: late.follower), [late.t], "without a spare it is still on its way then")
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
