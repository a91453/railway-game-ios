@testable import GameCore
import XCTest

/// Decision 556, continued (TYMCLIST9): decision 571's way out of a
/// deadlock, a free berth of the call taken against the planned way, for
/// a service of a line with runs (decision 133) standing aside at a
/// passing place (Stage V2), not only one waiting at a stop. On the
/// Taoyuan Airport MRT under the realistic rules, the night's last train
/// stood aside at Airport Hotel bound for the first airport terminal,
/// whose free berths it could reach only against the planned way; the
/// line stood from 00:23 to 05:39.
///
/// The scene is ``CounterflowDeadlockTests``' double track with W's second
/// berth taken away:
///
///   A  W1 ════ n6 ══════════════════════════════ n7 ════ E1
///               ╲ x7                          x12 ╲
///   B          n5 ════════════════════════════════ n8 ══ E2
///
/// X stands at W1, on its run to E, standing aside there (its call is E);
/// E's nearest berth is E2, where Y stands on its run to W, whose one
/// berth is W1. E1 is free, along A against Y's way. Simple rules (no
/// block sections), traffic control on, as a new game starts.
final class RunStoodAsideCounterflowTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let x: TrainID
        let y: TrainID
        let w: StationID
        let e: StationID
        let aMain: TrackEdgeID
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
        let n5 = try world.buildTrackNode(at: WorldCoordinate(x: 29_728, y: 39_680))
        let n8 = try world.buildTrackNode(at: WorldCoordinate(x: 205_472, y: 39_680))
        let e2 = try world.buildTrackNode(at: WorldCoordinate(x: 212_000, y: 39_680))
        let aWest = try world.buildTrackEdge(from: w1, to: n6)
        let aEast = try world.buildTrackEdge(from: n7, to: e1)
        let bEast = try world.buildTrackEdge(from: n8, to: e2)
        _ = try world.buildTrackEdge(from: n5, to: n6, curve: .cubic(PlanPoint(x: 28_128, y: 39_680), PlanPoint(x: 28_128, y: 40_000))) // x7
        _ = try world.buildTrackEdge(from: n7, to: n8, curve: .cubic(PlanPoint(x: 203_872, y: 40_000), PlanPoint(x: 203_872, y: 39_680))) // x12
        let aMain = try world.buildTrackEdge(from: n6, to: n7)
        _ = try world.buildTrackEdge(from: n5, to: n8)

        let w = try world.buildStation(named: "W", at: PlanPoint(x: 22_560, y: 42_048)).id
        try world.addTrackPlatform(w, on: aWest, from: 700, to: 5_120)
        let e = try world.buildStation(named: "E", at: PlanPoint(x: 209_440, y: 42_048)).id
        try world.addTrackPlatform(e, on: bEast, from: 1_408, to: 5_828)
        try world.addTrackPlatform(e, on: aEast, from: 4_608, to: 9_727)

        let line = try world.createLine(named: "L", stops: [w, e]).id
        func run(_ from: Int, _ to: Int, at start: Int64) -> LineRun {
            LineRun(from: from, to: to, times: [LineRunTime(arrival: start, departure: start), LineRunTime(arrival: start + 1_800, departure: start + 1_800)])
        }
        try world.setLineRuns(line, to: [run(0, 1, at: 600), run(1, 0, at: 600)])
        let x = try stand(&world, at: TrackTraversal(edge: aWest, direction: .forward), offset: 5_120, on: line)
        let y = try stand(&world, at: TrackTraversal(edge: bEast, direction: .backward), offset: 6_528 - 1_408, on: line)
        // With traffic control off the line sends both out on their runs
        // five minutes ahead; then traffic control comes on, and X, as if
        // it had stood aside at W on its way, is bound for E from there.
        for _ in 0..<6 { try world.advance(ticks: 1) }
        try world.setTrafficControl(true)
        var aside = try XCTUnwrap(world.train(id: x))
        aside.execution = .travellingToStop(1, cycle: 0)
        world = world.replacing(aside)
        return Scene(world: world, x: x, y: y, w: w, e: e, aMain: aMain)
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

    /// The scene is the one meant: X stands aside at W bound for E2,
    /// where Y waits for W1, where X stands; at 0:10 the two are a
    /// deadlock.
    func testXStandsAsideBoundForTheBerthYStandsOn() throws {
        var scene = try makeScene()
        let x = try XCTUnwrap(scene.world.train(id: scene.x))
        XCTAssertTrue(scene.world.isAtPassingPlace(x))
        XCTAssertEqual(scene.world.passingPlace(of: scene.x), scene.w)
        guard case .waitingAtStop(0, _)? = scene.world.train(id: scene.y)?.execution else { return XCTFail("Y is on its run") }
        let start = try XCTUnwrap(x.position)
        guard case .onEdge(let standing, _)? = scene.world.train(id: scene.y)?.position else { return XCTFail("placed") }
        XCTAssertEqual(scene.world.path(from: start, toStation: scene.e, length: x.length)?.traversals.last?.edge, standing.edge)
        try scene.world.advance(ticks: 4)
        XCTAssertEqual(scene.world.deadlockedTrains(), [scene.x, scene.y].sorted())
    }

    /// Before, X and Y waited for each other for good: decision 571's way
    /// out was only for a service waiting at a stop, and Y's call has no
    /// free berth. Now X goes to E1 along A, taken whole, and Y follows to
    /// W1.
    func testAServiceStandingAsideTakesAFreeBerthAgainstTheWay() throws {
        var scene = try makeScene()
        var arrived: Set<TrainID> = []
        var usedA = false
        for _ in 0..<60 {
            try scene.world.advance(ticks: 1)
            if scene.world.train(id: scene.x)?.movement.edges.contains(scene.aMain) == true { usedA = true }
            if scene.world.stationsStoppedAt(by: scene.x) == [scene.e] { arrived.insert(scene.x) }
            if scene.world.stationsStoppedAt(by: scene.y) == [scene.w] { arrived.insert(scene.y) }
            XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
        }
        XCTAssertEqual(arrived, [scene.x, scene.y], "deadlocked: \(scene.world.deadlockedTrains())")
        XCTAssertTrue(usedA, "X went along A")
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
