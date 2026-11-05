@testable import GameCore
import XCTest

/// Decision 556, continued (TYMCLIST9): a train of a line with runs in the
/// way of a service waiting for its route (decision 297), sent into a
/// depot (decision 221), goes to the one it reaches soonest of those with
/// a siding for it (decision 280), not only to the one it reaches soonest.
/// On the Taoyuan Airport MRT under the realistic rules, Luzhu's sidings
/// were full each night and Qingpu's half empty: the trains that ended
/// their runs at the airport terminals stayed on the berths the last
/// services were bound for, and the line stood until the morning.
///
///   D2 (Depot) ──── k
///                    ╲
///   D1 (Depot) ────── j ══ A ══════ C ══════ B
///
/// The line calls at A, C and B, runs from A to B at 06:00 and 22:00 and
/// back, and from B to A at 10:00, and keeps its trains in D1 and D2 (in
/// that order). At 10:00 T0 fills D1's one siding, T1 stands at A, where
/// no run leaves for hours, and T2 at B takes the 10:00 run to A, whose
/// one berth T1 stands on: D1 is nearer, D2 has room. Traffic control on,
/// as a new game starts.
final class RunDepotFallbackTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let t1: TrainID
        let t2: TrainID
        let a: StationID
        let c: StationID
        let d1: StationID
        let d2: StationID
    }

    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 131_072, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        let main = try [2_000, 20_000, 40_000, 70_000, 100_000].map { x in
            try world.buildTrackNode(at: WorldCoordinate(x: Int64(x), y: 8_192))
        }
        var edges: [TrackEdgeID] = []
        for (from, to) in zip(main, main.dropFirst()) { edges.append(try world.buildTrackEdge(from: from, to: to)) }
        let d2End = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 7_872))
        let k = try world.buildTrackNode(at: WorldCoordinate(x: 16_800, y: 7_872))
        let branch = try world.buildTrackEdge(from: d2End, to: k)
        _ = try world.buildTrackEdge(from: k, to: main[1], curve: .cubic(PlanPoint(x: 18_400, y: 7_872), PlanPoint(x: 18_400, y: 8_192)))

        let d1 = try world.buildStation(named: "D1", at: PlanPoint(x: 11_000, y: 10_240)).id
        let d2 = try world.buildStation(named: "D2", at: PlanPoint(x: 8_912, y: 5_120)).id
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 30_000, y: 10_240)).id
        let c = try world.buildStation(named: "C", at: PlanPoint(x: 55_000, y: 10_240)).id
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 85_000, y: 10_240)).id
        for (station, edge) in [(d1, edges[0]), (d2, branch), (a, edges[1]), (c, edges[2]), (b, edges[3])] {
            let length = try XCTUnwrap(world.trackEdge(edge)?.length)
            try world.addTrackPlatform(station, on: edge, from: length / 2 - 4_096, to: length / 2 + 4_096)
        }
        try world.setStationDepot(d1, to: true)
        try world.setStationDepot(d2, to: true)

        func run(_ from: Int, _ to: Int, at minute: Int64) -> LineRun {
            LineRun(from: from, to: to, times: (0...abs(to - from)).map { call in
                let seconds = (minute + 20 * Int64(call)) * 60
                return LineRunTime(arrival: seconds, departure: seconds)
            })
        }
        let line = try world.createLine(named: "L", stops: [a, c, b]).id
        try world.setLineRuns(line, to: [
            run(0, 2, at: 360), run(2, 0, at: 360), run(2, 0, at: 600), run(0, 2, at: 1_320), run(2, 0, at: 1_320),
        ])
        try world.setLineDepots(line, to: [d1, d2])
        var ids: [TrainID] = []
        for (name, edge, direction) in [("T0", edges[0], TrackEdgeDirection.forward), ("T1", edges[1], .forward), ("T2", edges[3], .backward)] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            let length = try XCTUnwrap(world.trackEdge(edge)?.length)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: edge, direction: direction), offset: length / 2 + 4_096))
            try world.setTrainContinuation(id, along: [], stoppingAt: length / 2 + 4_096)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            ids.append(id)
        }
        try world.setTrafficControl(true)
        return Scene(world: world, t1: ids[1], t2: ids[2], a: a, c: c, d1: d1, d2: d2)
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

    /// Before, T1 stood at A all day, held for D1's full siding, and T2
    /// waited at C for the berth T1 stood on. Now T1 runs empty into D2,
    /// and T2 reaches A.
    func testATrainInTheWayGoesIntoTheNextDepotWithRoom() throws {
        var scene = try makeScene()
        var waitedAtC = false
        var reachedA = false
        for _ in 0..<60 {
            try scene.world.advance(ticks: 1)
            if scene.world.stationsStoppedAt(by: scene.t2) == [scene.c] { waitedAtC = true }
            if scene.world.stationsStoppedAt(by: scene.t2) == [scene.a] { reachedA = true }
            XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
        }
        XCTAssertTrue(waitedAtC, "T2 called at C")
        XCTAssertTrue(reachedA, "T2 reached A")
        XCTAssertEqual(scene.world.stationsStoppedAt(by: scene.t1), [scene.d2])
        XCTAssertNil(scene.world.train(id: scene.t1)?.execution)
        XCTAssertNil(scene.world.heldDeparture(of: scene.t1))
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
