import Foundation
@testable import GameCore
import XCTest

/// Decision 283: with traffic control off, of two trains of real runs on
/// their way towards a single track from its two ends, neither on it yet,
/// the farther waits short of it and the nearer goes first. Before, only a
/// train still leaving its platform waited for a nearer one, and a train
/// on its way waited only for one on the track already; so two trains that
/// had both left their platforms both went on and met on it (the
/// high-speed demo between Nangang and Taipei, decision 281).
///
///   PS (P's start) ──e1──┐                        ┌──e43── Pd (P's end)
///                        j1 ═══ S: e3…e42 ═══ j2
///   Qd (Q's end) ────e2──┘                        └──e44── QS (Q's start)
///
/// P runs PS to Pd and Q runs QS to Qd, both setting off at 06:00. S is
/// forty short edges, more than the thirty-two a train was looked at along
/// before (decision 283: and on to 20 km). Q starts nearer S than P does.
final class OncomingTrainsTests: XCTestCase {
    private struct Scene {
        var world: GameWorld
        let p: TrainID
        let q: TrainID
        let pEnd: StationID
        let qEnd: StationID
    }

    private func makeScene() throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 124_928, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 5 * 60 + 58), speed: .normal)
        )
        // Every turnout within 1 in 16 of straight on (see `TrackNodeEnd`).
        let ps = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let qd = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 6_144))
        let j1 = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: 8_192))
        try world.buildTrackEdge(from: ps, to: j1) // e1
        try world.buildTrackEdge(from: qd, to: j1) // e2
        var node = j1
        for index in 1...40 {
            let next = try world.buildTrackNode(at: WorldCoordinate(x: 40_960 + Int64(index) * 1_024, y: 8_192))
            try world.buildTrackEdge(from: node, to: next) // e3…e42
            node = next
        }
        let pd = try world.buildTrackNode(at: WorldCoordinate(x: 121_856, y: 8_192))
        let qs = try world.buildTrackNode(at: WorldCoordinate(x: 121_856, y: 10_240))
        try world.buildTrackEdge(from: node, to: pd) // e43
        try world.buildTrackEdge(from: node, to: qs) // e44
        func station(_ name: String, on edge: Int, nearStart: Bool) throws -> StationID {
            let id = try world.buildStation(named: name, at: PlanPoint(x: nearStart ? 4_096 : 118_784, y: 12_288)).id
            let length = try XCTUnwrap(world.trackEdge(.edge(edge))?.length)
            try world.addTrackPlatform(id, on: .edge(edge), from: nearStart ? 1_024 : length - 9_216, to: nearStart ? 9_216 : length - 1_024)
            return id
        }
        let pStart = try station("PS", on: 1, nearStart: true)
        let qEnd = try station("Qd", on: 2, nearStart: true)
        let pEnd = try station("Pd", on: 43, nearStart: false)
        let qStart = try station("QS", on: 44, nearStart: false)
        try world.setTrafficControl(false)
        var ids: [TrainID] = []
        for (name, stops, edge, direction, offset) in [
            ("P", [pStart, pEnd], 1, TrackEdgeDirection.forward, Int64(9_216)), ("Q", [qStart, qEnd], 44, .backward, Int64(9_216)),
        ] {
            let line = try world.createLine(named: name, stops: stops).id
            try world.setLinePerformance(line, to: TrainPerformance(acceleration: 125, braking: 100, topSpeed: 8))
            try world.setLineRuns(line, to: [LineRun(from: 0, to: 1, times: [
                LineRunTime(arrival: 360 * 60, departure: 360 * 60), LineRunTime(arrival: 370 * 60, departure: 370 * 60),
            ])])
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: direction), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 4_096)
            try world.assignTrain(id, to: line)
            ids.append(id)
        }
        return Scene(world: world, p: ids[0], q: ids[1], pEnd: pEnd, qEnd: qEnd)
    }

    /// Facing or overlapping pairs of trains on one edge.
    private func meetings(in world: GameWorld) -> [String] {
        var on: [TrackEdgeID: [(String, Int64, Int64, TrackEdgeDirection)]] = [:]
        for train in world.trains {
            for stretch in world.bodyStretches(of: train) where stretch.to > stretch.from {
                guard let length = world.network.edge(stretch.traversal.edge)?.length else { continue }
                let (low, high) = stretch.traversal.direction == .forward ? (stretch.from, stretch.to) : (length - stretch.to, length - stretch.from)
                on[stretch.traversal.edge, default: []].append((train.name, low, high, stretch.traversal.direction))
            }
        }
        var found: [String] = []
        for (edge, trains) in on.sorted(by: { $0.key < $1.key }) {
            for i in trains.indices {
                for j in trains.indices where j > i && trains[i].0 != trains[j].0 {
                    if trains[i].3 != trains[j].3 || min(trains[i].2, trains[j].2) > max(trains[i].1, trains[j].1) {
                        found.append("\(trains[i].0) and \(trains[j].0) on \(edge)")
                    }
                }
            }
        }
        return found
    }

    /// Both set off; the farther, P, waits short of S while Q, nearer,
    /// comes through it; neither meets the other on any edge, second by
    /// second, and both reach the end of their runs.
    func testOfTwoTrainsOnTheirWayTheNearerGoesFirst() throws {
        let scene = try makeScene()
        var world = scene.world
        world.setSpeed(.x10)
        var met: [String] = []
        for second in 1...(30 * 60) {
            try world.advance(ticks: 1)
            let now = meetings(in: world)
            if !now.isEmpty, met.isEmpty { met = now.map { "\($0) at second \(second)" } }
        }
        XCTAssertEqual(met, [], "two trains on one edge")
        XCTAssertEqual(world.stationsStoppedAt(by: scene.p), [scene.pEnd], "P has reached Pd")
        XCTAssertEqual(world.stationsStoppedAt(by: scene.q), [scene.qEnd], "Q has reached Qd")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// A minute in one step leaves the trains where sixty one-second steps
    /// do (decisions 37 and 248).
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
