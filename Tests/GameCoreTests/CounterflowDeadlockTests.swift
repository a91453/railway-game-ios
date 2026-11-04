@testable import GameCore
import XCTest

/// Decision 571, continued (TestFlight 110.1: "a double track with a
/// signal station, the longest platforms, and the trains are always
/// deadlocked"). The platform tool lays one crossover inboard of each end
/// of a double track (decision 571). Where each way's shortest path
/// crosses over at both ends, each way reaches one berth at each end, and
/// two trains standing on those berths each wait for the other's:
///
///   A  W1 ════ n6 ══════════════════════════════ n7 ════ E1
///               ╲ x7                          x12 ╲
///   B  W2 ════════ n5 ════════════════════════════ n8 ══ E2
///
/// X stands at W1, bound for E, whose nearest berth is E2; Y stands at E2,
/// bound for W, whose nearest berth is W1. E1 and W2 are free, but the way
/// to them runs along the main track the other is bound along the other
/// way, which decision 57's direction protection forbids. Simple rules (no
/// block sections), traffic control on, as a new game starts.
final class CounterflowDeadlockTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let x: TrainID
        let y: TrainID
        let w: StationID
        let e: StationID
        let aMain: TrackEdgeID
    }

    /// `farther` moves the two free berths, W2 and E1, that much farther
    /// out (the rest of the scene that much east).
    private func makeScene(farther: Int64 = 0) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 229_376 + 131_072, height: 65_536), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        // Track A, y 40,000.
        let w1 = try world.buildTrackNode(at: WorldCoordinate(x: 20_000 + farther, y: 40_000))
        let n6 = try world.buildTrackNode(at: WorldCoordinate(x: 26_528 + farther, y: 40_000))
        let n7 = try world.buildTrackNode(at: WorldCoordinate(x: 202_272 + farther, y: 40_000))
        let e1 = try world.buildTrackNode(at: WorldCoordinate(x: 212_000 + 2 * farther, y: 40_000))
        // Track B, 320 units (5 m) beside it.
        let w2 = try world.buildTrackNode(at: WorldCoordinate(x: 20_000, y: 39_680))
        let n5 = try world.buildTrackNode(at: WorldCoordinate(x: 29_728 + farther, y: 39_680))
        let n8 = try world.buildTrackNode(at: WorldCoordinate(x: 205_472 + farther, y: 39_680))
        let e2 = try world.buildTrackNode(at: WorldCoordinate(x: 212_000 + farther, y: 39_680))
        let aWest = try world.buildTrackEdge(from: w1, to: n6)
        let aEast = try world.buildTrackEdge(from: n7, to: e1)
        let bWest = try world.buildTrackEdge(from: w2, to: n5)
        let bEast = try world.buildTrackEdge(from: n8, to: e2)
        // The crossovers before the main tracks: of two ways as long, a
        // path takes the lower numbered edge first, as on the player's map
        // (the platform tool's crossovers split the tracks it was laid
        // on), so each way crosses over where it sets off.
        _ = try world.buildTrackEdge(from: n5, to: n6, curve: .cubic(PlanPoint(x: 28_128 + farther, y: 39_680), PlanPoint(x: 28_128 + farther, y: 40_000))) // x7
        _ = try world.buildTrackEdge(from: n7, to: n8, curve: .cubic(PlanPoint(x: 203_872 + farther, y: 40_000), PlanPoint(x: 203_872 + farther, y: 39_680))) // x12
        let aMain = try world.buildTrackEdge(from: n6, to: n7)
        _ = try world.buildTrackEdge(from: n5, to: n8)

        // W1 and E2 end 700 units nearer the other station than W2 and E1:
        // the nearest berths, through the crossovers.
        let w = try world.buildStation(named: "W", at: PlanPoint(x: 22_560 + farther, y: 42_048)).id
        try world.addTrackPlatform(w, on: aWest, from: 700, to: 5_120)
        try world.addTrackPlatform(w, on: bWest, from: 1, to: 5_120)
        let e = try world.buildStation(named: "E", at: PlanPoint(x: 209_440 + farther, y: 42_048)).id
        try world.addTrackPlatform(e, on: bEast, from: 1_408, to: 5_828)
        try world.addTrackPlatform(e, on: aEast, from: 4_608 + farther, to: 9_727 + farther)

        let x = try stand(&world, at: TrackTraversal(edge: aWest, direction: .forward), offset: 5_120)
        let y = try stand(&world, at: TrackTraversal(edge: bEast, direction: .backward), offset: 6_528 - 1_408)
        try world.setTrainTimetable(x, to: [
            ScheduledStop(station: w, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: e, arrival: GameTime(minutes: 30), departure: GameTime(minutes: 30)),
        ])
        try world.setTrainTimetable(y, to: [
            ScheduledStop(station: e, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 3)),
            ScheduledStop(station: w, arrival: GameTime(minutes: 30), departure: GameTime(minutes: 30)),
        ])
        try world.setTrafficControl(true)
        try world.startTrainService(x)
        try world.startTrainService(y)
        return Scene(world: world, x: x, y: y, w: w, e: e, aMain: aMain)
    }

    private func stand(_ world: inout GameWorld, at traversal: TrackTraversal, offset: Int64) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(id, to: 2)
        try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
        try world.setTrainContinuation(id, along: [], stoppingAt: offset)
        try world.setTrainMovementRate(id, to: 4_096)
        return id
    }

    /// The scene is the one meant: each is bound through the crossovers
    /// for the berth the other stands on.
    func testEachIsBoundForTheBerthTheOtherStandsOn() throws {
        let scene = try makeScene()
        for (train, other, call) in [(scene.x, scene.y, scene.e), (scene.y, scene.x, scene.w)] {
            let world = scene.world
            let start = try XCTUnwrap(world.train(id: train)?.position)
            let length = try XCTUnwrap(world.train(id: train)?.length)
            guard case .onEdge(let standing, _)? = world.train(id: other)?.position else { return XCTFail("placed") }
            XCTAssertEqual(world.path(from: start, toStation: call, length: length)?.traversals.last?.edge, standing.edge)
        }
    }

    /// Before, X and Y waited for each other for good. Now, once the
    /// deadlock is found, the dispatcher sends X to E1 along A, against
    /// Y's way, taken whole; Y follows to W1 once X has left A.
    func testTrainsBoundForEachOthersBerthsTakeAFreeOneAgainstTheWay() throws {
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
    }

    /// A free berth is taken only within ``GameWorld/detourAllowance`` of
    /// the train's route: W2 and E1 moved farther than that leave the two
    /// waiting (as before), and well within it, they go.
    func testAFreeBerthFartherThanTheDetourAllowanceIsNotTaken() throws {
        let allowance = GameWorld.detourAllowance
        for (farther, taken) in [(allowance - 2_048, true), (allowance + 512, false)] {
            var scene = try makeScene(farther: farther)
            var usedA = false
            for _ in 0..<20 {
                try scene.world.advance(ticks: 1)
                if scene.world.train(id: scene.x)?.movement.edges.contains(scene.aMain) == true { usedA = true }
            }
            XCTAssertEqual(usedA, taken, "\(farther) farther")
            XCTAssertEqual(scene.world.deadlockedTrains().isEmpty, taken, "\(farther) farther")
        }
    }
}
