@testable import GameCore
import XCTest

/// Decision 302: under traffic control a train of a line with runs comes
/// out of a depot for a run only when it would stand there before the
/// train on its way to end there does: a late train still takes the run
/// before a run out that arrives after it.
///
/// The high-speed demo built over the ground, with traffic control and
/// block sections: at about 07:40 the All Stops sets on their way north to
/// Nangang ran late, so its runs counted as without a train, and THSR 13
/// ran empty from Wuri, an hour and a half away. By 08:20 three All Stops
/// sets stood idle at Nangang, and Taichung's 08:04 run, which THSR 13
/// would have taken, was dropped.
///
///   B ──e0── M ──e1── A ──e2 (5.6 km)── D (Depot)
///
/// B's and M's platforms are on `e0`, A's on `e1` and on `e2`, D's on
/// `e2`; edge `en` is `.edge(n + 1)`.
final class LateArrivalPullOutTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge + 1), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let a: StationID
        let depot: StationID
        let t0: TrainID
        let t1: TrainID
        let t2: TrainID
    }

    /// At 10:00, the line Main from B by M to A with a run from B at 10:00
    /// (M 10:02, A 10:05) and one from A to B at 10:15, and the depot D
    /// beyond A. T1, Main's, at B; T2, Main's, in D, four minutes from A;
    /// T0, of no line, standing on `e1`, so T1 waits at M for its route.
    /// Under traffic control.
    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 466_944, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let m = try world.buildTrackNode(at: WorldCoordinate(x: 49_152, y: 8_192))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 98_304, y: 8_192))
        let d = try world.buildTrackNode(at: WorldCoordinate(x: 458_752, y: 8_192))
        try world.buildTrackEdge(from: start, to: m) // e0
        try world.buildTrackEdge(from: m, to: a)     // e1
        try world.buildTrackEdge(from: a, to: d)     // e2
        let lengths = try (1...3).map { try XCTUnwrap(world.trackEdge(.edge($0))?.length) }
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 4_096, y: 10_240)).id
        try world.addTrackPlatform(b, on: .edge(1), from: 1_024, to: 9_216)
        let mStation = try world.buildStation(named: "M", at: PlanPoint(x: 45_056, y: 10_240)).id
        try world.addTrackPlatform(mStation, on: .edge(1), from: lengths[0] - 10_240, to: lengths[0] - 2_048)
        let aStation = try world.buildStation(named: "A", at: PlanPoint(x: 98_304, y: 10_240)).id
        try world.addTrackPlatform(aStation, on: .edge(2), from: lengths[1] - 10_240, to: lengths[1] - 2_048)
        try world.addTrackPlatform(aStation, on: .edge(3), from: 2_048, to: 10_240)
        let depot = try world.buildStation(named: "D", at: PlanPoint(x: 452_608, y: 10_240)).id
        try world.addTrackPlatform(depot, on: .edge(3), from: lengths[2] - 10_240, to: lengths[2] - 2_048)
        try world.setStationDepot(depot, to: true)
        let line = try world.createLine(named: "Main", stops: [b, mStation, aStation]).id
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 2, times: [
                LineRunTime(arrival: 600 * 60, departure: 600 * 60), LineRunTime(arrival: 602 * 60, departure: 602 * 60),
                LineRunTime(arrival: 605 * 60, departure: 605 * 60),
            ]),
            LineRun(from: 2, to: 0, times: [
                LineRunTime(arrival: 615 * 60, departure: 615 * 60), LineRunTime(arrival: 618 * 60, departure: 618 * 60),
                LineRunTime(arrival: 620 * 60, departure: 620 * 60),
            ]),
        ])
        try world.setLineDepots(line, to: [depot])
        var trains: [TrainID] = []
        for (name, edge, at, onLine) in [("T0", 1, lengths[1] / 2, false), ("T1", 0, Int64(9_216), true), ("T2", 2, lengths[2] - 2_048, true)] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: at))
            try world.setTrainContinuation(id, along: [], stoppingAt: at)
            try world.setTrainMovementRate(id, to: 4_096)
            if onLine { try world.assignTrain(id, to: line) }
            trains.append(id)
        }
        try world.setTrafficControl(true)
        return Scene(world: world, a: aStation, depot: depot, t0: trains[0], t1: trains[1], t2: trains[2])
    }

    /// T0 leaves at 10:14, so T1 leaves M twelve minutes late and reaches
    /// A at 10:17, before a run out of the depot could: T2 stays in the
    /// depot while T1 is on its way. Before, T2 came out at 10:13, once T1
    /// was due after 10:15.
    func testALateTrainOnItsWayTakesTheRunBeforeARunOutThatArrivesAfterIt() throws {
        var scene = try makeScene()
        var pullOuts = 0
        var running = false
        for minute in 0..<17 {
            if minute == 14 { try scene.world.unplaceTrain(scene.t0) }
            try scene.world.advance(ticks: 1)
            let t2 = try XCTUnwrap(scene.world.train(id: scene.t2))
            let out = t2.execution != nil && t2.timetable.first?.station == scene.depot
            if out, !running { pullOuts += 1 }
            running = out
        }
        XCTAssertEqual(pullOuts, 0)
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t2).contains(scene.depot), "T2 stays in the depot")
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t1).contains(scene.a), "T1 stands at A")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The trains move at whole minutes, so a batch ends where minute by
    /// minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var scene = try makeScene()
        try scene.world.advance(ticks: 14)
        try scene.world.unplaceTrain(scene.t0)
        var single = scene.world
        for _ in 0..<26 { try single.advance(ticks: 1) }
        var batched = scene.world
        try batched.advance(ticks: 26)
        XCTAssertEqual(batched, single)
    }
}
