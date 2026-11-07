@testable import GameCore
import XCTest

/// Decision 609: under traffic control a train of a line with runs,
/// waiting without a service where runs leave within the two hours a
/// waiting train looks ahead (decision 221), goes into its line's depot
/// when the runs leaving there within the hour still each find a train
/// without it: the last waiting in ID order, the one its runs take last.
///
/// The Taoyuan Airport MRT under the simple rules with traffic control: a
/// train late for its run at Airport Terminal 2 had one sent out of the
/// depot for it; arrived, it stood there for hours on one of the
/// station's three tracks, as some run left there within two hours all
/// day, and the trains turning back at Terminal 1 and those bound north
/// from Terminal 2 were held for each other's tracks.
///
///   B ── X ──e0 (4.5 km)── J ──e1── PA ── K ──e2── C
///                               └──e3── D (Depot)
///
/// A's one platform is on `e1`, B's and X's on `e0`; edge `en` is `.edge(n + 1)`.
///
/// Decision 609, continued (WENHU-LATE): only without block sections, as
/// its second part (``GameWorld/heldRunDepartures(memo:)``). With them it
/// sent trains in and out of the Wenhu line's depots all day under the
/// realistic rules (second day 286 → 308 trips late, the Tamsui line's
/// Green Mountain line deadlocked) and kept one at the Taoyuan Airport
/// MRT's Terminal 2 for five hours a night.
final class SurplusRunDepotTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge + 1), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let line: LineID
        let depot: StationID
        let t1: TrainID
        let t2: TrainID
    }

    /// At 10:00, the line Main calling at B, X, A and C, with runs from B
    /// to C at 10:30 and 11:30 and the depot D; T1 and T2, Main's, at B,
    /// T2 ahead. With traffic control when `controlled`, and block
    /// sections when `blocks`.
    private func makeScene(controlled: Bool = true, blocks: Bool = false) throws -> Scene {
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
        func run(at minute: Int64) -> LineRun {
            let calls: [(Int64, Int64)] = [(0, 0), (2, 3), (9, 10), (16, 16)]
            let times = calls.map { call in LineRunTime(arrival: (minute + call.0) * 60, departure: (minute + call.1) * 60) }
            return LineRun(from: 0, to: 3, times: times)
        }
        let runs = [run(at: 630), run(at: 690)]
        try world.setLineRuns(line, to: runs)
        try world.setLineDepots(line, to: [depot])
        var trains: [TrainID] = []
        // T1 behind T2 on B's platform.
        for (name, offset) in [("T1", Int64(6_144)), ("T2", Int64(9_216))] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(forward(0), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            trains.append(id)
        }
        if controlled {
            try world.setTrafficControl(true)
        }
        if blocks { world.setBlockSections(true) }
        return Scene(world: world, line: line, depot: depot, t1: trains[0], t2: trains[1])
    }

    /// Both runs leave within the two hours, so neither train is one too
    /// many by decision 221's count; within the hour only the 10:30 does,
    /// which T1 takes: T2 goes into the depot, and comes out again for the
    /// 11:30, which leaves too.
    func testATrainNoRunWantsWithinTheHourGoesIntoTheDepot() throws {
        var scene = try makeScene()
        for _ in 0..<20 { try scene.world.advance(ticks: 1) }
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.t2).contains(scene.depot), "T2 went into the depot")
        for _ in 0..<100 { try scene.world.advance(ticks: 1) }
        let line = try XCTUnwrap(scene.world.line(id: scene.line))
        XCTAssertEqual(line.runDays[0], 0, "the 10:30 left")
        XCTAssertEqual(line.runDays[1], 0, "the 11:30 left")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// Without traffic control decision 221's count stands: both trains
    /// wait for the runs.
    func testWithoutTrafficControlBothWait() throws {
        var scene = try makeScene(controlled: false)
        for _ in 0..<20 { try scene.world.advance(ticks: 1) }
        XCTAssertFalse(scene.world.stationsStoppedAt(by: scene.t2).contains(scene.depot), "T2 stayed at B")
        XCTAssertFalse(scene.world.stationsStoppedAt(by: scene.t1).contains(scene.depot), "T1 stayed at B")
    }

    /// WENHU-LATE: with block sections the rule stands aside, as decision
    /// 609's second part does: both trains wait for the runs, and both
    /// runs leave.
    func testWithBlockSectionsBothWait() throws {
        var scene = try makeScene(blocks: true)
        for _ in 0..<20 { try scene.world.advance(ticks: 1) }
        XCTAssertFalse(scene.world.stationsStoppedAt(by: scene.t2).contains(scene.depot), "T2 stayed at B")
        XCTAssertFalse(scene.world.stationsStoppedAt(by: scene.t1).contains(scene.depot), "T1 stayed at B")
        for _ in 0..<100 { try scene.world.advance(ticks: 1) }
        let line = try XCTUnwrap(scene.world.line(id: scene.line))
        XCTAssertEqual(line.runDays[0], 0, "the 10:30 left")
        XCTAssertEqual(line.runDays[1], 0, "the 11:30 left")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The trains move at whole minutes, so a batch ends where minute by
    /// minute does, with block sections or without.
    func testABatchEndsWhereMinutesDo() throws {
        for blocks in [false, true] {
            let scene = try makeScene(blocks: blocks)
            var single = scene.world
            for _ in 0..<120 { try single.advance(ticks: 1) }
            var batched = scene.world
            try batched.advance(ticks: 120)
            XCTAssertEqual(batched, single, "block sections \(blocks)")
        }
    }
}
