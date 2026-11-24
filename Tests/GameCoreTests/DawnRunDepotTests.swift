@testable import GameCore
import XCTest

/// Decision 954 (TYMC-DAWN-TAIPEI): with block sections an end of a line
/// with runs keeps through the night the trains its first runs of the
/// morning need, the runs before the first train to come in on a run from
/// the line's other end; the rest go into the depot as before (decision
/// 221: no run within two hours). On the Taoyuan Airport MRT under the
/// realistic rules, the trains left at Taipei Main Station overnight were
/// those that came in once Luzhu's sidings were full, and the runs from
/// Taipei after 06:15 waited for trains out of Luzhu, 30 km away.
///
///   B ── X ──e0 (4.5 km)── J ──e1── PA ── K ──e2── C
///                               └──e3── D (Depot)
///
/// B, the line's first stop, has its platform on `e0`; C, its last, on
/// `e2`. The geometry is ``SurplusRunDepotTests``'.
final class DawnRunDepotTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge + 1), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let line: LineID
        let b: StationID
        let depot: StationID
        let train: TrainID
    }

    /// At 23:00, the line Main calling at B, X, A and C, with a run from
    /// B to C at 05:30 every day and the depot D (one siding); T1, Main's,
    /// at B, traffic control on. With block sections when `blocks`. When
    /// `arriving`, a run from C arrives at B at 05:20 too, in time for the
    /// 05:30.
    private func makeScene(blocks: Bool = true, arriving: Bool = false) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 362_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 23 * 60), speed: .normal)
        )
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 288_768, y: 8_192))
        let k = try world.buildTrackNode(at: WorldCoordinate(x: 313_344, y: 8_192))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 337_920, y: 8_192))
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
        func run(at minute: Int64, back: Bool = false) -> LineRun {
            let calls: [(Int64, Int64)] = [(0, 0), (6, 7), (13, 14), (16, 16)]
            let times = calls.map { call in LineRunTime(arrival: (minute + call.0) * 60, departure: (minute + call.1) * 60) }
            return back ? LineRun(from: 3, to: 0, times: times) : LineRun(from: 0, to: 3, times: times)
        }
        var runs = [run(at: 5 * 60 + 30)]
        if arriving { runs.append(run(at: 5 * 60 + 4, back: true)) }
        try world.setLineRuns(line, to: runs)
        try world.setLineDepots(line, to: [depot])
        let id = try world.purchaseTrain(named: "T1").id
        try world.setTrainCars(id, to: 2)
        try world.placeTrain(id, at: .onEdge(forward(0), offset: 9_216))
        try world.setTrainContinuation(id, along: [], stoppingAt: 9_216)
        try world.setTrainMovementRate(id, to: 4_096)
        try world.assignTrain(id, to: line)
        try world.setTrafficControl(true)
        if blocks { world.setBlockSections(true) }
        return Scene(world: world, line: line, b: b, depot: depot, train: id)
    }

    /// The morning's first run from B comes before any train comes in
    /// from C: T1 waits at B through the night and takes it. (Before, it
    /// went into the depot at 23:00, no run leaving within two hours, and
    /// came out again for the run.)
    func testAnEndKeepsTheTrainForItsFirstRun() throws {
        var scene = try makeScene()
        for _ in 0..<(5 * 60) { try scene.world.advance(ticks: 1) } // 04:00
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.train).contains(scene.b), "T1 stayed at B")
        for _ in 0..<(2 * 60) { try scene.world.advance(ticks: 1) } // 06:00
        XCTAssertEqual(try XCTUnwrap(scene.world.line(id: scene.line)).runDays[0], 1, "the 05:30 left")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// A train in from C at 05:20 takes the 05:30: B keeps none, and T1
    /// goes in.
    func testATrainInFromTheOtherEndTakesTheRun() throws {
        var scene = try makeScene(arriving: true)
        for _ in 0..<(5 * 60) { try scene.world.advance(ticks: 1) } // 04:00
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.train).contains(scene.depot), "T1 went into the depot")
    }

    /// Without block sections decision 221 stands: T1 goes in.
    func testWithoutBlockSectionsTheTrainGoesIn() throws {
        var scene = try makeScene(blocks: false)
        for _ in 0..<(5 * 60) { try scene.world.advance(ticks: 1) } // 04:00
        XCTAssertTrue(scene.world.stationsStoppedAt(by: scene.train).contains(scene.depot), "T1 went into the depot")
    }

    /// A batch ends where minute by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        for (blocks, arriving) in [(true, false), (true, true), (false, false)] {
            let scene = try makeScene(blocks: blocks, arriving: arriving)
            var single = scene.world
            for _ in 0..<(7 * 60) { try single.advance(ticks: 1) }
            var batched = scene.world
            try batched.advance(ticks: 7 * 60)
            XCTAssertEqual(batched, single, "block sections \(blocks), arriving \(arriving)")
        }
    }
}
