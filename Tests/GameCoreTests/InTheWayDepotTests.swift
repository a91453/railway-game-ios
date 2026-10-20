@testable import GameCore
import XCTest

/// Decision 297: under traffic control a train of a line with runs,
/// standing without a service in the way of a service waiting for its
/// route, goes into its line's depot while no run from where it stands is
/// due, however soon its next run there is.
///
/// The high-speed demo built flat, with traffic control and block
/// sections: THSR 11 ended its run at Taichung at 08:45 on the inner of
/// its two southbound loops and stood there, its next run within the two
/// hours a waiting train looks ahead (decision 221). Every set calling
/// southbound queued for the other loop; at 10:00 eight of them were
/// deadlocked, THSR 1 at their head bound for THSR 11's loop, and THSR 11
/// could not leave north past them. The depot was a few kilometres south.
///
///   B ── X ──e0 (4.5 km)── J ──e1── PA ── K ──e2── C
///                               └──e3── D (Depot)
///
/// A's one platform is on `e1`, B's and X's on `e0`; edge `en` is `.edge(n + 1)`.
final class InTheWayDepotTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge + 1), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let depot: StationID
        let c: StationID
        let t1: TrainID
        let t3: TrainID
    }

    /// At 10:00, the line Main calling at B, X, A and C, with a run from B
    /// to A at 10:01, one from B to C at 10:05 leaving X at 10:12, one
    /// from A to C at 11:30 and the depot D; T1 and T3, Main's, at B, T1
    /// ahead.
    /// Under traffic control, with block sections.
    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 362_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 288_768, y: 8_192))
        let k = try world.buildTrackNode(at: WorldCoordinate(x: 313_344, y: 8_192))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 337_920, y: 8_192))
        // Within 1 in 16 of straight on from `e1`.
        let d = try world.buildTrackNode(at: WorldCoordinate(x: 360_448, y: 9_216))
        try world.buildTrackEdge(from: start, to: j) // e0
        try world.buildTrackEdge(from: j, to: k)     // e1
        try world.buildTrackEdge(from: k, to: c)     // e2
        try world.buildTrackEdge(from: k, to: d)     // e3
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 4_096, y: 10_240)).id
        try world.addTrackPlatform(b, on: .edge(1), from: 1_024, to: 9_216)
        let x = try world.buildStation(named: "X", at: PlanPoint(x: 104_448, y: 10_240)).id
        try world.addTrackPlatform(x, on: .edge(1), from: 100_000, to: 108_192)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 301_056, y: 10_240)).id
        let cStation = try world.buildStation(named: "C", at: PlanPoint(x: 333_824, y: 10_240)).id
        let depot = try world.buildStation(named: "D", at: PlanPoint(x: 354_304, y: 12_288)).id
        for (station, edge) in [(a, 1), (cStation, 2), (depot, 3)] {
            let length = try XCTUnwrap(world.trackEdge(.edge(edge + 1))?.length)
            try world.addTrackPlatform(station, on: .edge(edge + 1), from: length - 10_240, to: length - 2_048)
        }
        try world.setStationDepot(depot, to: true)
        let line = try world.createLine(named: "Main", stops: [b, x, a, cStation]).id
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 2, times: [
                LineRunTime(arrival: 601 * 60, departure: 601 * 60), LineRunTime(arrival: 603 * 60, departure: 604 * 60),
                LineRunTime(arrival: 610 * 60, departure: 610 * 60),
            ]),
            LineRun(from: 0, to: 3, times: [
                LineRunTime(arrival: 605 * 60, departure: 605 * 60), LineRunTime(arrival: 607 * 60, departure: 612 * 60),
                LineRunTime(arrival: 618 * 60, departure: 619 * 60), LineRunTime(arrival: 625 * 60, departure: 625 * 60),
            ]),
            LineRun(from: 2, to: 3, times: [
                LineRunTime(arrival: 690 * 60, departure: 690 * 60), LineRunTime(arrival: 700 * 60, departure: 700 * 60),
            ]),
        ])
        try world.setLineDepots(line, to: [depot])
        var trains: [TrainID] = []
        // T1 at the head of B's platform, T3 behind it.
        for (name, offset) in [("T1", Int64(9_216)), ("T3", Int64(6_144))] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(forward(0), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            trains.append(id)
        }
        try world.setTrafficControl(true)
        world.setBlockSections(true)
        return Scene(world: world, depot: depot, c: cStation, t1: trains[0], t3: trains[1])
    }

    /// T1 runs the 10:01 run and stands at A without a service, its next
    /// run there at 11:30, within the two hours; T3, on the 10:05 run,
    /// cannot leave X for A past it: T1 goes into the depot, and T3 runs
    /// on to C.
    func testATrainInTheWayOfAWaitingServiceGoesIntoTheDepot() throws {
        var scene = try makeScene()
        for _ in 0..<40 { try scene.world.advance(ticks: 1) }
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t1).contains(scene.depot), "T1 went into the depot")
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t3).contains(scene.c), "T3 ran the 10:05 run to C")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
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



