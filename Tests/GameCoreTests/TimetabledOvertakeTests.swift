import Foundation
@testable import GameCore
import XCTest

/// Decision 294: under traffic control two services of lines with runs
/// whose timetables have the slow one call at a station while the fast one
/// overtakes it there (it arrives first and is due to leave after the
/// fast one has passed) are planned as an overtake: the slow one waits on
/// a siding until the fast one has passed, even when the fast one runs
/// late. Before, the plan (decision 59) found only trains that would meet
/// between two points, so a real timetable's overtakes were never planned
/// and a late express followed the stopping train to the next station.
///
///                                 ┌─e4─ L1 ──e5 (X)── L2 ─e6─┐       ┌──e8── Q1 (Q)
///   W ──e0──┐                     │                          │       │
///           J0 ──e2── J1 ─────────┴──────── e3 (X) ──────────┴─ J2 ──e7── J3
///   P ──e1──┘                                                         └──e9── Q2 (Q)
///
/// Edge `en` is `.edge(n + 1)`. Slow (P, X, Q) leaves P at 10:15, calls
/// at X 10:18–10:22 and reaches Q at 10:28; Fast (W, Q) leaves W at 10:19
/// and reaches Q at 10:22, passing X at about 10:21.
final class TimetabledOvertakeTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let x: StationID
        let q: StationID
        let slow: TrainID
        let fast: TrainID
    }

    private func at(_ minute: Int64, _ second: Int64 = 0) -> LineRunTime {
        LineRunTime(arrival: minute * 60 + second, departure: minute * 60 + second)
    }

    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 262_144, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        // Every turnout within 1 in 16 of straight on (see `TrackNodeEnd`).
        let w = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let p = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 6_144))
        let j0 = try world.buildTrackNode(at: WorldCoordinate(x: 41_984, y: 8_192))
        let j1 = try world.buildTrackNode(at: WorldCoordinate(x: 82_944, y: 8_192))
        let l1 = try world.buildTrackNode(at: WorldCoordinate(x: 103_424, y: 9_216))
        let l2 = try world.buildTrackNode(at: WorldCoordinate(x: 144_384, y: 9_216))
        let j2 = try world.buildTrackNode(at: WorldCoordinate(x: 164_864, y: 8_192))
        let j3 = try world.buildTrackNode(at: WorldCoordinate(x: 205_824, y: 8_192))
        let q1 = try world.buildTrackNode(at: WorldCoordinate(x: 246_784, y: 10_240))
        let q2 = try world.buildTrackNode(at: WorldCoordinate(x: 246_784, y: 6_144))
        try world.buildTrackEdge(from: w, to: j0)   // e0
        try world.buildTrackEdge(from: p, to: j0)   // e1
        try world.buildTrackEdge(from: j0, to: j1)  // e2
        try world.buildTrackEdge(from: j1, to: j2)  // e3: X's main
        try world.buildTrackEdge(from: j1, to: l1)  // e4
        try world.buildTrackEdge(from: l1, to: l2)  // e5: X's siding
        try world.buildTrackEdge(from: l2, to: j2)  // e6
        try world.buildTrackEdge(from: j2, to: j3)  // e7
        try world.buildTrackEdge(from: j3, to: q1)  // e8
        try world.buildTrackEdge(from: j3, to: q2)  // e9
        func platform(_ station: StationID, on edge: Int, middle: Bool = false, back: Int64 = 2_048) throws {
            let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
            if back > 2_048 {
                try world.addTrackPlatform(station, on: .edge(edge), from: length - back - 8_192, to: length - back)
            } else if middle {
                try world.addTrackPlatform(station, on: .edge(edge), from: length / 2 - 4_096, to: length / 2 + 4_096)
            } else {
                try world.addTrackPlatform(station, on: .edge(edge), from: length - 10_240, to: length - 2_048)
            }
        }
        let wStation = try world.buildStation(named: "W", at: PlanPoint(x: 4_096, y: 10_240)).id
        let pStation = try world.buildStation(named: "P", at: PlanPoint(x: 4_096, y: 4_096)).id
        let x = try world.buildStation(named: "X", at: PlanPoint(x: 123_904, y: 12_288)).id
        let q = try world.buildStation(named: "Q", at: PlanPoint(x: 240_000, y: 12_288)).id
        // W's and P's trains stand clear of the turnout at J0.
        try platform(wStation, on: 1, back: 12_288)
        try platform(pStation, on: 2, back: 12_288)
        try platform(x, on: 4, middle: true)
        try platform(x, on: 6, middle: true)
        try platform(q, on: 9)
        try platform(q, on: 10)
        let slowLine = try world.createLine(named: "Slow", stops: [pStation, x, q]).id
        try world.setLineRuns(slowLine, to: [LineRun(from: 0, to: 2, times: [at(615), LineRunTime(arrival: 618 * 60, departure: 622 * 60), at(628)])])
        let fastLine = try world.createLine(named: "Fast", stops: [wStation, q]).id
        try world.setLineRuns(fastLine, to: [LineRun(from: 0, to: 1, times: [at(619), at(622)])])
        func train(_ name: String, on edge: Int, line: LineID) throws -> TrainID {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: length - 12_288))
            try world.setTrainContinuation(id, along: [], stoppingAt: length - 12_288)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            return id
        }
        let slow = try train("S", on: 2, line: slowLine)
        let fast = try train("F", on: 1, line: fastLine)
        try world.setTrafficControl(true)
        world.setBlockSections(true)
        return Scene(world: world, x: x, q: q, slow: slow, fast: fast)
    }

    /// Advances `world` to minute `minute`, a minute at a time or at once,
    /// and holds Fast at W from 10:18 to 10:23 (its rate 0), so it runs
    /// about three minutes late.
    private func run(_ world: inout GameWorld, fast: TrainID, to minute: Int64, batched: Bool) throws {
        let steps: [(until: Int64, rate: Int64?)] = [(618, 0), (623, 4_096), (minute, nil)]
        for step in steps {
            let ticks = Int(step.until - world.clock.now.minute)
            if batched {
                if ticks > 0 { try world.advance(ticks: ticks) }
            } else {
                for _ in 0..<max(ticks, 0) { try world.advance(ticks: 1) }
            }
            if let rate = step.rate { try world.setTrainMovementRate(fast, to: rate) }
        }
    }

    /// The plan has Slow wait at X for Fast, as the timetables have it.
    func testTheTimetablesOvertakeIsPlanned() throws {
        var scene = try makeScene()
        try scene.world.advance(ticks: 15)
        let waits = scene.world.scheduledTrafficWaits()
        XCTAssertTrue(
            waits.contains { $0.kind == .overtake && $0.train == scene.slow && $0.station == scene.x && $0.other == scene.fast },
            "Slow waits at X for Fast: \(waits)"
        )
    }

    /// Fast runs late: Slow, on X's siding, lets it pass before it leaves,
    /// and Fast reaches Q first, minutes before Slow is due there.
    func testALateExpressPassesTheStoppingTrain() throws {
        var scene = try makeScene()
        let siding: Set<TrackEdgeID> = [.edge(5), .edge(6), .edge(7)]
        try run(&scene.world, fast: scene.fast, to: 620, batched: false)
        if case .onEdge(let traversal, _)? = scene.world.train(id: scene.slow)?.position {
            XCTAssertTrue(siding.contains(traversal.edge), "Slow stands on X's siding: \(traversal)")
        }
        var fastAtQ: GameTime?, slowAtQ: GameTime?
        for _ in 620..<640 {
            try scene.world.advance(ticks: 1)
            if fastAtQ == nil, scene.world.stationsStoppedAt(by: scene.fast).contains(scene.q) { fastAtQ = scene.world.clock.now }
            if slowAtQ == nil, scene.world.stationsStoppedAt(by: scene.slow).contains(scene.q) { slowAtQ = scene.world.clock.now }
        }
        let fastQ = try XCTUnwrap(fastAtQ, "Fast reached Q")
        let slowQ = try XCTUnwrap(slowAtQ, "Slow reached Q")
        XCTAssertLessThan(fastQ, slowQ, "Fast reached Q before Slow (Fast at minute \(fastQ.minute), Slow at \(slowQ.minute))")
        XCTAssertLessThanOrEqual(fastQ.minute, 626, "Fast was not held behind Slow (Fast at minute \(fastQ.minute), Slow at \(slowQ.minute))")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The same, a minute at a time and in batches.
    func testBatchesMatchMinutes() throws {
        let scene = try makeScene()
        var single = scene.world, batched = scene.world
        try run(&single, fast: scene.fast, to: 640, batched: false)
        try run(&batched, fast: scene.fast, to: 640, batched: true)
        XCTAssertEqual(batched, single)
    }
}
