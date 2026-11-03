@testable import GameCore
import XCTest

/// Decision 562: with block sections a train following others holds only
/// the track it has taken (decision 212), so another train could join its
/// route ahead of it. When that train ended its service, or turned round,
/// at a berth on the follower's route, the follower could never follow it
/// (``GameWorld/isLeading(_:onto:for:)``) and waited behind it for good:
/// the Taoyuan Airport MRT's 18 and 29 at Airport Terminal 2 (decision
/// 556), 18 turning back over the crossover 29 stood on.
///
///   n5 ──e4──╮
///   n1 ──e1── J ──e2── n3 ──e3── n4
///   (S1: F on e4, C on e1)   (LA and S2 on e2, S3 and LZ on e3)
///
/// L leaves LA for LZ at 1:00 and takes its route whole. F leaves S1's
/// side berth at 1:00 for S2 and S3, following L; C leaves S1's main berth
/// at 1:05 for S2, where its service ends, following L too. C has the
/// lower number, so it took the junction first and stood at S2 for good,
/// F behind it. Now C waits at S1 until F has gone by.
final class FollowerCutOffTests: XCTestCase {
    private static let edgeLength: Int64 = 200_000

    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let s1: StationID
        let leader: TrainID
        let cutting: TrainID
        let follower: TrainID
        let s2: StationID
        let s3: StationID
        let la: StationID
    }

    private func makeScene() throws -> Scene {
        let length = Self.edgeLength
        var world = try GameWorld(
            bounds: WorldBounds(width: 3 * length + 4_096, height: 16_384), economy: fixtureEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 4_096))
        let junction = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + length, y: 4_096))
        let n3 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + 2 * length, y: 4_096))
        let n4 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + 3 * length, y: 4_096))
        let n5 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 14_336))
        try world.buildTrackEdge(from: n1, to: junction)  // e1
        try world.buildTrackEdge(from: junction, to: n3)  // e2
        try world.buildTrackEdge(from: n3, to: n4)        // e3
        try world.buildTrackEdge(from: n5, to: junction)  // e4
        let e4 = try XCTUnwrap(world.trackEdge(.edge(4))?.length)
        let s1 = try world.buildStation(named: "S1", at: PlanPoint(x: 1_024 + length - 20_000, y: 8_192)).id
        try world.addTrackPlatform(s1, on: .edge(1), from: length - 40_000, to: length - 20_000)
        try world.addTrackPlatform(s1, on: .edge(4), from: e4 - 40_000, to: e4 - 20_000)
        let la = try world.buildStation(named: "LA", at: PlanPoint(x: 1_024 + length + 40_000, y: 2_048)).id
        try world.addTrackPlatform(la, on: .edge(2), from: 30_000, to: 50_000)
        let s2 = try world.buildStation(named: "S2", at: PlanPoint(x: 1_024 + 2 * length - 20_000, y: 2_048)).id
        try world.addTrackPlatform(s2, on: .edge(2), from: length - 40_000, to: length - 20_000)
        let s3 = try world.buildStation(named: "S3", at: PlanPoint(x: 1_024 + 2 * length + 70_000, y: 2_048)).id
        try world.addTrackPlatform(s3, on: .edge(3), from: 60_000, to: 80_000)
        let lz = try world.buildStation(named: "LZ", at: PlanPoint(x: 1_024 + 3 * length - 20_000, y: 2_048)).id
        try world.addTrackPlatform(lz, on: .edge(3), from: length - 40_000, to: length - 20_000)
        world.setBlockSections(true)

        func service(_ name: String, on edge: Int, at end: Int64, _ calls: [(StationID, Int64, Int64)]) throws -> TrainID {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: end))
            try world.setTrainMovementRate(id, to: 4_096)
            try world.setTrainContinuation(id, along: [], stoppingAt: end)
            try world.setTrainTimetable(id, to: calls.map {
                ScheduledStop(station: $0.0, arrival: GameTime(seconds: $0.1), departure: GameTime(seconds: $0.2))
            })
            return id
        }
        let leader = try service("L", on: 2, at: 50_000, [(la, 0, 60), (lz, 1_800, 1_800)])
        let cutting = try service("C", on: 1, at: length - 20_000, [(s1, 0, 65), (s2, 1_200, 1_200)])
        let follower = try service("F", on: 4, at: e4 - 20_000, [(s1, 0, 60), (s2, 1_200, 1_260), (s3, 2_400, 2_400)])
        try world.setTrafficControl(true)
        for id in [leader, cutting, follower] {
            try world.startTrainService(id)
        }
        return Scene(world: world, s1: s1, leader: leader, cutting: cutting, follower: follower, s2: s2, s3: s3, la: la)
    }

    /// F calls at S2 and S3; C, held at S1 until F has gone by, then ends
    /// its service at S2. Before decision 562 C took the junction ahead of
    /// F and F stood behind it for good, never reaching S2. No two trains
    /// ever hold the same track.
    func testATrainEndingItsServiceDoesNotCutInAheadOfAFollower() throws {
        var scene = try makeScene()
        scene.world.setSpeed(.x10)
        var followerAt: [StationID] = []
        var cuttingLeft: GameTime?
        for second in 0..<3_600 {
            try scene.world.advance(ticks: 1)
            for station in scene.world.stationsStoppedAt(by: scene.follower) where station != scene.s1 && followerAt.last != station {
                followerAt.append(station)
            }
            if cuttingLeft == nil, case .travellingToStop? = scene.world.train(id: scene.cutting)?.execution {
                cuttingLeft = scene.world.clock.now
            }
            let held = [scene.leader, scene.cutting, scene.follower].map { Set(scene.world.heldResources(of: $0)) }
            XCTAssertTrue(held[0].isDisjoint(with: held[1]) && held[0].isDisjoint(with: held[2]) && held[1].isDisjoint(with: held[2]),
                          "second \(second)")
            if [scene.leader, scene.cutting, scene.follower].allSatisfy({ scene.world.train(id: $0)?.execution == nil }) { break }
        }
        XCTAssertEqual(followerAt, [scene.s2, scene.s3], "F calls at S2 and S3")
        XCTAssertNil(scene.world.train(id: scene.follower)?.execution, "F's service is done")
        XCTAssertNil(scene.world.train(id: scene.cutting)?.execution, "C's service is done")
        XCTAssertEqual(scene.world.stationsStoppedAt(by: scene.cutting), [scene.s2], "C ends at S2")
        XCTAssertGreaterThan(try XCTUnwrap(cuttingLeft).seconds, 65, "C waited for F")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The rule itself, at 1:06: F follows L, and C, ending its service at
    /// S2 on F's route, is held by F. Going on from S2 to S3 it could be
    /// followed, and is not held. O, at S3 bound west for S2 and LA, runs
    /// along F's route the other way, and is held by F.
    func testOnlyATrainTheFollowerCouldNeverFollowIsHeld() throws {
        var scene = try makeScene()
        let o = try scene.world.purchaseTrain(named: "O").id
        try scene.world.setTrainCars(o, to: 2)
        let back = TrackTraversal(edge: .edge(3), direction: .backward)
        try scene.world.placeTrain(o, at: .onEdge(back, offset: Self.edgeLength - 60_000))
        try scene.world.setTrainMovementRate(o, to: 4_096)
        try scene.world.setTrainContinuation(o, along: [], stoppingAt: Self.edgeLength - 60_000)
        try scene.world.setTrainTimetable(o, to: [
            ScheduledStop(station: scene.s3, arrival: GameTime(seconds: 0), departure: GameTime(seconds: 3_000)),
            ScheduledStop(station: scene.s2, arrival: GameTime(seconds: 3_300), departure: GameTime(seconds: 3_360)),
            ScheduledStop(station: scene.la, arrival: GameTime(seconds: 3_600), departure: GameTime(seconds: 3_600)),
        ])
        try scene.world.startTrainService(o)
        scene.world.setSpeed(.x1)
        try scene.world.advance(ticks: 10 * 66)
        let follower = try XCTUnwrap(scene.world.train(id: scene.follower))
        XCTAssertTrue(scene.world.isFollowing(follower), "F follows L")
        let cutting = try XCTUnwrap(scene.world.train(id: scene.cutting))
        XCTAssertEqual(cutting.execution, .waitingAtStop(0, cycle: 0), "C has not left")
        var memo = GameWorld.DirectionMemo()
        let leaving = try XCTUnwrap(scene.world.departureRequest(of: cutting, memo: &memo))
        XCTAssertEqual(scene.world.followerCutOff(by: leaving, memo: &memo), scene.follower)
        guard case .held(let by) = scene.world.reserving(leaving, following: true, memo: &memo) else { return XCTFail("C is held") }
        XCTAssertEqual(by, scene.follower)

        var goingOn = leaving
        goingOn.timetable.append(ScheduledStop(station: scene.s3, arrival: GameTime(seconds: 2_000), departure: GameTime(seconds: 2_000)))
        XCTAssertNil(scene.world.followerCutOff(by: goingOn, memo: &memo), "C going on from S2")

        // O as it would set off at 50:00, at 1:06.
        var westbound = try XCTUnwrap(scene.world.train(id: o))
        XCTAssertEqual(westbound.execution, .waitingAtStop(0, cycle: 0))
        let path = try XCTUnwrap(scene.world.path(from: try XCTUnwrap(westbound.position), toStation: scene.s2))
        scene.world.follow(path, &westbound)
        westbound.execution = .travellingToStop(1, cycle: 0)
        XCTAssertEqual(scene.world.followerCutOff(by: westbound, memo: &memo), scene.follower, "O comes at F")
    }
}
