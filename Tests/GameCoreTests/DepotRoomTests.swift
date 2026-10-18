import Foundation
@testable import GameCore
import XCTest

/// Decision 280: under traffic control a train goes into a depot only when
/// a siding there is free for it, beyond those the trains already on their
/// way in will take; a train that finds none stays where its runs left it.
/// The high-speed demo with traffic control and block sections lost its
/// north end this way: at 00:20 THSR 13 of the all-stops line and THSR 22
/// of the nine-stop line were sent into Nangang's depot in the same minute
/// with one siding left. THSR 13 took it; THSR 22 stood at Nangang's
/// platform waiting for a siding, and the sets on their way to Nangang
/// waited at Taipei behind it until the morning.
///
///                                   ┌──e2── PA1 (A)
///   B ──e0────────── n1 ──e1──────── J ┤
///   D1 (Depot) ──e5──┐  /              └──e3── PA2 (A)
///   D2 (Depot) ──e6── K ─e4
///
/// The lines Up and Down both run from B to A at 06:00 and 22:00 and back,
/// and keep their trains in Depot. At 10:00 T0 stands in D2, T1 (Up's) at
/// PA1 and T2 (Down's) at PA2, and no run leaves A for hours, so each line
/// sends its train in; only D1 is free. A train sent in waits out its
/// least dwell before it sets off, so the second line, a moment after the
/// first, found D1 still free and sent its train after the same siding.
final class DepotRoomTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private let t1 = TrainID(rawValue: 2)
    private let t2 = TrainID(rawValue: 3)

    private struct Scene {
        var world: GameWorld
        let a: StationID
        let depot: StationID
    }

    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 106_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        // Every turnout within 1 in 16 of straight on (see `TrackNodeEnd`).
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: 8_192))
        let junction = try world.buildTrackNode(at: WorldCoordinate(x: 57_344, y: 8_192))
        let pa1 = try world.buildTrackNode(at: WorldCoordinate(x: 98_304, y: 10_240))
        let pa2 = try world.buildTrackNode(at: WorldCoordinate(x: 98_304, y: 6_144))
        let k = try world.buildTrackNode(at: WorldCoordinate(x: 20_480, y: 7_168))
        let d1 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 6_144))
        let d2 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 5_120))
        try world.buildTrackEdge(from: start, to: n1)     // e0
        try world.buildTrackEdge(from: n1, to: junction)  // e1
        try world.buildTrackEdge(from: junction, to: pa1) // e2
        try world.buildTrackEdge(from: junction, to: pa2) // e3
        try world.buildTrackEdge(from: n1, to: k)         // e4
        try world.buildTrackEdge(from: k, to: d1)         // e5
        try world.buildTrackEdge(from: k, to: d2)         // e6
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 4_096, y: 10_240)).id
        try world.addTrackPlatform(b, on: .edge(1), from: 1_024, to: 9_216)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 77_824, y: 8_192)).id
        let depot = try world.buildStation(named: "Depot", at: PlanPoint(x: 8_192, y: 2_048)).id
        for (station, edges) in [(a, [3, 4]), (depot, [6, 7])] {
            for edge in edges {
                let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
                try world.addTrackPlatform(station, on: .edge(edge), from: length - 10_240, to: length - 2_048)
            }
        }
        try world.setStationDepot(depot, to: true)

        func run(_ from: Int, _ to: Int, at minute: Int64) -> LineRun {
            LineRun(from: from, to: to, times: [
                LineRunTime(arrival: minute * 60, departure: minute * 60), LineRunTime(arrival: (minute + 10) * 60, departure: (minute + 10) * 60),
            ])
        }
        var lines: [LineID] = []
        for name in ["Up", "Down"] {
            let line = try world.createLine(named: name, stops: [b, a]).id
            try world.setLineRuns(line, to: [run(0, 1, at: 360), run(1, 0, at: 360), run(0, 1, at: 1_320), run(1, 0, at: 1_320)])
            try world.setLineDepots(line, to: [depot])
            lines.append(line)
        }
        // T0 (Up's) in D2; T1 (Up's) at PA1 and T2 (Down's) at PA2, as
        // their runs left them.
        for (name, edge, line) in [("T0", 7, lines[0]), ("T1", 3, lines[0]), ("T2", 4, lines[1])] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: length - 2_048))
            try world.setTrainContinuation(id, along: [], stoppingAt: length - 2_048)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
        }
        try world.setTrafficControl(true)
        world.setBlockSections(true)
        return Scene(world: world, a: a, depot: depot)
    }

    /// The trains standing in the depot or on their way into it.
    private func inOrBound(_ scene: Scene) -> Int {
        scene.world.trains.count { train in
            train.execution == nil ? scene.world.stationsStoppedAt(by: train.id).contains(scene.depot) : train.timetable.last?.station == scene.depot
        }
    }

    /// One of T1 and T2 goes into D1; the other stays at A without a
    /// service, never sent towards a depot with no siding left for it.
    func testUnderTrafficControlATrainGoesIntoADepotOnlyWithASidingLeft() throws {
        var scene = try makeScene()
        for _ in 0..<30 {
            try scene.world.advance(ticks: 1)
            XCTAssertLessThanOrEqual(inOrBound(scene), 2, "at minute \(scene.world.clock.now.minute): more trains in or bound for the depot than its two sidings")
        }
        let atA = scene.world.trains.filter { scene.world.stationsStoppedAt(by: $0.id) == [scene.a] }
        XCTAssertEqual(atA.count, 1, "one stays at A")
        XCTAssertNil(atA.first?.execution, "without a service")
        XCTAssertEqual(scene.world.trains.count { scene.world.stationsStoppedAt(by: $0.id) == [scene.depot] }, 2, "the depot is full")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The train that stayed at A takes its line's 22:00 run from A.
    func testTheTrainThatStayedTakesTheEveningRun() throws {
        var scene = try makeScene()
        try scene.world.advance(ticks: 30)
        let stayed = try XCTUnwrap(scene.world.trains.first { scene.world.stationsStoppedAt(by: $0.id) == [scene.a] })
        try scene.world.advance(ticks: 12 * 60 - 30 + 1)
        XCTAssertEqual(scene.world.train(id: stayed.id)?.timetable.first?.station, scene.a, "it runs from A")
        XCTAssertEqual(scene.world.train(id: stayed.id)?.timetable.first?.departure, GameTime(minutes: 1_320), "at 22:00")
        XCTAssertNotNil(scene.world.train(id: stayed.id)?.execution)
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The trains go in at whole minutes, so a batch ends where minute by
    /// minute does.
    func testABatchEndsWhereMinutesDo() throws {
        let scene = try makeScene()
        var single = scene.world
        for _ in 0..<(13 * 60) { try single.advance(ticks: 1) }
        var batched = scene.world
        try batched.advance(ticks: 13 * 60)
        XCTAssertEqual(batched, single)
    }
}
