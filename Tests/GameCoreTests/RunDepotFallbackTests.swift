@testable import GameCore
import XCTest

/// Decision 556, continued (TYMCLIST9): a train of a line with runs sent
/// into a depot (decision 221) goes to the one it reaches soonest of those
/// with a siding for it (decision 280), not only to the one it reaches
/// soonest. On the Taoyuan Airport MRT under the realistic rules, Luzhu's
/// sidings were full each night and Qingpu's half empty: the trains that
/// ended their runs at the airport terminals stayed on the berths the last
/// services were bound for, and the line stood until the morning.
///
///   D1 (Depot) ── n1 ══ A ══════ n2 ══════════ B ══════════ n3 ── D2 (Depot)
///
/// One straight track. The line runs from A to B at 06:00 and 22:00 and
/// back, and keeps its trains in D1 and D2 (in that order). At 10:00 T0
/// fills D1's one siding and T1 stands at A, where no run leaves for
/// hours: D1 is nearer, D2 has room.
final class RunDepotFallbackTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let t1: TrainID
        let a: StationID
        let d1: StationID
        let d2: StationID
    }

    private func makeScene(trafficControl: Bool = true) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 131_072, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        let nodes = try [1_024, 12_288, 40_960, 90_112, 120_832].map { x in
            try world.buildTrackNode(at: WorldCoordinate(x: Int64(x), y: 8_192))
        }
        var edges: [TrackEdgeID] = []
        for (from, to) in zip(nodes, nodes.dropFirst()) { edges.append(try world.buildTrackEdge(from: from, to: to)) }
        let d1 = try world.buildStation(named: "D1", at: PlanPoint(x: 6_144, y: 10_240)).id
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 26_624, y: 10_240)).id
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 65_536, y: 10_240)).id
        let d2 = try world.buildStation(named: "D2", at: PlanPoint(x: 106_496, y: 10_240)).id
        for (station, edge) in [(d1, edges[0]), (a, edges[1]), (b, edges[2]), (d2, edges[3])] {
            let length = try XCTUnwrap(world.trackEdge(edge)?.length)
            try world.addTrackPlatform(station, on: edge, from: length / 2 - 4_096, to: length / 2 + 4_096)
        }
        try world.setStationDepot(d1, to: true)
        try world.setStationDepot(d2, to: true)

        func run(_ from: Int, _ to: Int, at minute: Int64) -> LineRun {
            LineRun(from: from, to: to, times: [
                LineRunTime(arrival: minute * 60, departure: minute * 60), LineRunTime(arrival: (minute + 20) * 60, departure: (minute + 20) * 60),
            ])
        }
        let line = try world.createLine(named: "L", stops: [a, b]).id
        try world.setLineRuns(line, to: [run(0, 1, at: 360), run(1, 0, at: 360), run(0, 1, at: 1_320), run(1, 0, at: 1_320)])
        try world.setLineDepots(line, to: [d1, d2])
        var ids: [TrainID] = []
        for (name, edge) in [("T0", edges[0]), ("T1", edges[1])] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            let length = try XCTUnwrap(world.trackEdge(edge)?.length)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: length / 2 + 4_096))
            try world.setTrainContinuation(id, along: [], stoppingAt: length / 2 + 4_096)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            ids.append(id)
        }
        if trafficControl { try world.setTrafficControl(true) }
        return Scene(world: world, t1: ids[1], a: a, d1: d1, d2: d2)
    }

    /// The scene is the one meant: T0 fills D1, D2 is empty, T1 stands at
    /// A without a service, and D1 is the depot T1 reaches soonest.
    func testTheNearestDepotIsFull() throws {
        let scene = try makeScene()
        let world = scene.world
        let t1 = try XCTUnwrap(world.train(id: scene.t1))
        XCTAssertEqual(world.stationsStoppedAt(by: scene.t1), [scene.a])
        XCTAssertNil(t1.execution)
        XCTAssertFalse(world.depotHasRoom(scene.d1, for: t1))
        XCTAssertTrue(world.depotHasRoom(scene.d2, for: t1))
        let line = try XCTUnwrap(world.lines.first)
        XCTAssertEqual(world.emptyRun(of: line, for: t1, to: line.depots)?.deadhead?.to, scene.d1)
    }

    /// Before, T1 stood at A all day, held for D1's full siding. Now it
    /// runs empty into D2, and is held by nothing on the way.
    func testATrainGoesIntoTheNextDepotWithRoom() throws {
        for trafficControl in [true, false] {
            var scene = try makeScene(trafficControl: trafficControl)
            if trafficControl { XCTAssertNil(scene.world.heldDeparture(of: scene.t1), "not held for D1 with D2 free") }
            for _ in 0..<60 {
                try scene.world.advance(ticks: 1)
                XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
            }
            XCTAssertEqual(scene.world.stationsStoppedAt(by: scene.t1), [scene.d2], "traffic control \(trafficControl)")
            XCTAssertNil(scene.world.train(id: scene.t1)?.execution)
        }
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
