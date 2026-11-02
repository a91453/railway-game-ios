import Foundation
@testable import GameCore
import XCTest

/// Decision 518: with traffic control off, a train of real runs that calls
/// at a station and goes on stands on the loop beside the through track,
/// and leaves the through track to the trains that pass. Before, when
/// another train stood on its loop but was due to leave in time, it went
/// to the through track instead (decision 228's empty platform first), and
/// without a platform named it took the nearest, the through track's.
///
///   P ──e1── J1 ───────────── e2 (X, main) ───────────── J2 ──e6── Q
///             └──e3── L1 ──── e4 (X, loop) ──── L2 ──e5──┘
///
/// Edge `en` is `.edge(n)`. Local runs P (10:05) – X (10:10–10:11) – Q
/// (10:15); Other stands on X's loop and leaves it for Q at `otherLeaves`.
final class CallingLoopPlatformTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let local: TrainID
        let x: StationID
    }

    private func at(_ minute: Int64) -> LineRunTime {
        LineRunTime(arrival: minute * 60, departure: minute * 60)
    }

    /// `named`: Local names X's loop for its call there; `endsAtX`: Local
    /// ends at X; `otherLeaves`: when Other, on X's loop, leaves it (none
    /// on the loop when `nil`).
    private func makeScene(named: Bool, endsAtX: Bool = false, otherLeaves: Int64?) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 262_144, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        // Every turnout within 1 in 16 of straight on (see `TrackNodeEnd`).
        let p = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j1 = try world.buildTrackNode(at: WorldCoordinate(x: 82_944, y: 8_192))
        let l1 = try world.buildTrackNode(at: WorldCoordinate(x: 103_424, y: 9_216))
        let l2 = try world.buildTrackNode(at: WorldCoordinate(x: 144_384, y: 9_216))
        let j2 = try world.buildTrackNode(at: WorldCoordinate(x: 164_864, y: 8_192))
        let q = try world.buildTrackNode(at: WorldCoordinate(x: 246_784, y: 8_192))
        try world.buildTrackEdge(from: p, to: j1)   // e1
        try world.buildTrackEdge(from: j1, to: j2)  // e2: X's main
        try world.buildTrackEdge(from: j1, to: l1)  // e3
        try world.buildTrackEdge(from: l1, to: l2)  // e4: X's loop
        try world.buildTrackEdge(from: l2, to: j2)  // e5
        try world.buildTrackEdge(from: j2, to: q)   // e6
        let pStation = try world.buildStation(named: "P", at: PlanPoint(x: 4_096, y: 4_096)).id
        let x = try world.buildStation(named: "X", at: PlanPoint(x: 123_904, y: 12_288)).id
        let qStation = try world.buildStation(named: "Q", at: PlanPoint(x: 240_000, y: 12_288)).id
        func length(_ edge: Int) throws -> Int64 { try XCTUnwrap(world.trackEdge(.edge(edge))?.length) }
        try world.addTrackPlatform(pStation, on: .edge(1), from: try length(1) - 20_480, to: try length(1) - 12_288)
        // The main's platform ends before the loop's, so the shortest way
        // reaches it first.
        try world.addTrackPlatform(x, on: .edge(2), from: try length(2) / 2 - 12_288, to: try length(2) / 2 - 4_096)
        try world.addTrackPlatform(x, on: .edge(4), from: try length(4) / 2 - 4_096, to: try length(4) / 2 + 4_096)
        try world.addTrackPlatform(qStation, on: .edge(6), from: try length(6) - 10_240, to: try length(6) - 2_048)
        try world.setTrafficControl(false)
        let stops = endsAtX ? [pStation, x] : [pStation, x, qStation]
        let localLine = try world.createLine(named: "Local", stops: stops).id
        let times = [at(605), LineRunTime(arrival: 610 * 60, departure: 611 * 60)] + (endsAtX ? [] : [at(615)])
        try world.setLineRuns(localLine, to: [LineRun(from: 0, to: stops.count - 1, times: times)])
        if named, let loop = world.network.platforms(of: x).first(where: { $0.edge == .edge(4) }) {
            try world.setLineRoutePreferences(localLine, to: [LineRoutePreference(from: 0, to: 1, platform: loop)])
        }
        func train(_ name: String, on edge: Int, at offset: Int64, line: LineID) throws -> TrainID {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: .forward), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            return id
        }
        let local = try train("L", on: 1, at: try length(1) - 12_288, line: localLine)
        if let otherLeaves {
            let otherLine = try world.createLine(named: "Other", stops: [x, qStation]).id
            try world.setLineRuns(otherLine, to: [LineRun(from: 0, to: 1, times: [at(otherLeaves), at(otherLeaves + 4)])])
            _ = try train("O", on: 4, at: try length(4) / 2 + 4_096, line: otherLine)
        }
        return Scene(world: world, local: local, x: x)
    }

    /// The edge Local stands on at X at 10:10 30 s, its call there.
    private func standing(_ scene: Scene) throws -> TrackEdgeID? {
        var world = scene.world
        try world.advance(ticks: 10)
        world.setSpeed(.x10)
        try world.advance(ticks: 30)
        XCTAssertEqual(world.stationsStoppedAt(by: scene.local), [scene.x], "Local is at X")
        guard case .onEdge(let traversal, _)? = world.train(id: scene.local)?.position else { return nil }
        return traversal.edge
    }

    /// When Local sets off, another train stands on the loop it names, due
    /// to leave at 10:06, in time: Local still goes to the loop, not to the
    /// through track.
    func testItKeepsToItsLoopWhenTheTrainThereLeavesInTime() throws {
        XCTAssertEqual(try standing(makeScene(named: true, otherLeaves: 606)), .edge(4))
    }

    /// The train on its loop stays there until after Local has gone: the
    /// loop is taken over its time there, so Local calls on the through
    /// track.
    func testItTakesTheThroughTrackWhenItsLoopIsTaken() throws {
        XCTAssertEqual(try standing(makeScene(named: true, otherLeaves: 620)), .edge(2))
    }

    /// Without a platform named, the loop is free: Local stands there, not
    /// on the through track the shortest way reaches first.
    func testWithoutAPlatformNamedItStandsOnTheFreeLoop() throws {
        XCTAssertEqual(try standing(makeScene(named: false, otherLeaves: nil)), .edge(4))
    }

    /// Where its run ends nothing passes it: it stands at the nearest, as
    /// before.
    func testWhereItsRunEndsItStandsAtTheNearest() throws {
        XCTAssertEqual(try standing(makeScene(named: false, endsAtX: true, otherLeaves: nil)), .edge(2))
    }

    /// A station whose platform is split over two edges of one track, the
    /// last half of the edge from the west and the first of the edge to
    /// the east (``TestLine``): the far half is the rest of the through
    /// track's platform, not a loop beside it, so a train calling there
    /// still stands at the near half (`LineAcquisitionTests`' v66 save).
    func testTheRestOfThePlatformAheadIsNotBesideIt() throws {
        let track = TestLine(tiles: 7)
        var world = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 10_000_000, costs: testCosts))
        world.setSpeed(.normal)
        try world.advance(ticks: 300)
        try track.build(in: &world)
        let alpha = try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let beta = try track.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        let gamma = try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let line = try world.createLine(named: "Main", stops: [alpha, beta, gamma]).id
        try world.setLineServiceWindow(line, to: .allDay)
        let blue = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(blue, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(blue, to: 1_024)
        try world.assignTrain(blue, to: line)
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 2, times: [at(370), LineRunTime(arrival: 375 * 60, departure: 376 * 60), at(380)])])
        try world.advance(ticks: 75)
        XCTAssertEqual(world.stationsStoppedAt(by: blue), [beta], "Blue is at Beta")
        guard case .onEdge(let traversal, _)? = world.train(id: blue)?.position else { return XCTFail("Blue is on the track") }
        XCTAssertEqual(traversal.edge, track.edge(3))
    }

    /// L4-1 (decision 518, continued): on double track with a crossover
    /// less than a kilometre short of X, the platform of the other way's
    /// track is not beside the through track. Local calls on its own
    /// way's platform and runs on to Q along its own track; before, it
    /// crossed over, stood at the other way's platform and ran on along
    /// the other way's track.
    ///
    ///   P ──e1── J1 ──────────── e2 (X, east) ──────────── (Q, east)
    ///              \
    ///   ───e5───── K ─────────── e4 (X, west) ──────────── (Q, west)
    private func makeDoubleTrack() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 262_144, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .normal)
        )
        let pe = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let j1 = try world.buildTrackNode(at: WorldCoordinate(x: 82_944, y: 8_192))
        let ee = try world.buildTrackNode(at: WorldCoordinate(x: 246_784, y: 8_192))
        let k = try world.buildTrackNode(at: WorldCoordinate(x: 103_424, y: 9_216))
        let ew = try world.buildTrackNode(at: WorldCoordinate(x: 246_784, y: 9_216))
        let pw = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 9_216))
        try world.buildTrackEdge(from: pe, to: j1)  // e1
        try world.buildTrackEdge(from: j1, to: ee)  // e2: the east track
        try world.buildTrackEdge(from: j1, to: k)   // e3: the crossover
        try world.buildTrackEdge(from: k, to: ew)   // e4: the west track
        try world.buildTrackEdge(from: pw, to: k)   // e5
        func length(_ edge: Int) throws -> Int64 { try XCTUnwrap(world.trackEdge(.edge(edge))?.length) }
        let pStation = try world.buildStation(named: "P", at: PlanPoint(x: 4_096, y: 4_096)).id
        let x = try world.buildStation(named: "X", at: PlanPoint(x: 124_000, y: 12_288)).id
        let qStation = try world.buildStation(named: "Q", at: PlanPoint(x: 240_000, y: 12_288)).id
        try world.addTrackPlatform(pStation, on: .edge(1), from: try length(1) - 20_480, to: try length(1) - 12_288)
        // X's two platforms side by side, 120,000 to 128,192 along.
        try world.addTrackPlatform(x, on: .edge(2), from: 120_000 - 82_944, to: 128_192 - 82_944)
        try world.addTrackPlatform(x, on: .edge(4), from: 120_000 - 103_424, to: 128_192 - 103_424)
        try world.addTrackPlatform(qStation, on: .edge(2), from: try length(2) - 10_240, to: try length(2) - 2_048)
        try world.addTrackPlatform(qStation, on: .edge(4), from: try length(4) - 10_240, to: try length(4) - 2_048)
        try world.setTrafficControl(false)
        let stops = [pStation, x, qStation]
        let localLine = try world.createLine(named: "Local", stops: stops).id
        try world.setLineRuns(localLine, to: [LineRun(from: 0, to: 2, times: [at(605), LineRunTime(arrival: 612 * 60, departure: 613 * 60), at(620)])])
        let local = try world.purchaseTrain(named: "L").id
        try world.setTrainCars(local, to: 2)
        try world.placeTrain(local, at: .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: try length(1) - 12_288))
        try world.setTrainContinuation(local, along: [], stoppingAt: try length(1) - 12_288)
        try world.setTrainMovementRate(local, to: 4_096)
        try world.assignTrain(local, to: localLine)
        return Scene(world: world, local: local, x: x)
    }

    func testItDoesNotCrossOverToTheOtherWaysPlatform() throws {
        let scene = try makeDoubleTrack()
        var world = scene.world
        try world.advance(ticks: 12)
        world.setSpeed(.x10)
        try world.advance(ticks: 30)
        XCTAssertEqual(world.stationsStoppedAt(by: scene.local), [scene.x], "Local is at X")
        guard case .onEdge(let atX, _)? = world.train(id: scene.local)?.position else { return XCTFail("Local is on the track") }
        XCTAssertEqual(atX.edge, .edge(2), "Local calls at X on its own way's track")
        world.setSpeed(.normal)
        try world.advance(ticks: 8)
        XCTAssertEqual(world.stationsStoppedAt(by: scene.local).count, 1, "Local is at Q")
        guard case .onEdge(let atQ, _)? = world.train(id: scene.local)?.position else { return XCTFail("Local is on the track") }
        XCTAssertNotEqual(atQ.edge, .edge(4), "Local runs on to Q along its own way's track")
    }
}
