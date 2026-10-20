import Foundation
@testable import GameCore
import XCTest

/// Decision 296: under traffic control a line with runs no longer shuttles
/// a train between a depot and a stop while a run there waits for its
/// route, and does not send one out of a depot for a run it cannot reach
/// before the run is dropped.
///
/// The high-speed demo built over the ground, with traffic control and
/// block sections: at Nangang the Five Stops' 22:00 run could not take its
/// route, THSR 28 and 29 both standing there for it. Once 22:00 had
/// passed the train waiting counted as too late for it, so THSR 29 came
/// out of the depot; there it was one train too many for the one run, so
/// it went back in, and out again, every three or four minutes until the
/// run left.
///
///                      ┌──e1── PA1 ──e3──┐
///   B ──e0──────────── J                 J2 ──e5── D (Depot)
///                      └──e2── PA2 ──e4──┘
///
/// A's platforms are on `e1` and `e2`; edge `en` is `.edge(n + 1)`.
final class DepotShuttleTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge + 1), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let a: StationID
        let depot: StationID
        let t2: TrainID
    }

    /// At 10:00, the line Main from B to A with a run from A to B at 10:10
    /// and the depot D; T1 Main's at PA1, T2 Main's in D, and T0, of no
    /// line, standing on `e0`, so T1 cannot take the run's route. Under
    /// traffic control, without block sections: T1 does not follow T0.
    private func makeScene(performance: TrainPerformance? = nil) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 106_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        // Each bend at PA1 and PA2 within 1 in 16 of straight on.
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 32_768, y: 8_192))
        let pa1 = try world.buildTrackNode(at: WorldCoordinate(x: 57_344, y: 8_704))
        let pa2 = try world.buildTrackNode(at: WorldCoordinate(x: 57_344, y: 7_680))
        let j2 = try world.buildTrackNode(at: WorldCoordinate(x: 81_920, y: 8_192))
        let d = try world.buildTrackNode(at: WorldCoordinate(x: 104_448, y: 8_192))
        try world.buildTrackEdge(from: start, to: j) // e0
        try world.buildTrackEdge(from: j, to: pa1)   // e1
        try world.buildTrackEdge(from: j, to: pa2)   // e2
        try world.buildTrackEdge(from: pa1, to: j2)  // e3
        try world.buildTrackEdge(from: pa2, to: j2)  // e4
        try world.buildTrackEdge(from: j2, to: d)    // e5
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 4_096, y: 10_240)).id
        try world.addTrackPlatform(b, on: .edge(1), from: 1_024, to: 9_216)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 49_152, y: 8_192)).id
        let depot = try world.buildStation(named: "D", at: PlanPoint(x: 98_304, y: 10_240)).id
        for (station, edge) in [(a, 1), (a, 2), (depot, 5)] {
            let length = try XCTUnwrap(world.trackEdge(.edge(edge + 1))?.length)
            try world.addTrackPlatform(station, on: .edge(edge + 1), from: length - 10_240, to: length - 2_048)
        }
        try world.setStationDepot(depot, to: true)
        let line = try world.createLine(named: "Main", stops: [b, a]).id
        if let performance { try world.setLinePerformance(line, to: performance) }
        try world.setLineRuns(line, to: [LineRun(from: 1, to: 0, times: [
            LineRunTime(arrival: 610 * 60, departure: 610 * 60), LineRunTime(arrival: 630 * 60, departure: 630 * 60),
        ])])
        try world.setLineDepots(line, to: [depot])
        var trains: [TrainID] = []
        for (name, edge, onLine) in [("T0", 0, false), ("T1", 1, true), ("T2", 5, true)] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            let length = try XCTUnwrap(world.trackEdge(.edge(edge + 1))?.length)
            let offset = edge == 0 ? length / 2 : length - 2_048
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
            if onLine { try world.assignTrain(id, to: line) }
            trains.append(id)
        }
        try world.setTrafficControl(true)
        return Scene(world: world, a: a, depot: depot, t2: trains[2])
    }

    /// How many times T2 is sent out of the depot, minute by minute until
    /// `minutes` past 10:00, and where it stands then.
    private func pullOuts(_ scene: inout Scene, until minutes: Int) throws -> Int {
        var count = 0
        var running = false
        for _ in 0..<minutes {
            try scene.world.advance(ticks: 1)
            let train = try XCTUnwrap(scene.world.train(id: scene.t2))
            let out = train.execution != nil && train.timetable.first?.station == scene.depot
            if out, !running { count += 1 }
            running = out
        }
        return count
    }

    /// T2 comes out once the 10:10 run has found no train able to leave,
    /// and then stays at A for it rather than going back in.
    func testATrainOutOfTheDepotForADueRunIsNotSentBackUntilTheRunLeaves() throws {
        var scene = try makeScene()
        XCTAssertEqual(try pullOuts(&scene, until: 25), 1)
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t2).contains(scene.a), "T2 waits at A for the run")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// With the line crawling, a run out of the depot would reach A after
    /// 10:40, when the 10:10 run is dropped: T2 stays in the depot.
    func testNoTrainComesOutOfTheDepotForARunItCannotReachInTime() throws {
        var scene = try makeScene(performance: TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1))
        XCTAssertEqual(try pullOuts(&scene, until: 25), 0)
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t2).contains(scene.depot))
    }

    /// The trains move at whole minutes, so a batch ends where minute by
    /// minute does.
    func testABatchEndsWhereMinutesDo() throws {
        let scene = try makeScene()
        var single = scene.world
        for _ in 0..<40 { try single.advance(ticks: 1) }
        var batched = scene.world
        try batched.advance(ticks: 40)
        XCTAssertEqual(batched, single)
    }
}
