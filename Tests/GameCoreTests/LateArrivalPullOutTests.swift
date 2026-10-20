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
///   B ──e0 (1.5 km)── A ──e1 (5.6 km)── D (Depot)
///
/// B's platform is on `e0`, A's on `e0` and on `e1`, D's on `e1`; edge
/// `en` is `.edge(n + 1)`.
final class LateArrivalPullOutTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge + 1), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let b: StationID
        let depot: StationID
        let t1: TrainID
        let t2: TrainID
    }

    /// At 10:00, the line Main from B to A with a run from B to A at 10:00
    /// and one from A to B at 10:15, and the depot D beyond A. T1, Main's,
    /// at B, tops out at 5 km/h and reaches A at about 10:17; T2, Main's,
    /// in D, would be there four minutes after it set out. Under traffic
    /// control.
    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 466_944, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 98_304, y: 8_192))
        let d = try world.buildTrackNode(at: WorldCoordinate(x: 458_752, y: 8_192))
        try world.buildTrackEdge(from: start, to: a) // e0
        try world.buildTrackEdge(from: a, to: d)     // e1
        let first = try XCTUnwrap(world.trackEdge(.edge(1))?.length)
        let second = try XCTUnwrap(world.trackEdge(.edge(2))?.length)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 4_096, y: 10_240)).id
        try world.addTrackPlatform(b, on: .edge(1), from: 1_024, to: 9_216)
        let aStation = try world.buildStation(named: "A", at: PlanPoint(x: 98_304, y: 10_240)).id
        try world.addTrackPlatform(aStation, on: .edge(1), from: first - 10_240, to: first - 2_048)
        try world.addTrackPlatform(aStation, on: .edge(2), from: 2_048, to: 10_240)
        let depot = try world.buildStation(named: "D", at: PlanPoint(x: 452_608, y: 10_240)).id
        try world.addTrackPlatform(depot, on: .edge(2), from: second - 10_240, to: second - 2_048)
        try world.setStationDepot(depot, to: true)
        let line = try world.createLine(named: "Main", stops: [b, aStation]).id
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 1, times: [
                LineRunTime(arrival: 600 * 60, departure: 600 * 60), LineRunTime(arrival: 605 * 60, departure: 605 * 60),
            ]),
            LineRun(from: 1, to: 0, times: [
                LineRunTime(arrival: 615 * 60, departure: 615 * 60), LineRunTime(arrival: 620 * 60, departure: 620 * 60),
            ]),
        ])
        try world.setLineDepots(line, to: [depot])
        var trains: [TrainID] = []
        for (name, edge, at) in [("T1", 0, Int64(9_216)), ("T2", 1, second - 2_048)] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: at))
            try world.setTrainContinuation(id, along: [], stoppingAt: at)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            trains.append(id)
        }
        try world.setTrainPerformance(trains[0], to: TrainPerformance(acceleration: 1_500, braking: 2_500, topSpeed: 5))
        try world.setTrafficControl(true)
        return Scene(world: world, b: b, depot: depot, t1: trains[0], t2: trains[1])
    }

    /// T1 runs twelve minutes late and reaches A before a run out of the
    /// depot could: T2 stays in the depot, and T1 takes the 10:15 run.
    /// Before, T2 came out at 10:17, as T1 arrived, and went back in.
    func testALateTrainOnItsWayTakesTheRunBeforeARunOutThatArrivesAfterIt() throws {
        var scene = try makeScene()
        var pullOuts = 0
        var running = false
        var t1Ends: Set<StationID> = []
        for _ in 0..<30 {
            try scene.world.advance(ticks: 1)
            let t2 = try XCTUnwrap(scene.world.train(id: scene.t2))
            let out = t2.execution != nil && t2.timetable.first?.station == scene.depot
            if out, !running { pullOuts += 1 }
            running = out
            if let last = try XCTUnwrap(scene.world.train(id: scene.t1)).timetable.last { t1Ends.insert(last.station) }
        }
        XCTAssertEqual(pullOuts, 0)
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t2).contains(scene.depot), "T2 stays in the depot")
        XCTAssertTrue(t1Ends.contains(scene.b), "T1 takes the run back to B")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The trains move at whole minutes, so a batch ends where minute by
    /// minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var scene = try makeScene()
        try scene.world.advance(ticks: 12)
        var single = scene.world
        for _ in 0..<28 { try single.advance(ticks: 1) }
        var batched = scene.world
        try batched.advance(ticks: 28)
        XCTAssertEqual(batched, single)
    }
}
