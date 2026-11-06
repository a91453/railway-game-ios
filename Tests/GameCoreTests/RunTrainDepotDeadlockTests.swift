@testable import GameCore
import XCTest

/// Decision 556, continued (TYMCLIST8): the Taoyuan Airport MRT's evening
/// at the two airport terminals under the realistic rules. Every berth of
/// both terminals held a train between runs (decision 133) bound for the
/// other, so decision 571's way out (a free berth against the planned way)
/// and TYMCLIST7's (``RunTrainCounterflowTests``) found no free berth, and
/// the line stood still from 16:25 on the second day.
///
/// The scene is ``RunTrainCounterflowTests``' double track with a depot
/// beyond E, a siding off the end of each of E's berths:
///
///   A  W1 ════ n6 ══════════════════════════════ n7 ════ E1 ──── D1
///               ╲ x7                          x12 ╲
///   B  W2 ════════ n5 ════════════════════════════ n8 ══ E2 ──── D2
///
/// X1 and X2 stand at W, their next runs from W to E; Y1 and Y2 at E,
/// theirs from E to W. No berth is free. Simple rules (no block
/// sections), traffic control on, as a new game starts.
final class RunTrainDepotDeadlockTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let xs: [TrainID]
        let ys: [TrainID]
        let w: StationID
        let e: StationID
        let depot: StationID
    }

    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 262_144, height: 65_536), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let w1 = try world.buildTrackNode(at: WorldCoordinate(x: 20_000, y: 40_000))
        let n6 = try world.buildTrackNode(at: WorldCoordinate(x: 26_528, y: 40_000))
        let n7 = try world.buildTrackNode(at: WorldCoordinate(x: 202_272, y: 40_000))
        let e1 = try world.buildTrackNode(at: WorldCoordinate(x: 212_000, y: 40_000))
        let d1 = try world.buildTrackNode(at: WorldCoordinate(x: 220_000, y: 40_000))
        let w2 = try world.buildTrackNode(at: WorldCoordinate(x: 20_000, y: 39_680))
        let n5 = try world.buildTrackNode(at: WorldCoordinate(x: 29_728, y: 39_680))
        let n8 = try world.buildTrackNode(at: WorldCoordinate(x: 205_472, y: 39_680))
        let e2 = try world.buildTrackNode(at: WorldCoordinate(x: 212_000, y: 39_680))
        let d2 = try world.buildTrackNode(at: WorldCoordinate(x: 220_000, y: 39_680))
        let aWest = try world.buildTrackEdge(from: w1, to: n6)
        let aEast = try world.buildTrackEdge(from: n7, to: e1)
        let bWest = try world.buildTrackEdge(from: w2, to: n5)
        let bEast = try world.buildTrackEdge(from: n8, to: e2)
        let aDepot = try world.buildTrackEdge(from: e1, to: d1)
        let bDepot = try world.buildTrackEdge(from: e2, to: d2)
        _ = try world.buildTrackEdge(from: n5, to: n6, curve: .cubic(PlanPoint(x: 28_128, y: 39_680), PlanPoint(x: 28_128, y: 40_000))) // x7
        _ = try world.buildTrackEdge(from: n7, to: n8, curve: .cubic(PlanPoint(x: 203_872, y: 40_000), PlanPoint(x: 203_872, y: 39_680))) // x12
        _ = try world.buildTrackEdge(from: n6, to: n7)
        _ = try world.buildTrackEdge(from: n5, to: n8)

        let w = try world.buildStation(named: "W", at: PlanPoint(x: 22_560, y: 42_048)).id
        try world.addTrackPlatform(w, on: aWest, from: 700, to: 5_120)
        try world.addTrackPlatform(w, on: bWest, from: 1, to: 5_120)
        let e = try world.buildStation(named: "E", at: PlanPoint(x: 209_440, y: 42_048)).id
        try world.addTrackPlatform(e, on: bEast, from: 1_408, to: 5_828)
        try world.addTrackPlatform(e, on: aEast, from: 4_608, to: 9_727)
        let depot = try world.buildStation(named: "D", at: PlanPoint(x: 216_000, y: 42_048)).id
        try world.addTrackPlatform(depot, on: aDepot, from: 1_000, to: 7_000)
        try world.addTrackPlatform(depot, on: bDepot, from: 1_000, to: 7_000)
        try world.setStationDepot(depot, to: true)

        let line = try world.createLine(named: "L", stops: [w, e]).id
        func run(_ from: Int, _ to: Int, at start: Int64) -> LineRun {
            LineRun(from: from, to: to, times: [LineRunTime(arrival: start, departure: start), LineRunTime(arrival: start + 1_800, departure: start + 1_800)])
        }
        try world.setLineRuns(line, to: [run(0, 1, at: 60), run(0, 1, at: 120), run(1, 0, at: 60), run(1, 0, at: 120)])
        try world.setLineDepots(line, to: [depot])
        let xs = [
            try stand(&world, at: TrackTraversal(edge: aWest, direction: .forward), offset: 5_120, on: line),
            try stand(&world, at: TrackTraversal(edge: bWest, direction: .forward), offset: 5_120, on: line),
        ]
        let ys = [
            try stand(&world, at: TrackTraversal(edge: aEast, direction: .backward), offset: 9_728 - 4_608, on: line),
            try stand(&world, at: TrackTraversal(edge: bEast, direction: .backward), offset: 6_528 - 1_408, on: line),
        ]
        try world.setTrafficControl(true)
        return Scene(world: world, xs: xs, ys: ys, w: w, e: e, depot: depot)
    }

    private func stand(_ world: inout GameWorld, at traversal: TrackTraversal, offset: Int64, on line: LineID) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: 2)
        try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
        try world.setTrainContinuation(id, along: [], stoppingAt: offset)
        try world.setTrainMovementRate(id, to: 4_096)
        try world.assignTrain(id, to: line)
        return id
    }

    /// The scene is the one meant: every berth of W and E is taken, by a
    /// train with no service, and the depot's sidings fit them.
    func testEveryBerthIsTakenAndTheDepotFits() throws {
        let scene = try makeScene()
        let world = scene.world
        for id in scene.xs { XCTAssertEqual(world.stationsStoppedAt(by: id), [scene.w]) }
        for id in scene.ys { XCTAssertEqual(world.stationsStoppedAt(by: id), [scene.e]) }
        for id in scene.xs + scene.ys { XCTAssertNil(world.train(id: id)?.execution) }
        let length = try XCTUnwrap(world.train(id: scene.xs[0])?.length)
        XCTAssertTrue(world.depotFits(scene.depot, length: length))
    }

    /// Before, the four stood waiting for their runs all day: no free
    /// berth for any way out. Then, once the deadlock was found, a train
    /// at E ran empty into the depot, and a run from W reached E. Since
    /// decision 609's continuation a train at E, its own run held and in
    /// the way of a run from W, runs in before the four make a deadlock.
    func testATrainBetweenRunsRunsIntoTheDepotWhenNoBerthIsFree() throws {
        var scene = try makeScene()
        var reachedE: Set<TrainID> = []
        var inDepot: Set<TrainID> = []
        var deadlocked: Set<TrainID> = []
        for _ in 0..<60 {
            try scene.world.advance(ticks: 1)
            deadlocked.formUnion(scene.world.deadlockedTrains())
            for id in scene.xs where scene.world.stationsStoppedAt(by: id) == [scene.e] { reachedE.insert(id) }
            for id in scene.ys where scene.world.stationsStoppedAt(by: id) == [scene.depot] { inDepot.insert(id) }
            XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
        }
        XCTAssertEqual(deadlocked, [], "a train at E went in before the four made a deadlock")
        XCTAssertFalse(inDepot.isEmpty)
        XCTAssertFalse(reachedE.isEmpty)
        XCTAssertEqual(scene.world.deadlockedTrains(), [])
    }

    /// A batch of minutes ends where minute by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var minutes = try makeScene()
        var batch = try makeScene()
        for _ in 0..<60 { try minutes.world.advance(ticks: 1) }
        try batch.world.advance(ticks: 60)
        XCTAssertEqual(minutes.world, batch.world)
    }
}
