@testable import GameCore
import XCTest

/// Decision 556, continued (TYMCLIST7): the Taoyuan Airport MRT's evening
/// at the two airport terminals. Trains of a line with runs (decision 133)
/// that have finished one run stand at a terminus between runs, with no
/// service. When the next run of each is due and each is bound for the
/// berth the other stands on, they wait for each other as two services do
/// in decision 571's continuation, but that way out (a free berth against
/// the planned way) was only for a service already waiting at a stop, so
/// they waited for good: the airport line stopped every evening.
///
/// The scene is ``CounterflowDeadlockTests``' double track:
///
///   A  W1 ════ n6 ══════════════════════════════ n7 ════ E1
///               ╲ x7                          x12 ╲
///   B  W2 ════════ n5 ════════════════════════════ n8 ══ E2
///
/// X stands at W1, its next run from W to E, whose nearest berth is E2; Y
/// stands at E2, its next run from E to W, whose nearest berth is W1. E1
/// and W2 are free, but the way to them runs along the main track the
/// other is bound along the other way. Simple rules (no block sections),
/// traffic control on, as a new game starts.
final class RunTrainCounterflowTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let x: TrainID
        let y: TrainID
        let w: StationID
        let e: StationID
    }

    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 229_376, height: 65_536), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
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
        let aWest = try world.buildTrackEdge(from: w1, to: n6)
        let aEast = try world.buildTrackEdge(from: n7, to: e1)
        let bWest = try world.buildTrackEdge(from: w2, to: n5)
        let bEast = try world.buildTrackEdge(from: n8, to: e2)
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

        let line = try world.createLine(named: "L", stops: [w, e]).id
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 60, departure: 60), LineRunTime(arrival: 1_800, departure: 1_800)]),
            LineRun(from: 1, to: 0, times: [LineRunTime(arrival: 180, departure: 180), LineRunTime(arrival: 1_800, departure: 1_800)]),
        ])
        let x = try stand(&world, at: TrackTraversal(edge: aWest, direction: .forward), offset: 5_120, on: line)
        let y = try stand(&world, at: TrackTraversal(edge: bEast, direction: .backward), offset: 6_528 - 1_408, on: line)
        try world.setTrafficControl(true)
        return Scene(world: world, x: x, y: y, w: w, e: e)
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

    /// The scene is the one meant: each is bound through the crossovers
    /// for the berth the other stands on, and neither has a service yet.
    func testEachIsBoundForTheBerthTheOtherStandsOn() throws {
        let scene = try makeScene()
        for (train, other, call) in [(scene.x, scene.y, scene.e), (scene.y, scene.x, scene.w)] {
            let world = scene.world
            XCTAssertNil(world.train(id: train)?.execution)
            let start = try XCTUnwrap(world.train(id: train)?.position)
            let length = try XCTUnwrap(world.train(id: train)?.length)
            guard case .onEdge(let standing, _)? = world.train(id: other)?.position else { return XCTFail("placed") }
            XCTAssertEqual(world.path(from: start, toStation: call, length: length)?.traversals.last?.edge, standing.edge)
        }
    }

    /// Before, X and Y stood waiting for their runs all day. Now, once the
    /// deadlock is found, X is put on its run and takes E1 against Y's
    /// way, as a service would (decision 571, continued); Y follows to W1.
    func testTrainsBetweenRunsBoundForEachOthersBerthsTakeAFreeOne() throws {
        var scene = try makeScene()
        var arrived: Set<TrainID> = []
        var deadlocked: Set<TrainID> = []
        for _ in 0..<60 {
            try scene.world.advance(ticks: 1)
            deadlocked.formUnion(scene.world.deadlockedTrains())
            if scene.world.stationsStoppedAt(by: scene.x) == [scene.e] { arrived.insert(scene.x) }
            if scene.world.stationsStoppedAt(by: scene.y) == [scene.w] { arrived.insert(scene.y) }
            XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
        }
        XCTAssertEqual(arrived, [scene.x, scene.y], "deadlocked: \(deadlocked)")
    }

    /// A batch of minutes ends where minute by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var minutes = try makeScene()
        var batch = try makeScene()
        for _ in 0..<40 { try minutes.world.advance(ticks: 1) }
        try batch.world.advance(ticks: 40)
        XCTAssertEqual(minutes.world, batch.world)
    }
}
