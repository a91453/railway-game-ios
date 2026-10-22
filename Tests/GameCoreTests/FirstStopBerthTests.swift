@testable import GameCore
import XCTest

/// Decision 344: without block sections (the simple rules, decision 258)
/// a train bound for a line's first stop takes another of its berths when
/// the one its route names is taken. A line is planned from every berth
/// of its first stop (``GameWorld/opposingParts(for:memo:)``), so each
/// berth's way in was planned the other way, and decision 57 forbade them
/// all: the train waited all day for the one standing there, with no
/// warning (the bought branch lines with their branch station first,
/// decision 315's "後來").
///
///                ┌─e3─ l1 ──e4── l2 ─e5─┐
///   W ──e1── jW ──┴──────────e2──────────┴── jE ──e6── B
///                 (A: P1 on e2, P2 on e4)          (B on e6)
///
/// The line runs from A to B; its train X stands at P1, the berth the
/// shortest way into A names. Y, a service from B to A, comes in.
final class FirstStopBerthTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let service: TrainID
        let a: StationID
    }

    private func makeScene(blocks: Bool = false) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 106_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let jW = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let jE = try world.buildTrackNode(at: WorldCoordinate(x: 81_920, y: 8_192))
        let l1 = try world.buildTrackNode(at: WorldCoordinate(x: 32_768, y: 9_216))
        let l2 = try world.buildTrackNode(at: WorldCoordinate(x: 65_536, y: 9_216))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 104_448, y: 8_192))
        try world.buildTrackEdge(from: west, to: jW)  // e1
        try world.buildTrackEdge(from: jW, to: jE)    // e2
        try world.buildTrackEdge(from: jW, to: l1)    // e3
        try world.buildTrackEdge(from: l1, to: l2)    // e4
        try world.buildTrackEdge(from: l2, to: jE)    // e5
        try world.buildTrackEdge(from: jE, to: end)   // e6
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 49_152, y: 6_144)).id
        try world.addTrackPlatform(a, on: .edge(2), from: 24_576, to: 40_960)
        try world.addTrackPlatform(a, on: .edge(4), from: 8_192, to: 24_576)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 100_352, y: 6_144)).id
        let e6 = try XCTUnwrap(world.trackEdge(.edge(6))?.length)
        try world.addTrackPlatform(b, on: .edge(6), from: e6 - 8_192, to: e6 - 1_024)
        let line = try world.createLine(named: "L", stops: [a, b]).id
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 0, offPeak: 0, low: 0))
        let x = try world.purchaseTrain(named: "X").id
        try world.setTrainCars(x, to: 2)
        try world.placeTrain(x, at: .onEdge(TrackTraversal(edge: .edge(2), direction: .backward), offset: 40_960))
        try world.assignTrain(x, to: line)

        let service = try world.purchaseTrain(named: "Y").id
        try world.setTrainCars(service, to: 2)
        try world.placeTrain(service, at: .onEdge(TrackTraversal(edge: .edge(6), direction: .backward), offset: 8_192))
        try world.setTrainContinuation(service, along: [], stoppingAt: 8_192)
        try world.setTrainMovementRate(service, to: 4_096)
        try world.setTrainTimetable(service, to: [
            ScheduledStop(station: b, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: a, arrival: GameTime(minutes: 30), departure: GameTime(minutes: 30)),
        ])
        world.setBlockSections(blocks)
        try world.setTrafficControl(true)
        try world.startTrainService(service)
        return Scene(world: world, service: service, a: a)
    }

    /// Before decision 344 Y waited at B for X all day: A's other berth,
    /// P2, lies on the line's way out of A from P2. Now Y sets off for P2.
    func testATrainTakesAnotherBerthOfALinesFirstStopWithoutBlockSections() throws {
        var scene = try makeScene()
        var arrived = false
        for _ in 0..<60 {
            try scene.world.advance(ticks: 1)
            if scene.world.stationsStoppedAt(by: scene.service) == [scene.a] {
                arrived = true
                break
            }
        }
        XCTAssertTrue(arrived, "Y calls at A; held by \(String(describing: scene.world.trainHoldingRoute(of: scene.service)))")
        guard case .onEdge(let traversal, _)? = scene.world.train(id: scene.service)?.position else { return XCTFail("Y is placed") }
        XCTAssertEqual(traversal.edge, .edge(4), "at P2")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// Only the way into the berth no plan but its own departures runs out
    /// of: the line comes back into P1, so the way into P1 is planned both
    /// ways, and a train bound for B is not let along the loop.
    func testTheWayIntoAFirstCallsOtherBerth() throws {
        let scene = try makeScene()
        let backward = { (edge: Int) in TrackTraversal(edge: .edge(edge), direction: .backward) }
        let y = try XCTUnwrap(scene.world.train(id: scene.service))
        var memo = GameWorld.DirectionMemo()
        let parts = scene.world.opposingParts(for: y, memo: &memo)
        let intoP2 = TrainPath(traversals: [backward(5), backward(4)], end: 40_960, distance: 0)
        XCTAssertEqual(scene.world.firstCallTraversals(along: intoP2, to: scene.a, parts: parts), [backward(5), backward(4)])
        let intoP1 = TrainPath(traversals: [backward(2)], end: 40_960, distance: 0)
        XCTAssertEqual(scene.world.firstCallTraversals(along: intoP1, to: scene.a, parts: parts), [], "the line comes back into P1")
        let b = try XCTUnwrap(scene.world.stations.first { $0.name == "B" }?.id)
        XCTAssertEqual(scene.world.firstCallTraversals(along: intoP2, to: b, parts: parts), [], "only on a way to the first call")
    }
}
