import Foundation
@testable import GameCore
import XCTest

/// Decision 285: a block ends only where a train standing there is clear
/// of every other track. The high-speed demo's up track joins the down
/// track over a ramp of 100 m short of Zuoying, and a node 50 m out, laid
/// for Zuoying's depot lead (decision 281), ended a block. With traffic
/// control and block sections, a set following another into Zuoying
/// stopped there when its berth was taken, fouling the up track, the way
/// out for the set on that berth: each waited for the other, and the sets
/// behind them back to Taichung.
///
///   R          R2                                        T1 (P1)    Y
///   ══e1═══════════════════════════ b ─e2─ J ─e3─ K ─e4──────── Z ─e8─
///   U  ──e7──────────────────────────────── c ╱e6      ╲e5── T2 (P2)
///
/// e1 runs east 6 km to b, 50 m short of J, where the ramp e6 from the up
/// track e7, 5 m to the side, joins. e5 leaves K for T2. P1 lies 500 m
/// beyond K (farther from b than a following train keeps back), and the
/// siding Y beyond it. L runs from R2 to T2; D from R to T1 follows it.
/// Once D has set off, I runs from Y onto P1, then on west to U along e6
/// and e7. D stops where its block ends, short of P1: before, at b,
/// which fouls e6, so I could never leave and D never reach P1.
final class ClearBlockBoundaryTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    private static let y: Int64 = 8_192
    private static let main: Int64 = 384_000

    private struct Scene {
        var world: GameWorld
        let d: TrainID
        let i: TrainID
        let t1: StationID
        let u: StationID
    }

    private func makeScene() throws -> Scene {
        let y = Self.y
        var world = try GameWorld(
            bounds: WorldBounds(width: 491_520, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: y))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Self.main, y: y))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Self.main + 3_200, y: y))
        let k = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Self.main + 9_600, y: y))
        let z = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Self.main + 73_600, y: y))
        let p2 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Self.main + 48_000, y: y + 1_536))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Self.main - 3_200, y: y - 320))
        let w = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: y - 320))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Self.main + 99_200, y: y))
        try world.buildTrackEdge(from: a, to: b)   // e1
        try world.buildTrackEdge(from: b, to: j)   // e2
        try world.buildTrackEdge(from: j, to: k)   // e3
        try world.buildTrackEdge(from: k, to: z)   // e4
        try world.buildTrackEdge(from: k, to: p2)  // e5
        try world.buildTrackEdge(from: j, to: c)   // e6
        try world.buildTrackEdge(from: w, to: c)   // e7
        try world.buildTrackEdge(from: z, to: end) // e8

        let r = try world.buildStation(named: "R", at: PlanPoint(x: 12_288, y: y + 2_048)).id
        try world.addTrackPlatform(r, on: .edge(1), from: 1_024, to: 21_504)
        let r2 = try world.buildStation(named: "R2", at: PlanPoint(x: 150_000, y: y + 2_048)).id
        try world.addTrackPlatform(r2, on: .edge(1), from: 140_000, to: 160_000)
        let t1 = try world.buildStation(named: "T1", at: PlanPoint(x: 1_024 + Self.main + 54_400, y: y + 2_048)).id
        try world.addTrackPlatform(t1, on: .edge(4), from: 32_000, to: 57_600)
        let t2 = try world.buildStation(named: "T2", at: PlanPoint(x: 1_024 + Self.main + 30_000, y: y + 3_072)).id
        let e5 = try XCTUnwrap(world.trackEdge(.edge(5))?.length)
        try world.addTrackPlatform(t2, on: .edge(5), from: e5 - 25_600, to: e5 - 1_024)
        let yard = try world.buildStation(named: "Y", at: PlanPoint(x: 1_024 + Self.main + 86_400, y: y + 2_048)).id
        try world.addTrackPlatform(yard, on: .edge(8), from: 6_400, to: 19_200)
        let u = try world.buildStation(named: "U", at: PlanPoint(x: 20_480, y: y - 2_048)).id
        try world.addTrackPlatform(u, on: .edge(7), from: 10_240, to: 30_720)

        func train(_ name: String, at position: TrainPosition, stops: [(StationID, Int64, Int64)]) throws -> TrainID {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: position)
            guard case .onEdge(_, let offset) = position else { preconditionFailure() }
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.setTrainTimetable(id, to: stops.map {
                ScheduledStop(station: $0.0, arrival: GameTime(minutes: $0.1), departure: GameTime(minutes: $0.2))
            })
            return id
        }
        let e8 = try XCTUnwrap(world.trackEdge(.edge(8))?.length)
        let l = try train("L", at: .onEdge(forward(1), offset: 160_000), stops: [(r2, 0, 1), (t2, 15, 15)])
        let d = try train("D", at: .onEdge(forward(1), offset: 21_504), stops: [(r, 0, 2), (t1, 15, 15)])
        let i = try train("I", at: .onEdge(backward(8), offset: e8 - 6_400), stops: [(yard, 0, 3), (t1, 8, 25), (u, 45, 45)])
        world.setBlockSections(true)
        try world.setTrafficControl(true)
        for id in [l, d, i] {
            try world.startTrainService(id)
        }
        return Scene(world: world, d: d, i: i, t1: t1, u: u)
    }

    /// The end of e1 is 50 m short of J, where the ramp from the up track
    /// is within 4 m of the down track: no block ends there, and the one
    /// before it, 1.5 km back, is the last on the way to J. Before, b did.
    func testNoBlockEndsWhereATrainFoulsTheRampOfATurnout() throws {
        var world = try makeScene().world
        let probe = try world.purchaseTrain(named: "P").id
        try world.placeTrain(probe, at: .onEdge(forward(1), offset: 200_000))
        try world.setTrainContinuation(probe, along: [forward(2), forward(3), forward(4)], stoppingAt: 57_600)
        let e = world.authorityEnvelopes(of: try XCTUnwrap(world.train(id: probe)))
        // From the head: e1's 288,000 is 88,000 on; b, 184,000 on, would
        // have been the next; e2, J, K and e4 bound none before the end.
        XCTAssertEqual(world.blockBoundary(e, atOrBefore: Self.main - 200_000), 88_000)
        XCTAssertEqual(world.blockBoundary(e, atOrBefore: e.length - 1), 88_000)
        XCTAssertNil(world.blockBoundary(e, after: 88_000))
    }

    /// D follows L, then waits short of P1, which I took after D set off.
    /// I leaves at 25:00 along e6, D reaches T1 and I reaches U, and no
    /// train is ever deadlocked. Before, D waited at b, fouling e6, and
    /// both waited for each other for good.
    func testATrainWaitingForATakenBerthLeavesTheWayOutClear() throws {
        var scene = try makeScene()
        var deadlocked: [TrainID] = []
        var dReached = false, iReached = false
        for _ in 0..<60 {
            try scene.world.advance(ticks: 1)
            deadlocked = Array(Set(deadlocked).union(scene.world.deadlockedTrains())).sorted()
            if scene.world.stationsStoppedAt(by: scene.d).contains(scene.t1) { dReached = true }
            if scene.world.stationsStoppedAt(by: scene.i).contains(scene.u) { iReached = true }
        }
        XCTAssertEqual(deadlocked, [], "no deadlock")
        XCTAssertTrue(dReached, "D calls at T1; held by \(String(describing: scene.world.trainHoldingRoute(of: scene.d)))")
        XCTAssertTrue(iReached, "I calls at U; held by \(String(describing: scene.world.trainHoldingRoute(of: scene.i)))")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The same hour stepped a minute at a time and in one batch gives
    /// the same world.
    func testAnHourInOneBatchIsAnHourMinuteByMinute() throws {
        var byMinute = try makeScene().world
        var batch = byMinute
        for _ in 0..<60 {
            try byMinute.advance(ticks: 1)
        }
        try batch.advance(ticks: 60)
        XCTAssertEqual(batch, byMinute)
    }
}
