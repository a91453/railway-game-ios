@testable import GameCore
import XCTest

/// Decision 556, continued (TYMCLIST8, tested by TYMCLIST9): the last way
/// out of a deadlock, a service of a line with runs (decision 133) that
/// stands aside against the planned directions and however far round
/// (``GameWorld/passingPlace(for:in:anyWay:memo:)``). On the Taoyuan
/// Airport MRT under the simple rules with traffic control, both of
/// Kengkou's berths held trains bound for the first airport terminal, and
/// the terminal's held trains bound for Kengkou: no passing place lay
/// between them the planned way, and the line stood.
///
/// The scene is ``RunTrainDepotDeadlockTests``' double track with, past
/// E's second berth, a long track to F, a station no line calls at:
///
///   A  W1 ════ n6 ══════════════════════════ n7 ════ E1
///               ╲ x7                      x12 ╲
///   B  W2 ════════ n5 ════════════════════════ n8 ══ E2 ─────────────── F
///
/// X1 and X2 stand at W on runs to E, Y1 and Y2 at E on runs to W, all
/// four due at 0:10. Simple rules (no block sections), traffic control
/// on, as a new game starts. F is off the line, against the eastbound
/// trains' way and further than ``GameWorld/detourAllowance``.
final class RunServiceStandAsideAnyWayTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let xs: [TrainID]
        let ys: [TrainID]
        let w: StationID
        let e: StationID
        let f: StationID
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
                let w2 = try world.buildTrackNode(at: WorldCoordinate(x: 20_000, y: 39_680))
        let n5 = try world.buildTrackNode(at: WorldCoordinate(x: 29_728, y: 39_680))
        let n8 = try world.buildTrackNode(at: WorldCoordinate(x: 205_472, y: 39_680))
        let e2 = try world.buildTrackNode(at: WorldCoordinate(x: 212_000, y: 39_680))
        let f1 = try world.buildTrackNode(at: WorldCoordinate(x: 252_000, y: 39_680))
        let aWest = try world.buildTrackEdge(from: w1, to: n6)
        let aEast = try world.buildTrackEdge(from: n7, to: e1)
        let bWest = try world.buildTrackEdge(from: w2, to: n5)
        let bEast = try world.buildTrackEdge(from: n8, to: e2)
        let beyond = try world.buildTrackEdge(from: e2, to: f1)
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
        let f = try world.buildStation(named: "F", at: PlanPoint(x: 248_000, y: 37_632)).id
        try world.addTrackPlatform(f, on: beyond, from: 30_000, to: 36_000)

        let line = try world.createLine(named: "L", stops: [w, e]).id
        func run(_ from: Int, _ to: Int, at start: Int64) -> LineRun {
            LineRun(from: from, to: to, times: [LineRunTime(arrival: start, departure: start), LineRunTime(arrival: start + 1_800, departure: start + 1_800)])
        }
        try world.setLineRuns(line, to: [run(0, 1, at: 600), run(0, 1, at: 600), run(1, 0, at: 600), run(1, 0, at: 600)])
        let xs = [
            try stand(&world, at: TrackTraversal(edge: aWest, direction: .forward), offset: 5_120, on: line),
            try stand(&world, at: TrackTraversal(edge: bWest, direction: .forward), offset: 5_120, on: line),
        ]
        let ys = [
            try stand(&world, at: TrackTraversal(edge: aEast, direction: .backward), offset: 9_728 - 4_608, on: line),
            try stand(&world, at: TrackTraversal(edge: bEast, direction: .backward), offset: 6_528 - 1_408, on: line),
        ]
        // With traffic control off the line sends all four out on their
        // runs five minutes ahead; then traffic control comes on, before
        // they are due to leave.
        for _ in 0..<6 { try world.advance(ticks: 1) }
        try world.setTrafficControl(true)
        return Scene(world: world, xs: xs, ys: ys, w: w, e: e, f: f)
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

    /// The scene is the one meant: all four are services waiting at their
    /// first stops, every berth of W and E is taken, F fits a train, and
    /// once due the four are a deadlock.
    func testEveryBerthIsTakenByAServiceBoundForTheOtherEnd() throws {
        var scene = try makeScene()
        for id in scene.xs {
            XCTAssertEqual(scene.world.stationsStoppedAt(by: id), [scene.w])
            guard case .waitingAtStop(0, _)? = scene.world.train(id: id)?.execution else { return XCTFail("X is on its run") }
        }
        for id in scene.ys {
            XCTAssertEqual(scene.world.stationsStoppedAt(by: id), [scene.e])
            guard case .waitingAtStop(0, _)? = scene.world.train(id: id)?.execution else { return XCTFail("Y is on its run") }
        }
        let length = try XCTUnwrap(scene.world.train(id: scene.ys[0])?.length)
        XCTAssertFalse(scene.world.berths(of: scene.f, length: length).isEmpty)
        try scene.world.advance(ticks: 4)
        XCTAssertEqual(scene.world.deadlockedTrains(), (scene.xs + scene.ys).sorted())
    }

    /// Before, the four stood all day: no passing place the planned way.
    /// Now, the minute the deadlock is found, the train at E's second
    /// berth, where both trains from W are bound, backs out to F; a train
    /// from W takes the berth, and the other at E leaves for W. (The scene
    /// has no later runs, so the two left then wait for the train whose
    /// run has ended at E: no deadlock, and none of this exit's doing.)
    func testAServiceOfARunLineStandsAsideAgainstThePlannedWay() throws {
        var scene = try makeScene()
        var atF: Set<TrainID> = []
        var reachedE: Set<TrainID> = []
        var reachedW: Set<TrainID> = []
        var deadlocked: Set<TrainID> = []
        for minute in 0..<60 {
            try scene.world.advance(ticks: 1)
            let stuck = scene.world.deadlockedTrains()
            deadlocked.formUnion(stuck)
            if minute >= 5 { XCTAssertEqual(stuck, [], "cleared the minute it is found") }
            for id in scene.ys where scene.world.stationsStoppedAt(by: id) == [scene.f] { atF.insert(id) }
            for id in scene.xs where scene.world.stationsStoppedAt(by: id) == [scene.e] { reachedE.insert(id) }
            for id in scene.ys where scene.world.stationsStoppedAt(by: id) == [scene.w] { reachedW.insert(id) }
            XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
        }
        XCTAssertEqual(deadlocked, Set(scene.xs + scene.ys), "the scene deadlocks first")
        XCTAssertEqual(atF, [scene.ys[1]], "the train on E's second berth stands aside at F")
        XCTAssertEqual(reachedE.count, 1)
        XCTAssertEqual(reachedW, [scene.ys[0]])
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
