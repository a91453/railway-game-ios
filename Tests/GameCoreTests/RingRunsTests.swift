import Foundation
@testable import GameCore
import XCTest

/// Runs of a ring (decision 535): a timetable's trains going one way round
/// a ring line, past its last stop to its first, a whole lap or part of
/// one; sent out as they face, never turned round onto the other way's
/// track; riders change trains where a run ends.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class RingRunsTests: XCTestCase {
    // A double ring: the loop of `RingLineTests` (and the golden
    // `ring-line.json`) moved to centre (5120, 4096), the inner track, and
    // the same loop twice as large round it, the outer track; the two are
    // never joined. Inner edges 1–8 run clockwise from node 1 (4096,
    // 3072), outer edges 9–16 from node 9 (3072, 2048). Six stations, A–F,
    // each with a platform on the last 512 of an inner edge and of the
    // outer edge beside it (edges 1, 2, 3, 5, 6, 7 and 9, 10, 11, 13, 14,
    // 15), so the stops in order go clockwise: the inner way round
    // (decision 49) is the inner track's clockwise way, the outer way the
    // outer track's anticlockwise way.
    private let stations = (1...6).map { StationID(rawValue: $0) }
    private let ring = LineID(rawValue: 1)
    private let clockwise = TrainID(rawValue: 1)
    private let anticlockwise = TrainID(rawValue: 2)

    /// A whole lap or part of one from stop `from` going `way`, `legs`
    /// legs, leaving at `departure`: each leg five minutes and a minute at
    /// every stop between.
    private func run(from: Int, to: Int, _ way: RingDirection, legs: Int, at departure: Int64, days: Int = LineRun.everyDay) -> LineRun {
        let times = (0...legs).map { leg -> LineRunTime in
            let time = departure + Int64(leg) * 360
            return leg == 0 ? LineRunTime(arrival: time, departure: time) : LineRunTime(arrival: time - 60, departure: leg == legs ? time - 60 : time)
        }
        return LineRun(from: from, to: to, times: times, days: days, way: way)
    }

    /// A lap each way from A at 06:00 (inner) and 06:10 (outer); A to D
    /// each way at 07:00 and 07:10; and D back to A each way, across the
    /// seam of the ring going the inner way, at 08:00 and 08:10.
    private var runs: [LineRun] {
        [
            run(from: 0, to: 0, .inner, legs: 6, at: 21_600),
            run(from: 0, to: 0, .outer, legs: 6, at: 22_200),
            run(from: 0, to: 3, .inner, legs: 3, at: 25_200),
            run(from: 0, to: 3, .outer, legs: 3, at: 25_800),
            run(from: 3, to: 0, .inner, legs: 3, at: 28_800),
            run(from: 3, to: 0, .outer, legs: 3, at: 29_400),
        ]
    }

    private func buildLoop(scale: Int64, firstNode: Int, in world: inout GameWorld) throws {
        let centre = (x: Int64(5_120), y: Int64(4_096))
        let corner = 1_338 * scale
        let offsets: [(Int64, Int64)] = [(-1_024, -1_024), (0, -1_024), (1_024, -1_024), (2_048, 0), (1_024, 1_024), (0, 1_024), (-1_024, 1_024), (-2_048, 0)]
        let nodes = offsets.map { (centre.x + $0.0 * scale, centre.y + $0.1 * scale) }
        for (x, y) in nodes {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        let curves: [TrackCurve] = [
            .straight, .straight,
            .cubic(PlanPoint(x: nodes[2].0 + corner, y: nodes[2].1), PlanPoint(x: nodes[3].0, y: nodes[3].1 - corner)),
            .cubic(PlanPoint(x: nodes[3].0, y: nodes[3].1 + corner), PlanPoint(x: nodes[4].0 + corner, y: nodes[4].1)),
            .straight, .straight,
            .cubic(PlanPoint(x: nodes[6].0 - corner, y: nodes[6].1), PlanPoint(x: nodes[7].0, y: nodes[7].1 + corner)),
            .cubic(PlanPoint(x: nodes[7].0, y: nodes[7].1 - corner), PlanPoint(x: nodes[0].0 - corner, y: nodes[0].1)),
        ]
        for (index, curve) in curves.enumerated() {
            try world.buildTrackEdge(from: .node(firstNode + index), to: .node(firstNode + (index + 1) % 8), curve: curve)
        }
    }

    private func length(_ edge: Int, in world: GameWorld) throws -> Int64 {
        try XCTUnwrap(world.network.edge(.edge(edge))).length
    }

    /// The double ring, the ring line calling at A–F with `runs`, and two
    /// trains at A: one on the inner track facing clockwise, one on the
    /// outer facing anticlockwise.
    private func makeWorld(runs: [LineRun]? = nil, minute: Int64 = 0) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 10_240, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        try buildLoop(scale: 1, firstNode: 1, in: &world)
        try buildLoop(scale: 2, firstNode: 9, in: &world)
        let tiles = [(4, 0), (6, 0), (9, 0), (6, 7), (4, 7), (1, 7)]
        for (index, edge) in [1, 2, 3, 5, 6, 7].enumerated() {
            let station = try world.buildStation(named: ["A", "B", "C", "D", "E", "F"][index], at: TestLine.centre(tiles[index].0, tiles[index].1)).id
            for track in [edge, edge + 8] {
                let length = try length(track, in: world)
                try world.addTrackPlatform(station, on: .edge(track), from: length - 512, to: length)
            }
        }
        try world.createLine(named: "Ring", stops: stations)
        try world.setLineRing(ring, to: true)
        try world.setLineServiceWindow(ring, to: .allDay)
        let inner = try length(1, in: world)
        for (name, position) in [
            ("Clockwise", TrainPosition.onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: inner)),
            ("Anticlockwise", TrainPosition.onEdge(TrackTraversal(edge: .edge(9), direction: .backward), offset: 512)),
        ] {
            let train = try world.purchaseTrain(named: name)
            try world.placeTrain(train.id, at: position)
            if name == "Anticlockwise" {
                try world.setTrainContinuation(train.id, along: [], stoppingAt: 512)
            }
            try world.setTrainMovementRate(train.id, to: 1_024)
            try world.assignTrain(train.id, to: ring)
        }
        try world.setLineRuns(ring, to: runs ?? self.runs)
        return world
    }

    private func seconds(_ timetable: [ScheduledStop]?) -> [[Int64]] {
        (timetable ?? []).map { [$0.arrival.seconds, $0.departure.seconds] }
    }

    // MARK: - Runs

    func testWorld() throws {
        let world = try makeWorld()
        XCTAssertEqual(world.stationsStoppedAt(by: clockwise), [stations[0]])
        XCTAssertEqual(world.stationsStoppedAt(by: anticlockwise), [stations[0]])
        print("LENGTHS", try (1...16).map { try length($0, in: world) })
    }
}
