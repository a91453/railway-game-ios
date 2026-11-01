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
    private let depotStation = StationID(rawValue: 7)

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
    private func makeWorld(runs: [LineRun]? = nil, minute: Int64 = 0, trains: Bool = true, depot: Bool = false) throws -> GameWorld {
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
        if depot {
            // The depot G: a siding bowed out of the inner track between A
            // and B, node 2 (5120, 3072) to node 17 (5632, 2816), edge 17,
            // and on to node 3 (6144, 3072), edge 18, its platform the
            // first 512 of edge 18.
            try world.buildTrackNode(at: WorldCoordinate(x: 5_632, y: 2_816))
            try world.buildTrackEdge(from: .node(2), to: .node(17), curve: .cubic(PlanPoint(x: 5_376, y: 3_072), PlanPoint(x: 5_376, y: 2_816)))
            try world.buildTrackEdge(from: .node(17), to: .node(3), curve: .cubic(PlanPoint(x: 5_888, y: 2_816), PlanPoint(x: 5_888, y: 3_072)))
            let id = try world.buildStation(named: "G", at: TestLine.centre(8, 1)).id
            try world.addTrackPlatform(id, on: .edge(18), from: 0, to: 512)
            try world.setStationDepot(id, to: true)
        }
        try world.createLine(named: "Ring", stops: stations)
        try world.setLineRing(ring, to: true)
        try world.setLineServiceWindow(ring, to: .allDay)
        let inner = try length(1, in: world)
        for (name, position) in !trains ? [] : [
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
        if depot {
            try world.setLineDepots(ring, to: [depotStation])
        }
        return world
    }

    private func seconds(_ timetable: [ScheduledStop]?) -> [[Int64]] {
        (timetable ?? []).map { [$0.arrival.seconds, $0.departure.seconds] }
    }

    /// Each train's timetables as it is sent out, minute by minute for
    /// `ticks` minutes.
    private func sentOut(_ world: inout GameWorld, ticks: Int) throws -> [TrainID: [[ScheduledStop]]] {
        var sent: [TrainID: [[ScheduledStop]]] = [:]
        var running: Set<TrainID> = []
        for _ in 0..<ticks {
            try world.advance(ticks: 1)
            for train in world.trains {
                if train.execution != nil, !running.contains(train.id) { sent[train.id, default: []].append(train.timetable) }
                if train.execution == nil { running.remove(train.id) } else { running.insert(train.id) }
            }
        }
        return sent
    }

    private func names(_ timetable: [ScheduledStop]) -> String {
        timetable.map { ["A", "B", "C", "D", "E", "F", "G"][$0.station.rawValue - 1] }.joined()
    }

    // MARK: - Calls and checks

    /// The calls of a run of a ring worked out the slow way, as an
    /// independent model (decision 49's `ReferenceWorld` does not run
    /// timetables): from `from`, step one stop `way` at a time until `to`
    /// comes round, a whole lap when it is `from`.
    private func referenceCalls(from: Int, to: Int, _ way: RingDirection, count: Int) -> [Int] {
        var calls = [from]
        repeat {
            calls.append(way == .inner ? (calls.last! + 1) % count : (calls.last! + count - 1) % count)
        } while calls.last! != to
        return calls
    }

    /// Every run of rings of 3 to 8 stops calls as the slow model does, and
    /// is a run of the ring only with a time for each of those calls and a
    /// way; a line with ends takes no way, and no run from a stop to
    /// itself.
    func testRingRunCallsMatchAStepByStepModel() {
        for count in 3...8 {
            for from in 0..<count {
                for to in 0..<count {
                    for way in RingDirection.allCases {
                        let calls = referenceCalls(from: from, to: to, way, count: count)
                        let times = calls.indices.map { LineRunTime(arrival: Int64($0) * 60, departure: Int64($0) * 60) }
                        let run = LineRun(from: from, to: to, times: times, way: way)
                        XCTAssertEqual(run.calls(stopCount: count), calls, "\(count) \(from) \(to) \(way)")
                        XCTAssertTrue(run.isValid(stopCount: count, ring: true))
                        XCTAssertFalse(run.isValid(stopCount: count), "a line with ends takes no way")
                        XCTAssertFalse(LineRun(from: from, to: to, times: Array(times.dropLast()), way: way).isValid(stopCount: count, ring: true))
                        XCTAssertFalse(LineRun(from: from, to: to, times: times + [LineRunTime(arrival: 3_600, departure: 3_600)], way: way).isValid(stopCount: count, ring: true))
                        XCTAssertFalse(LineRun(from: from, to: to, times: times).isValid(stopCount: count, ring: true), "a run of a ring has a way")
                        XCTAssertEqual(run.isOutbound, way == .inner)
                    }
                }
            }
        }
        // The runs of the world: D to A the inner way crosses the seam.
        XCTAssertEqual(runs.map { $0.calls(stopCount: 6) }, [[0, 1, 2, 3, 4, 5, 0], [0, 5, 4, 3, 2, 1, 0], [0, 1, 2, 3], [0, 5, 4, 3], [3, 4, 5, 0], [3, 2, 1, 0]])
    }

    /// A ring takes runs with a way; a run without one, with the wrong
    /// number of times, or of a line with ends with a way, is refused; a
    /// ring with runs stays a ring; reversing its stops reverses each run's
    /// way and keeps its stations; the way saves as `"way"`.
    func testRingRunsAreCheckedKeptAndReversed() throws {
        var world = try makeWorld(trains: false)
        XCTAssertEqual(world.line(id: ring)?.runs, runs)
        let lap = runs[0]
        for broken in [
            LineRun(from: 0, to: 0, times: lap.times),
            LineRun(from: 0, to: 3, times: lap.times, way: .inner),
            LineRun(from: 0, to: 0, times: Array(lap.times.prefix(4)), way: .outer),
        ] {
            XCTAssertThrowsError(try world.setLineRuns(ring, to: [broken])) { XCTAssertEqual($0 as? GameError, .invalidLineRuns, "\(broken)") }
        }
        XCTAssertEqual(world.line(id: ring)?.runs, runs, "a refused change changes nothing")
        XCTAssertThrowsError(try world.setLineRing(ring, to: false)) { XCTAssertEqual($0 as? GameError, .invalidLineRuns) }
        XCTAssertNoThrow(try world.setLineRing(ring, to: true))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = String(decoding: try encoder.encode(XCTUnwrap(world.line(id: ring))), as: UTF8.self)
        XCTAssertTrue(text.contains(#""way":"inner""#), text)
        XCTAssertTrue(text.contains(#""way":"outer""#), text)
        XCTAssertEqual(try JSONDecoder().decode(ServiceLine.self, from: Data(text.utf8)), world.line(id: ring))
        // A run of a ring without a way, or with one that is no way round,
        // is refused.
        for (from, to) in [(#","way":"inner""#, ""), (#""way":"outer""#, #""way":"sideways""#)] {
            XCTAssertTrue(text.contains(from))
            XCTAssertThrowsError(try JSONDecoder().decode(ServiceLine.self, from: Data(text.replacingOccurrences(of: from, with: to).utf8)), from)
        }

        try world.reverseLineStops(ring)
        let reversed = try XCTUnwrap(world.line(id: ring))
        XCTAssertEqual(reversed.stops, stations.reversed())
        XCTAssertEqual(reversed.runs.map(\.way), [.outer, .inner, .outer, .inner, .outer, .inner])
        XCTAssertEqual(reversed.runs.map { reversed.calls(of: $0).map { reversed.stops[$0] } }, runs.map { $0.calls(stopCount: 6).map { stations[$0] } })
    }

    // MARK: - Running

    /// Each train is sent out five minutes before each of its runs and
    /// keeps the run's times; neither ever turns round, each going on round
    /// its own track, the inner train across the seam from D to A; the
    /// second day runs the same, and both end the day at A.
    func testRunsGoRoundEachWayWithoutTurningForTwoDays() throws {
        var world = try makeWorld()
        let sent = try sentOut(&world, ticks: 2 * 1_440)
        func expected(_ way: RingDirection) -> [[ScheduledStop]] {
            let ours = runs.filter { $0.way == way }
            return (0..<2).flatMap { day in
                ours.map { run in
                    let base = Int64(day) * GameTime.secondsPerDay
                    return run.calls(stopCount: 6).enumerated().map { index, stop in
                        ScheduledStop(
                            station: stations[stop], arrival: GameTime(seconds: base + (index == 0 ? run.times[0].departure - LineRun.earliestDispatch : run.times[index].arrival)),
                            departure: GameTime(seconds: base + run.times[index].departure), reverses: false
                        )
                    }
                }
            }
        }
        XCTAssertEqual(sent[clockwise], expected(.inner))
        XCTAssertEqual(sent[anticlockwise], expected(.outer))
        XCTAssertEqual(sent[clockwise]?.map(names), ["ABCDEFA", "ABCD", "DEFA", "ABCDEFA", "ABCD", "DEFA"])
        XCTAssertEqual(sent[anticlockwise]?.map(names), ["AFEDCBA", "AFED", "DCBA", "AFEDCBA", "AFED", "DCBA"])
        // The inner lap of day 0, written out: sent at 05:55, A at 06:00,
        // then a stop every six minutes, back at A at 06:35.
        XCTAssertEqual(seconds(sent[clockwise]?.first), [[21_300, 21_600], [21_900, 21_960], [22_260, 22_320], [22_620, 22_680], [22_980, 23_040], [23_340, 23_400], [23_700, 23_700]])
        XCTAssertEqual(world.line(id: ring)?.runDays, Array(repeating: 1, count: 6))
        XCTAssertEqual(world.stationsStoppedAt(by: clockwise), [stations[0]])
        XCTAssertEqual(world.stationsStoppedAt(by: anticlockwise), [stations[0]])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// A train facing its run's way round leaves its first stop at least
    /// ``ServiceDwell/minimum`` (36 s, a ring's stop) after it is sent, not
    /// a terminal's dwell; one that must turn round first takes
    /// ``ServiceDwell/terminalMinimum``.
    func testTheFirstStopOfARingRunIsAnOrdinaryStop() throws {
        let world = try makeWorld()
        let line = try XCTUnwrap(world.line(id: ring))
        let train = try XCTUnwrap(world.train(id: clockwise))
        let lap = runs[0]
        let ahead = try XCTUnwrap(world.runTrip(of: line, lap, for: train))
        XCTAssertFalse(ahead.turnsFirst)
        let late = GameTime(seconds: lap.times[0].departure)
        XCTAssertEqual(ahead.timetable(lap, calling: line.stops, day: 0, sentOutAt: late).first?.departure.seconds, lap.times[0].departure + 36)
        XCTAssertEqual(ServiceDwell.minimum, 36)
        // The outer lap on the inner track: it turns round first.
        let turned = try XCTUnwrap(world.runTrip(of: line, runs[1], for: train))
        XCTAssertTrue(turned.turnsFirst)
        let outerDeparture = runs[1].times[0].departure
        let first = try XCTUnwrap(turned.timetable(runs[1], calling: line.stops, day: 0, sentOutAt: GameTime(seconds: outerDeparture)).first)
        XCTAssertEqual(first.departure.seconds, outerDeparture + ServiceDwell.terminalMinimum)
        XCTAssertTrue(first.reverses)
    }

    /// A train in the depot G beside the inner track between A and B
    /// facing A: the nearest way to A has it stand at A facing the outer
    /// way, so it is sent out turned round, all the way round the inner
    /// track, to stand at A facing the inner way, and the inner lap leaves
    /// without turning round; after it the train goes back into G.
    func testATrainOutOfTheDepotStandsFacingItsRunsWay() throws {
        var world = try makeWorld(runs: [runs[0]], trains: false, depot: true)
        let train = try world.purchaseTrain(named: "Out").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(18), direction: .backward), offset: try length(18, in: world)))
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: ring)
        XCTAssertEqual(world.stationsStoppedAt(by: train), [depotStation])
        let line = try XCTUnwrap(world.line(id: ring))
        let nearest = try XCTUnwrap(world.emptyRun(of: line, for: XCTUnwrap(world.train(id: train)), to: [stations[0]]))
        XCTAssertFalse(nearest.turnsFirst, "the nearest way goes as it faces, onto the outer way's side")
        let facing = try XCTUnwrap(world.emptyRun(of: line, for: XCTUnwrap(world.train(id: train)), to: [stations[0]], facing: .inner))
        XCTAssertTrue(facing.turnsFirst)
        XCTAssertGreaterThan(try XCTUnwrap(facing.deadhead).seconds, try XCTUnwrap(nearest.deadhead).seconds)

        let sent = try sentOut(&world, ticks: 7 * 60)
        let trips = try XCTUnwrap(sent[train])
        XCTAssertEqual(trips.map(names), ["GA", "ABCDEFA", "AG"])
        XCTAssertEqual(trips[0].map(\.reverses), [true, false])
        XCTAssertEqual(trips[1].map(\.reverses), Array(repeating: false, count: 7))
        XCTAssertEqual(seconds(trips[1]).first, [21_300, 21_600])
        XCTAssertEqual(world.line(id: ring)?.runDays, [0])
        XCTAssertEqual(world.stationsStoppedAt(by: train), [depotStation])
    }

    /// Only the outer way has runs from A, two laps at 06:00 and 06:10,
    /// and the train at A facing the inner way is the spare for the
    /// second: it stands at A from 05:00, is not sent into the depot G
    /// for want of an inner run (and out again), and takes the 06:10 lap
    /// turned round where it stands.
    func testATrainFacingAWayWithoutRunsTakesTheOtherWaysRunTurnedRound() throws {
        var world = try makeWorld(runs: [runs[1], run(from: 0, to: 0, .outer, legs: 6, at: 21_600)], minute: 300, depot: true)
        let sent = try sentOut(&world, ticks: 2 * 60)
        XCTAssertEqual(try XCTUnwrap(sent[clockwise]).map(names), ["AFEDCBA", "AG"])
        XCTAssertEqual(try XCTUnwrap(sent[clockwise])[0].first?.reverses, true)
        XCTAssertEqual(seconds(try XCTUnwrap(sent[clockwise])[0]).first?.last, 22_200)
        XCTAssertEqual(try XCTUnwrap(sent[anticlockwise]).map(names), ["AFEDCBA"])
        XCTAssertEqual(seconds(try XCTUnwrap(sent[anticlockwise])[0]).first?.last, 21_600)
    }

    // MARK: - Riders

    /// With only the inner lap from A, a rider from E to B goes the inner
    /// way and changes trains at A, where every lap ends (the seam,
    /// decision 49); a stretch is served only within some run going that
    /// way round: with only D back to A the inner way, E to A is, E to B
    /// (past the seam) and anything the outer way are not.
    func testRidersChangeTrainsAtTheSeam() throws {
        let world = try makeWorld(runs: [runs[0]])
        let route = try XCTUnwrap(world.passengerRoutes(from: stations[4], to: stations[1]).first)
        XCTAssertEqual(route.legs.map(\.from), [stations[4], stations[0]])
        XCTAssertEqual(route.legs.map(\.to), [stations[0], stations[1]])
        XCTAssertEqual(route.legs.map(\.direction), [.outbound, .outbound])

        var arc = try XCTUnwrap(world.line(id: ring))
        arc.runs = [runs[4]]
        XCTAssertTrue(arc.runsServe(from: 4, to: 0, way: .inner))
        XCTAssertTrue(arc.runsServe(from: 3, to: 5, way: .inner))
        XCTAssertFalse(arc.runsServe(from: 4, to: 1, way: .inner))
        XCTAssertFalse(arc.runsServe(from: 0, to: 4, way: .outer))
        XCTAssertTrue(arc.runsServe(from: 4, to: 0))
        XCTAssertFalse(arc.runsServe(from: 0, to: 4))
        XCTAssertTrue(arc.ringRunPaths(way: .inner).laps.isEmpty)
        XCTAssertEqual(arc.ringRunPaths(way: .inner).arcs.map { [$0.start, $0.legs] }, [[3, 3]])

        // The world's runs: the laps from A cover both arcs each way.
        let line = try XCTUnwrap(makeWorld().line(id: ring))
        for way in RingDirection.allCases {
            XCTAssertEqual(line.ringRunPaths(way: way).laps, [0])
            XCTAssertTrue(line.ringRunPaths(way: way).arcs.isEmpty)
        }
    }

    // MARK: - Saving

    /// Version 80 (decision 535): the double ring with the depot G and its
    /// six runs at 06:10, both trains on their laps. It saves byte for byte
    /// and is the world this build makes.
    func testVersionEightyKeepsTheRingRuns() throws {
        var made = try makeWorld(depot: true)
        try made.advance(ticks: 370)
        let url = SavedGameTests.fixtures.appendingPathComponent("v80-ring-runs.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["RING_RUNS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 80)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.line(id: ring)?.runs, runs)
        XCTAssertEqual(world.line(id: ring)?.depots, [depotStation])
        XCTAssertEqual(world.line(id: ring)?.runDays, [0, 0, nil, nil, nil, nil])
        XCTAssertEqual(world.train(id: clockwise)?.timetable.map(\.station), [0, 1, 2, 3, 4, 5, 0].map { stations[$0] })
        XCTAssertEqual(world.train(id: anticlockwise)?.timetable.map(\.station), [0, 5, 4, 3, 2, 1, 0].map { stations[$0] })
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 80,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
