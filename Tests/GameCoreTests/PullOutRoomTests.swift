import Foundation
@testable import GameCore
import XCTest

/// Decision 290: under traffic control a line with runs sends a train out
/// of a depot to a stop only when the stop has a berth for it, one no
/// train stands on or is bound for beyond those the trains already sent
/// out will take, and the train runs to a free berth.
///
/// The high-speed demo built over the ground, with traffic control and
/// block sections, lost its south end this way at night: at 21:53 THSR 8
/// and at 21:57 THSR 24 came out of Zuoying's depot, both routed to the
/// one free track `end5`. THSR 8 took it and stood there without a run;
/// THSR 24 stood on the depot's single lead waiting for it, and the sets
/// at Zuoying could not go into the depot past it until the morning.
///
///                                   ┌──e2── PA1 (A)
///   B ──e0────────── n1 ──e1──────── J ┤
///   D1 (Depot) ──e5──┐  /              └──e3── PA2 (A)
///   D2 (Depot) ──e6── K ─e4
///
/// Edge `en` is `.edge(n + 1)`.
final class PullOutRoomTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private struct Scene {
        var world: GameWorld
        let a: StationID
        let depot: StationID
        var trains: [String: TrainID]
    }

    private func run(_ from: Int, _ to: Int, at minute: Int64) -> LineRun {
        LineRun(from: from, to: to, times: [
            LineRunTime(arrival: minute * 60, departure: minute * 60), LineRunTime(arrival: (minute + 10) * 60, departure: (minute + 10) * 60),
        ])
    }

    /// The layout at `minutes`, the lines `lines` from B to A with their
    /// runs and Depot, and the trains `trains` placed at the ends of edges
    /// (`line` `nil`: no line's).
    private func makeScene(at minutes: Int64, lines: [(name: String, runs: [LineRun])], trains: [(name: String, edge: Int, line: Int?)]) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 106_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minutes), speed: .normal)
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
        var ids: [LineID] = []
        for (name, runs) in lines {
            let line = try world.createLine(named: name, stops: [b, a]).id
            try world.setLineRuns(line, to: runs)
            try world.setLineDepots(line, to: [depot])
            ids.append(line)
        }
        var placed: [String: TrainID] = [:]
        for (name, edge, line) in trains {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: length - 2_048))
            try world.setTrainContinuation(id, along: [], stoppingAt: length - 2_048)
            try world.setTrainMovementRate(id, to: 4_096)
            if let line { try world.assignTrain(id, to: ids[line]) }
            placed[name] = id
        }
        try world.setTrafficControl(true)
        world.setBlockSections(true)
        return Scene(world: world, a: a, depot: depot, trains: placed)
    }

    // MARK: - A berth at the end

    /// Up's T1 in D1, Down's T2 in D2, and a train of no line standing at
    /// PA1, so A has one free track. Both lines run from A at 10:10, so
    /// in the same minute each wants a train out of the depot for it.
    private func oneFreeTrack() throws -> Scene {
        try makeScene(
            at: 590,
            lines: [("Up", [run(1, 0, at: 610)]), ("Down", [run(1, 0, at: 610)])],
            trains: [("T0", 3, nil), ("T1", 6, 0), ("T2", 7, 1)]
        )
    }

    /// The trains standing at A, and those on their way to end there.
    private func atOrBound(_ scene: Scene) -> Int {
        scene.world.trains.count { train in
            scene.world.stationsStoppedAt(by: train.id).contains(scene.a)
                || (train.execution != nil && train.timetable.last?.station == scene.a)
        }
    }

    /// Only one of them comes out: never more trains at A or bound for it
    /// than its two tracks. The other comes out once the first has left
    /// on its run.
    func testATrainComesOutOfTheDepotOnlyWithATrackAtTheEndForIt() throws {
        var scene = try oneFreeTrack()
        let t2 = try XCTUnwrap(scene.trains["T2"])
        var cameOut: GameTime?
        for _ in 0..<45 {
            try scene.world.advance(ticks: 1)
            XCTAssertLessThanOrEqual(atOrBound(scene), 2, "at minute \(scene.world.clock.now.minute): more trains at A or bound for it than its two tracks")
            if cameOut == nil, scene.world.train(id: t2)?.execution != nil { cameOut = scene.world.clock.now }
        }
        let t1 = try XCTUnwrap(scene.trains["T1"])
        XCTAssertEqual(scene.world.train(id: t1)?.timetable.first?.station, scene.a, "T1 ran Up's run from A")
        XCTAssertNotNil(cameOut, "T2 came out")
        XCTAssertTrue(scene.world.stationsStoppedAt(by: t2).contains(scene.a), "T2 stands at A for Down's run")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// The train out of the depot runs to the free track, not the first
    /// one: PA1 is taken by a train standing there.
    func testTheTrainOutOfTheDepotRunsToTheFreeTrack() throws {
        var scene = try oneFreeTrack()
        let t1 = try XCTUnwrap(scene.trains["T1"])
        for _ in 0..<15 {
            try scene.world.advance(ticks: 1)
            if case .travellingToStop? = scene.world.train(id: t1)?.execution { break }
        }
        let train = try XCTUnwrap(scene.world.train(id: t1))
        guard case .travellingToStop? = train.execution else { return XCTFail("T1 is on its way to A") }
        XCTAssertEqual(train.movement.edges.last, .edge(4), "to PA2")
    }

    // MARK: - Batches

    /// The trains come out at whole minutes, so a batch ends where minute
    /// by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        let scene = try oneFreeTrack()
        var single = scene.world
        for _ in 0..<60 { try single.advance(ticks: 1) }
        var batched = scene.world
        try batched.advance(ticks: 60)
        XCTAssertEqual(batched, single)
    }
}
