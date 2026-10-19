import Foundation
@testable import GameCore
import XCTest

/// Decision 282: with traffic control off, a train of real runs bound for a
/// terminus's platform track another train is still pulling out of, coming
/// towards it, goes to a free platform. The high-speed demo built over the
/// real ground stopped at 08:25 at Nangang this way (decision 281): THSR 8,
/// leaving platform track 1914 late, stood at the far end of it waiting for
/// the throat; THSR 27, late too, came in through the throat for the same
/// track, which had looked free when it left Taipei since THSR 8 was due to
/// have gone; each waited for the other all day.
///
///   B1 (B) ──┐                            ┌── P1 (A) ── e4
///            k ──────────── S ─────────── j
///   B2 (B) ──┘                            └── P2 (A) ── e5
///
/// One line runs between B and A. X runs B to A at 05:50, arriving at
/// 06:00, and back at 06:05; Y runs B to A at 06:01, due at 06:11. When Y
/// leaves B both of A's platforms are free over its time there (X is due
/// to have left P1 by 06:05), so it is bound for P1, the nearer. X leaves
/// P1 for B as Y comes along the single track S: both are on the track
/// the other runs, so neither waits for the other (decision 228), and they
/// met at P1's end.
final class TerminusPlatformTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let x: TrainID
        let y: TrainID
        let a: StationID
        let b: StationID
        let p1: TrackEdgeID
        let p2: TrackEdgeID
    }

    private func run(_ from: Int, _ to: Int, at minute: Int64, taking minutes: Int64) -> LineRun {
        LineRun(from: from, to: to, times: [
            LineRunTime(arrival: minute * 60, departure: minute * 60), LineRunTime(arrival: (minute + minutes) * 60, departure: (minute + minutes) * 60),
        ])
    }

    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 200_704, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 5 * 60 + 58), speed: .normal)
        )
        // Every turnout within 1 in 16 of straight on (see `TrackNodeEnd`).
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let k = try world.buildTrackNode(at: WorldCoordinate(x: 20_480, y: 8_192))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 102_400, y: 8_192))
        let p1 = try world.buildTrackNode(at: WorldCoordinate(x: 129_024, y: 9_728))
        let p2 = try world.buildTrackNode(at: WorldCoordinate(x: 129_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 198_656, y: 8_192))
        try world.buildTrackEdge(from: west, to: k) // e1, B
        try world.buildTrackEdge(from: k, to: j)    // e2, S
        try world.buildTrackEdge(from: j, to: p1)   // e3, P1
        try world.buildTrackEdge(from: j, to: p2)   // e4, P2
        try world.buildTrackEdge(from: p2, to: east) // e5, to C
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 4_096, y: 12_288)).id
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 120_832, y: 12_288)).id
        let c = try world.buildStation(named: "C", at: PlanPoint(x: 190_464, y: 12_288)).id
        for (station, edge, from, to) in [(b, 1, 2_048, 17_408), (a, 3, 2_048, 18_432), (a, 4, 8_192, 24_576), (c, 5, 49_152, 67_584)] {
            try world.addTrackPlatform(station, on: .edge(edge), from: Int64(from), to: Int64(to))
        }
        try world.setTrafficControl(false)
        let performance = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 8)
        let main = try world.createLine(named: "Main", stops: [b, a]).id
        try world.setLinePerformance(main, to: performance)
        try world.setLineRuns(main, to: [run(0, 1, at: 360, taking: 12), run(1, 0, at: 365, taking: 12)])
        let branch = try world.createLine(named: "Branch", stops: [a, c]).id
        try world.setLinePerformance(branch, to: performance)
        try world.setLineRuns(branch, to: [run(0, 1, at: 366, taking: 6)])
        var ids: [TrainID] = []
        for (name, edge, at, line) in [("X", 3, Int64(18_432), main), ("W", 4, Int64(24_576), branch), ("Y", 1, Int64(17_408), main)] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: .forward), offset: at))
            try world.setTrainContinuation(id, along: [], stoppingAt: at)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            ids.append(id)
        }
        return Scene(world: world, x: ids[0], y: ids[2], a: a, b: b, p1: .edge(3), p2: .edge(4))
    }

    /// Pairs of trains whose bodies lie on one edge at once.
    private func meetings(in world: GameWorld) -> [String] {
        var on: [TrackEdgeID: [(TrainID, Int64, Int64, TrackEdgeDirection)]] = [:]
        for train in world.trains {
            for stretch in world.bodyStretches(of: train) where stretch.to > stretch.from {
                guard let length = world.network.edge(stretch.traversal.edge)?.length else { continue }
                let (low, high) = stretch.traversal.direction == .forward ? (stretch.from, stretch.to) : (length - stretch.to, length - stretch.from)
                on[stretch.traversal.edge, default: []].append((train.id, low, high, stretch.traversal.direction))
            }
        }
        var found: [String] = []
        for (edge, trains) in on.sorted(by: { $0.key < $1.key }) {
            for i in trains.indices {
                for j in trains.indices where j > i && trains[i].0 != trains[j].0 {
                    let facing = trains[i].3 != trains[j].3
                    if facing || min(trains[i].2, trains[j].2) > max(trains[i].1, trains[j].1) {
                        let names = [trains[i].0, trains[j].0].map { world.train(id: $0)?.name ?? "?" }
                        found.append("\(names[0]) and \(names[1]) on \(edge)\(facing ? ", facing" : "")")
                    }
                }
            }
        }
        return found
    }

    /// When Y sets off from B, A's two platforms are free over its time
    /// there, X due to have left P1, so it is bound for P1.
    func testTheArrivingTrainIsFirstBoundForTheTrackTheOtherLeaves() throws {
        var scene = try makeScene()
        try scene.world.advance(ticks: 3)
        let y = try XCTUnwrap(scene.world.train(id: scene.y))
        guard case .travellingToStop? = y.execution else { return XCTFail("Y is on its way: \(String(describing: y.execution))") }
        XCTAssertEqual(y.movement.edges.last, scene.p1)
    }

    /// X leaves P1 for B as Y comes along the single track bound for P1:
    /// Y goes to P2 instead, X waits for it at the throat, and neither
    /// meets the other on any edge, second by second.
    func testATrainBoundForATrackAnotherIsLeavingTowardsItGoesToAFreeOne() throws {
        var world = try makeScene().world
        let scene = try makeScene()
        world.setSpeed(.x10)
        var met: [String] = []
        for second in 1...(30 * 60) {
            try world.advance(ticks: 1)
            let now = meetings(in: world)
            if !now.isEmpty, met.isEmpty { met = now.map { "\($0) at second \(second)" } }
        }
        XCTAssertEqual(met, [], "two trains on one edge")
        XCTAssertEqual(world.stationsStoppedAt(by: scene.y), [scene.a], "Y has come in")
        XCTAssertEqual(world.train(id: scene.y).flatMap { if case .onEdge(let traversal, _)? = $0.position { traversal.edge } else { nil } }, scene.p2, "at P2")
        XCTAssertEqual(world.stationsStoppedAt(by: scene.x), [scene.b], "X has gone on to B")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// The trains change their way at the services' phase, so a minute in
    /// one step leaves them where sixty one-second steps do (decision 37).
    func testAMinuteInOneStepIsSixtyOneSecondSteps() throws {
        var whole = try makeScene().world
        var seconds = whole
        seconds.setSpeed(.x10)
        for minute in 1...30 {
            try whole.advance(ticks: 1)
            try seconds.advance(ticks: 60)
            XCTAssertEqual(whole.trains, seconds.trains, "minute \(minute)")
            if whole.trains != seconds.trains { break }
        }
    }
}
