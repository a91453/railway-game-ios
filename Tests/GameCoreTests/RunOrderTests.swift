import Foundation
@testable import GameCore
import XCTest

/// Decision 297: under traffic control a line with runs sends out the
/// train that came in first, and sends the one that came in last to the
/// depot when there is one too many: the train that reached the end takes
/// the next run from there, and the one with the longest wait goes in.
/// With traffic control off, the order stays the trains' IDs.
///
///                      ┌──e1── PA1 ──e3──┐
///   B ──e0──────────── J                 J2 ──e5── D (Depot)
///                      └──e2── PA2 ──e4──┘
///
/// A's platforms are on `e1` and `e2`; edge `en` is `.edge(n + 1)`.
final class RunOrderTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let a: StationID
        let depot: StationID
        /// T1 runs the 10:00 from B, reaching A at 10:10.
        let t1: TrainID
        /// T2 stands at A from the start, never sent anywhere.
        let t2: TrainID
    }

    /// At 10:00, the line Main from B to A with runs from B at 10:00 and
    /// from A at 11:00, and the depot D; T1 at B, T2 at PA1.
    private func makeScene(trafficControl: Bool) throws -> Scene {
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
        func run(_ from: Int, _ to: Int, at minute: Int64) -> LineRun {
            LineRun(from: from, to: to, times: [
                LineRunTime(arrival: minute * 60, departure: minute * 60), LineRunTime(arrival: (minute + 10) * 60, departure: (minute + 10) * 60),
            ])
        }
        try world.setLineRuns(line, to: [run(0, 1, at: 600), run(1, 0, at: 660)])
        try world.setLineDepots(line, to: [depot])
        var trains: [TrainID] = []
        // T1 first, so it has the lower ID.
        for (name, edge, offset) in [("T1", 0, Int64(8_192)), ("T2", 1, nil)] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            let length = try XCTUnwrap(world.trackEdge(.edge(edge + 1))?.length)
            let at = offset ?? length - 2_048
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge + 1), direction: .forward), offset: at))
            try world.setTrainContinuation(id, along: [], stoppingAt: at)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            trains.append(id)
        }
        try world.setTrafficControl(trafficControl)
        return Scene(world: world, a: a, depot: depot, t1: trains[0], t2: trains[1])
    }

    /// Under traffic control T1, in last, goes to the depot; T2, in
    /// first, takes the 11:00 run.
    func testTheTrainThatCameInLastGoesToTheDepot() throws {
        var scene = try makeScene(trafficControl: true)
        for _ in 0..<40 { try scene.world.advance(ticks: 1) }
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t1).contains(scene.depot), "T1, in at 10:10, goes in")
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t2).contains(scene.a), "T2 waits for the 11:00")
        for _ in 0..<25 { try scene.world.advance(ticks: 1) }
        XCTAssertEqual(scene.world.train(id: scene.t2)?.timetable.first?.station, scene.a, "T2 runs the 11:00 from A")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// With traffic control off the trains keep their ID order: T2, the
    /// last in ID order, goes in, as before.
    func testWithoutTrafficControlTheOrderIsTheTrainsIDs() throws {
        var scene = try makeScene(trafficControl: false)
        for _ in 0..<40 { try scene.world.advance(ticks: 1) }
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t2).contains(scene.depot))
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t1).contains(scene.a))
    }

    /// The trains move at whole minutes, so a batch ends where minute by
    /// minute does.
    func testABatchEndsWhereMinutesDo() throws {
        let scene = try makeScene(trafficControl: true)
        var single = scene.world
        for _ in 0..<70 { try single.advance(ticks: 1) }
        var batched = scene.world
        try batched.advance(ticks: 70)
        XCTAssertEqual(batched, single)
    }
}
