@testable import GameCore
import XCTest

/// Decision 306: under traffic control with block sections, a late train
/// of a line with runs runs its next leg in the time left to its
/// scheduled arrival, as with traffic control off (decision 228): it
/// makes up what it can, no faster than it can go. Decision 308: without
/// block sections too; before, it kept the leg's scheduled time.
///
///   B ──e0── M ──e1── A
///
/// B's and M's platforms are on `e0`, A's on `e1`; edge `en` is
/// `.edge(n + 1)`.
final class TrafficControlCatchUpTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge + 1), direction: .forward)
    }

    /// At 10:00, the line Main from B by M to A with a run from B at 10:00
    /// (M 10:02, A 10:05). T1, Main's, at B; T0, of no line, standing on
    /// `e1`, so T1 waits at M for its route until T0 goes. Under traffic
    /// control, with block sections or without.
    private func makeWorld(blockSections: Bool) throws -> (world: GameWorld, a: StationID, t0: TrainID, t1: TrainID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 106_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let m = try world.buildTrackNode(at: WorldCoordinate(x: 49_152, y: 8_192))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 98_304, y: 8_192))
        try world.buildTrackEdge(from: start, to: m) // e0
        try world.buildTrackEdge(from: m, to: a)     // e1
        let lengths = try (1...2).map { try XCTUnwrap(world.trackEdge(.edge($0))?.length) }
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 4_096, y: 10_240)).id
        try world.addTrackPlatform(b, on: .edge(1), from: 1_024, to: 9_216)
        let mStation = try world.buildStation(named: "M", at: PlanPoint(x: 45_056, y: 10_240)).id
        try world.addTrackPlatform(mStation, on: .edge(1), from: lengths[0] - 10_240, to: lengths[0] - 2_048)
        let aStation = try world.buildStation(named: "A", at: PlanPoint(x: 98_304, y: 10_240)).id
        try world.addTrackPlatform(aStation, on: .edge(2), from: lengths[1] - 10_240, to: lengths[1] - 2_048)
        let line = try world.createLine(named: "Main", stops: [b, mStation, aStation]).id
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 2, times: [
                LineRunTime(arrival: 600 * 60, departure: 600 * 60), LineRunTime(arrival: 602 * 60, departure: 602 * 60),
                LineRunTime(arrival: 605 * 60, departure: 605 * 60),
            ]),
        ])
        var trains: [TrainID] = []
        for (name, edge, at, onLine) in [("T0", 1, lengths[1] / 2, false), ("T1", 0, Int64(9_216), true)] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: at))
            try world.setTrainContinuation(id, along: [], stoppingAt: at)
            try world.setTrainMovementRate(id, to: 4_096)
            if onLine { try world.assignTrain(id, to: line) }
            trains.append(id)
        }
        try world.setTrafficControl(true)
        world.setBlockSections(blockSections)
        return (world, aStation, trains[0], trains[1])
    }

    /// T0 goes at 10:14, so T1 leaves M twelve minutes late: the seconds
    /// of its run from M to A, and the minute after 10:14 it first stands
    /// at A.
    private func arrival(blockSections: Bool) throws -> (minute: Int, leg: Int64) {
        var scene = try makeWorld(blockSections: blockSections)
        var leg: Int64?
        for minute in 0..<30 {
            if minute == 14 { try scene.world.unplaceTrain(scene.t0) }
            try scene.world.advance(ticks: 1)
            let t1 = try XCTUnwrap(scene.world.train(id: scene.t1))
            if case .travellingToStop(2, _) = t1.execution, leg == nil { leg = t1.times?.run?.seconds }
            if minute >= 14, scene.world.stationsStoppedAt(by: scene.t1).contains(scene.a) {
                return (minute - 14, try XCTUnwrap(leg))
            }
        }
        XCTFail("T1 never reached A")
        return (.max, .max)
    }

    func testALateTrainMakesUpTimeWithBlockSections() throws {
        let caught = try arrival(blockSections: true)
        // Not its three scheduled minutes: as fast as it can.
        XCTAssertLessThan(caught.leg, 180)
    }

    /// Decision 308: without block sections the same.
    func testALateTrainMakesUpTimeWithoutBlockSections() throws {
        let caught = try arrival(blockSections: true)
        let free = try arrival(blockSections: false)
        XCTAssertLessThan(free.leg, 180)
        XCTAssertEqual(free.leg, caught.leg)
        XCTAssertEqual(free.minute, caught.minute)
    }

    /// The trains move at whole minutes, so a batch ends where minute by
    /// minute does.
    func testABatchEndsWhereMinutesDo() throws {
        for blockSections in [true, false] {
            var scene = try makeWorld(blockSections: blockSections)
            try scene.world.advance(ticks: 14)
            try scene.world.unplaceTrain(scene.t0)
            var single = scene.world
            for _ in 0..<10 { try single.advance(ticks: 1) }
            var batched = scene.world
            try batched.advance(ticks: 10)
            XCTAssertEqual(batched, single, "block sections \(blockSections)")
        }
    }
}
