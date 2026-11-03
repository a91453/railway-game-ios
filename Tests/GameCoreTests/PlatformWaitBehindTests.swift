import Foundation
@testable import GameCore
import XCTest

/// Decision 558: with traffic control off, a train of real runs does not
/// wait for a platform (decision 228) that another train is due on when
/// that train can only come to it past this one: its way ahead runs over
/// the track this one stands on. The Taoyuan Airport MRT bought under the
/// simple rules (decision 556) stopped this way at Chang Gung Memorial
/// Hospital before six in the morning: the train starting its run there
/// for Taipei at 05:56 waited for its platform at the National Taiwan
/// Sport University, which an empty run out of the Luzhu depot was due on,
/// and that empty run stood behind it on the same track all day.
///
///   P1 (T) ──┐
///            j ──────── H ──────────── E ──
///   P2 (T) ──┘
///
/// S stands at H for its run to T at 06:00, due there at 06:06. D runs E to
/// T at 05:50, not calling at H, due at T at 06:05 and out of it again at
/// 06:10, and is bound for P1, as P2 is taken: W stands there for its run
/// at 06:40. When S is due to leave, P1 is D's until 06:13, within
/// fifteen minutes (``GameWorld/platformHold``), but D is behind S on the
/// single track and cannot come to P1 before S has gone.
final class PlatformWaitBehindTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let s: TrainID
        let d: TrainID
        let t: StationID
        let h: StationID
    }

    private func run(_ from: Int, _ to: Int, at minute: Int64, taking minutes: Int64) -> LineRun {
        LineRun(from: from, to: to, times: [
            LineRunTime(arrival: minute * 60, departure: minute * 60), LineRunTime(arrival: (minute + minutes) * 60, departure: (minute + minutes) * 60),
        ])
    }

    private func makeScene(trafficControl: Bool = false) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 200_704, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 5 * 60 + 49), speed: .normal)
        )
        // Every turnout within 1 in 16 of straight on (see `TrackNodeEnd`).
        let p1 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 9_216))
        let p2 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j = try world.buildTrackNode(at: WorldCoordinate(x: 20_480, y: 8_192))
        let x = try world.buildTrackNode(at: WorldCoordinate(x: 102_400, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 198_656, y: 8_192))
        try world.buildTrackEdge(from: p1, to: j)   // e1, P1
        try world.buildTrackEdge(from: p2, to: j)   // e2, P2
        try world.buildTrackEdge(from: j, to: x)    // e3, H
        try world.buildTrackEdge(from: x, to: east) // e4, E
        let t = try world.buildStation(named: "T", at: PlanPoint(x: 6_144, y: 12_288)).id
        let h = try world.buildStation(named: "H", at: PlanPoint(x: 71_680, y: 12_288)).id
        let e = try world.buildStation(named: "E", at: PlanPoint(x: 153_600, y: 12_288)).id
        for (station, edge, from, to) in [(t, 1, 2_048, 14_336), (t, 2, 2_048, 14_336), (h, 3, 40_960, 61_440), (e, 4, 40_960, 61_440)] {
            try world.addTrackPlatform(station, on: .edge(edge), from: Int64(from), to: Int64(to))
        }
        try world.setTrafficControl(trafficControl)
        let performance = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 8)
        let local = try world.createLine(named: "Local", stops: [h, t]).id
        try world.setLineRuns(local, to: [run(0, 1, at: 360, taking: 6)])
        let express = try world.createLine(named: "Express", stops: [e, t]).id
        try world.setLineRuns(express, to: [run(0, 1, at: 350, taking: 15), run(1, 0, at: 370, taking: 15)])
        let branch = try world.createLine(named: "Branch", stops: [t, h]).id
        try world.setLineRuns(branch, to: [run(0, 1, at: 400, taking: 6)])
        var ids: [TrainID] = []
        // S at H and D at E facing west, W on P2 facing east.
        for (name, traversal, at, line) in [
            ("S", TrackTraversal(edge: .edge(3), direction: .backward), Int64(40_960), local),
            ("D", TrackTraversal(edge: .edge(4), direction: .backward), Int64(55_296), express),
            ("W", TrackTraversal(edge: .edge(2), direction: .forward), Int64(14_336), branch),
        ] {
            try world.setLinePerformance(line, to: performance)
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(traversal, offset: at))
            try world.setTrainContinuation(id, along: [], stoppingAt: at)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            ids.append(id)
        }
        return Scene(world: world, s: ids[0], d: ids[1], t: t, h: h)
    }

    /// D sets off for P1, the free one, and comes up behind S at H.
    func testTheEmptyPlatformIsBookedByTheTrainBehind() throws {
        var scene = try makeScene()
        try scene.world.advance(ticks: 2)
        let d = try XCTUnwrap(scene.world.train(id: scene.d))
        guard case .travellingToStop? = d.execution else { return XCTFail("D is on its way: \(String(describing: d.execution))") }
        XCTAssertEqual(d.movement.edges.last, .edge(1), "bound for P1")
        XCTAssertTrue(d.movement.remainingEdges.contains(.edge(3)), "past H, where S stands")
    }

    /// S leaves at 06:00 and is at T by 06:09; D has followed it past H.
    /// Before, S waited at H for P1 to come free of D, and D, behind it,
    /// never came.
    func testTheTrainAheadLeavesAndTheOneBehindFollows() throws {
        var scene = try makeScene()
        for _ in 0..<20 { try scene.world.advance(ticks: 1) }
        XCTAssertEqual(scene.world.stationsStoppedAt(by: scene.s), [scene.t], "S has come to T")
        let d = try XCTUnwrap(scene.world.train(id: scene.d))
        guard case .onEdge(let traversal, let offset)? = d.position else { return XCTFail("D is on the track") }
        XCTAssertTrue(traversal.edge == .edge(1) || (traversal.edge == .edge(3) && offset > 40_960), "D is past H: \(traversal) @\(offset)")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The trains change their way at the services' phase, so a minute in
    /// one step leaves them where sixty one-second steps do (decision 37).
    func testAMinuteInOneStepIsSixtyOneSecondSteps() throws {
        var whole = try makeScene().world
        var seconds = whole
        seconds.setSpeed(.x10)
        for minute in 1...40 {
            try whole.advance(ticks: 1)
            try seconds.advance(ticks: 60)
            XCTAssertEqual(whole.trains, seconds.trains, "minute \(minute)")
            if whole.trains != seconds.trains { break }
        }
    }
}
