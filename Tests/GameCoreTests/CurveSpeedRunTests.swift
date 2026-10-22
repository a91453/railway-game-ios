import Foundation
@testable import GameCore
import XCTest

/// Decision 217, the running side: with the world's switch on, a line plans
/// its legs under the curve limits, and a train sets off on a run that
/// keeps to them, braking ahead of the curve and keeping to its timetable.
/// Off, as in every world before it, nothing changes.
final class CurveSpeedRunTests: XCTestCase {
    private let main = LineID(rawValue: 1)
    private var curveEdge = TrackEdgeID.edge(0)

    /// Station A on a 64 m platform, 1 km east, a quarter circle of 300 m
    /// turning north (limit 75 km/h), 1 km north, station B on a 64 m
    /// platform; the line Main A–B all day, with one standard train.
    private func build(limits: Bool, realistic: Bool = true) throws -> (GameWorld, TrainID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500))
        )
        let r: Int64 = 300 * 64, k = r * 5523 / 10_000
        let (x, y): (Int64, Int64) = (8_192, 8_192)
        let points = [
            WorldCoordinate(x: x, y: y), WorldCoordinate(x: x + 4_096, y: y), WorldCoordinate(x: x + 4_096 + 64_000, y: y),
            WorldCoordinate(x: x + 4_096 + 64_000 + r, y: y + r), WorldCoordinate(x: x + 4_096 + 64_000 + r, y: y + r + 64_000),
            WorldCoordinate(x: x + 4_096 + 64_000 + r, y: y + r + 64_000 + 4_096),
        ]
        let nodes = try points.map { try world.buildTrackNode(at: $0) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        _ = try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        curveEdge = try world.buildTrackEdge(from: nodes[2], to: nodes[3], curve: .cubic(
            PlanPoint(x: points[2].x + k, y: points[2].y), PlanPoint(x: points[3].x, y: points[3].y - k)))
        _ = try world.buildTrackEdge(from: nodes[3], to: nodes[4])
        let last = try world.buildTrackEdge(from: nodes[4], to: nodes[5])
        let a = try world.buildStation(named: "A", at: PlanPoint(x: x + 2_048, y: y + 512)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: points[4].x + 512, y: points[4].y + 2_048)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.createLine(named: "Main", stops: [a, b])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        world.setRealisticOperation(realistic)
        world.setCurveSpeedLimits(limits)
        let train = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        try world.setTrainMovementRate(train, to: 1024)
        try world.assignTrain(train, to: main)
        world.setSpeed(.normal)
        return (world, train)
    }

    func testTheCurveEdgeIsLimitedToSeventyFive() throws {
        let (world, _) = try build(limits: true)
        XCTAssertEqual(world.network.edge(curveEdge)?.speedLimits.map(\.speed).min(), 75)
    }

    func testALinePlansItsLegsUnderTheLimitsOnlyWithTheSwitchOn() throws {
        for realistic in [false, true] {
            let off = try XCTUnwrap(build(limits: false, realistic: realistic).0.lineJourney(main))
            let on = try XCTUnwrap(build(limits: true, realistic: realistic).0.lineJourney(main))
            XCTAssertEqual(off.legs.count, on.legs.count)
            for (free, limited) in zip(off.legs, on.legs) {
                XCTAssertEqual(free.path, limited.path)
                XCTAssertGreaterThan(limited.seconds, free.seconds, "a 110 km/h train slows to 75 for the curve")
                XCTAssertLessThan(limited.seconds, free.seconds + 60)
            }
        }
    }

    /// Runs the world second by second until the train has gone from A to
    /// B and back, checking each second on the curve that its run's curve
    /// keeps to the limit there.
    func testTheTrainKeepsToTheLimitOnTheCurveAndToItsTimetable() throws {
        var (world, train) = try build(limits: true)
        var onCurve = 0
        var limitedRuns = 0
        var arrivals: [(Int64, Int64)] = []
        var wasTravelling = false
        for _ in 0..<1_200 {
            try world.advance(ticks: 1)
            let current = try XCTUnwrap(world.train(id: train))
            guard case .travellingToStop(let stop, let cycle)? = current.execution, let run = current.times?.run else {
                if wasTravelling, case .waitingAtStop(let stop, let cycle)? = current.execution {
                    arrivals.append((current.times!.arrival.seconds, current.scheduledArrival(of: stop, cycle: cycle).seconds))
                }
                wasTravelling = false
                continue
            }
            if !wasTravelling, !run.limits.isEmpty { limitedRuns += 1 }
            wasTravelling = true
            _ = (stop, cycle)
            guard case .onEdge(let traversal, _)? = current.position, traversal.edge == curveEdge,
                  case .limited(let curve)? = world.runCurve(of: run, for: current.performance) else { continue }
            onCurve += 1
            let elapsed = (world.clock.now.seconds - run.start.seconds) * 1000
            XCTAssertLessThanOrEqual(curve.speed(at: elapsed), 76, "at \(elapsed) ms into the run")
        }
        XCTAssertGreaterThanOrEqual(limitedRuns, 2, "both ways")
        XCTAssertGreaterThan(onCurve, 20)
        XCTAssertGreaterThanOrEqual(arrivals.count, 2)
        for (actual, scheduled) in arrivals {
            XCTAssertLessThanOrEqual(actual, scheduled, "on time under the limits")
        }
    }

    /// A6 of the #873–#910 review: a train of a real timetable that runs
    /// late makes up what it can, but under the curve limits its timetable
    /// keeps to (decision 306); only where the timetable's own time does
    /// not fit under them does it run without.
    ///
    /// Station M on the straight before the bend: the timetable gives A–M
    /// 10 s, which no train makes, so the train leaves M late, and M–B,
    /// through the bend, 170 s, which fit under the limit.
    func testALateRealRunMakesUpTimeUnderTheLimits() throws {
        var (world, train) = try build(limits: true, realistic: false)
        let a = StationID(rawValue: 1), b = StationID(rawValue: 2)
        let m = try world.buildStation(named: "M", at: PlanPoint(x: 8_192 + 4_096 + 32_000, y: 8_192 + 512)).id
        try world.addTrackPlatform(m, on: .edge(2), from: 28_000, to: 32_096)
        try world.setLineStops(main, to: [a, m, b])
        try world.setLineRuns(main, to: [LineRun(from: 0, to: 2, times: [
            LineRunTime(arrival: 600, departure: 600), LineRunTime(arrival: 610, departure: 640), LineRunTime(arrival: 810, departure: 810),
        ])])
        var run: ServiceRun?
        for _ in 0..<1_200 where run == nil {
            try world.advance(ticks: 1)
            if case .travellingToStop(2, _)? = world.train(id: train)?.execution { run = world.train(id: train)?.times?.run }
        }
        let late = try XCTUnwrap(run)
        XCTAssertGreaterThan(late.start.seconds, 640, "it leaves M late")
        XCTAssertFalse(late.limits.isEmpty, "it keeps to the curve")
        let moving = try XCTUnwrap(world.train(id: train))
        XCTAssertEqual(late.seconds, RunCurve.leastSeconds(length: late.length, performance: moving.performance, limits: late.limits),
                       "as fast as the curve lets it")
        XCTAssertLessThan(late.seconds, 170, "making up time")

        // Where the timetable's own time does not fit under the limits,
        // the real time is kept without them, late or not.
        let free = try XCTUnwrap(world.run(of: moving, length: late.length, scheduled: 60, timetabled: 100))
        XCTAssertEqual(free.limits, [])
        XCTAssertLessThan(free.seconds, late.seconds)
        let lateFitting = try XCTUnwrap(world.run(of: moving, length: late.length, scheduled: 60, timetabled: 170))
        XCTAssertFalse(lateFitting.limits.isEmpty)
        XCTAssertEqual(lateFitting.seconds, RunCurve.leastSeconds(length: late.length, performance: moving.performance, limits: lateFitting.limits))
    }

    func testWithTheSwitchOffARunMeetsNoLimit() throws {
        var (world, train) = try build(limits: false)
        for _ in 0..<300 {
            try world.advance(ticks: 1)
            XCTAssertEqual(world.train(id: train)?.times?.run?.limits ?? [], [])
        }
    }

    func testARunKeepsItsLimitsThroughASave() throws {
        var (world, train) = try build(limits: true)
        var saved: GameWorld?
        for _ in 0..<300 {
            try world.advance(ticks: 1)
            if let run = world.train(id: train)?.times?.run, !run.limits.isEmpty {
                saved = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
                break
            }
        }
        let loaded = try XCTUnwrap(saved)
        XCTAssertTrue(loaded.curveSpeedLimits)
        XCTAssertEqual(loaded.train(id: train)?.times?.run, world.train(id: train)?.times?.run)
        XCTAssertEqual(loaded, world)
    }

    func testTheSwitchIsSavedOnlyWhenOn() throws {
        let off = try build(limits: false).0
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(off), as: UTF8.self).contains("curveSpeedLimits"))
        let on = try build(limits: true).0
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(on), as: UTF8.self).contains("\"curveSpeedLimits\":true"))
    }

    func testARunWithLimitsOutsideItIsRejected() throws {
        let json = #"{"start": 0, "length": 100, "seconds": 10, "limits": [{"start": 50, "end": 120, "speed": 60}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ServiceRun.self, from: Data(json.utf8)))
        let fine = #"{"start": 0, "length": 100, "seconds": 10, "limits": [{"start": 50, "end": 100, "speed": 60}]}"#
        XCTAssertEqual(try JSONDecoder().decode(ServiceRun.self, from: Data(fine.utf8)).limits,
                       [TrackSpeedLimit(start: 50, end: 100, speed: 60)])
    }

    /// Save version 58: the world of ``build(limits:realistic:)`` saved as
    /// its train has set off on its first run, with the bend's limits on it.
    func testVersionFiftyEightKeepsCurveSpeedLimits() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v58-curve-speed-limits.json")
        var (made, train) = try build(limits: true)
        while made.train(id: train)?.times?.run?.limits.isEmpty ?? true {
            try made.advance(ticks: 1)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["CURVE_SPEED_LIMITS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 58)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertTrue(loaded.curveSpeedLimits)
        XCTAssertEqual(loaded.train(id: train)?.times?.run?.limits.map(\.speed).min(), 75)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 58,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    // MARK: - With block sections (decision 212)

    /// #556's chain (`BlockSectionsTests`): three edges of 200,000, but
    /// the middle one an S its trains slow down for. Three
    /// services leave at 1:00 one behind another, under traffic control
    /// with block sections.
    private func makeChain(limits: Bool) throws -> (world: GameWorld, trains: [TrainID], bow: TrackEdgeID) {
        let length: Int64 = 200_000
        var world = try GameWorld(
            bounds: WorldBounds(width: 3 * length + 4_096, height: 262_144), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        // The middle edge an S: east, across 120,000 to the side, east again.
        let shift: Int64 = 120_000
        let nodes = try (0..<4).map { try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + Int64($0) * length, y: 1_024 + ($0 >= 2 ? shift : 0))) }
        let x1 = 1_024 + length
        _ = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        let bow = try world.buildTrackEdge(from: nodes[1], to: nodes[2], curve: .cubic(
            PlanPoint(x: x1 + 20_000, y: 1_024), PlanPoint(x: x1 + length - 20_000, y: 1_024 + shift)))
        _ = try world.buildTrackEdge(from: nodes[2], to: nodes[3])
        let bowLength = try XCTUnwrap(world.network.edge(bow)).length
        var stations: [String: StationID] = [:]
        for (name, edge, from) in [("S1", 1, Int64(30_000)), ("S2", 2, 20_000), ("S3", 2, bowLength - 50_000), ("D", 3, 20_000), ("C", 3, 100_000),
                                   ("B", 3, length - 20_480)] {
            let station = try world.buildStation(named: name, at: PlanPoint(x: 1_024 + Int64(edge - 1) * length + 10_000, y: 2_048)).id
            try world.addTrackPlatform(station, on: .edge(edge), from: from, to: from + 19_456)
            stations[name] = station
        }
        world.setBlockSections(true)
        world.setCurveSpeedLimits(limits)
        var trains: [TrainID] = []
        for (from, edge, to) in [("S3", 2, "B"), ("S2", 2, "C"), ("S1", 1, "D")] {
            let id = try world.purchaseTrain(named: "T\(trains.count + 1)").id
            try world.setTrainCars(id, to: 2)
            let end: Int64 = ["S3": bowLength - 30_544, "S2": 39_456, "S1": 49_456][from]!
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: .forward), offset: end))
            try world.setTrainMovementRate(id, to: 4_096)
            try world.setTrainContinuation(id, along: [], stoppingAt: end)
            try world.setTrainTimetable(id, to: [
                ScheduledStop(station: stations[from]!, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
                ScheduledStop(station: stations[to]!, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 20)),
            ])
            trains.append(id)
        }
        try world.setTrafficControl(true)
        for id in trains {
            try world.startTrainService(id)
        }
        return (world, trains, bow)
    }

    /// No two trains ever hold the same track, they keep to the bow's limit
    /// on their runs, every one arrives, none sooner than with the limits
    /// off, and stepping by minutes gives the world stepping by seconds does.
    func testTrainsFollowingThroughBlockSectionsKeepToTheCurveAndApart() throws {
        var arrivals: [Bool: [TrainID: GameTime]] = [:]
        for limits in [false, true] {
            var (world, trains, bow) = try makeChain(limits: limits)
            if limits {
                XCTAssertLessThan(try XCTUnwrap(world.network.edge(bow)?.speedLimits.map(\.speed).min()), 110, "the bow is limited below the standard 110")
            }
            let start = world
            world.setSpeed(.x10)
            var seconds = 0
            var limited = 0
            var arrived: [TrainID: GameTime] = [:]
            while seconds < 3_600 {
                try world.advance(ticks: 1)
                seconds += 1
                let held = trains.map { Set(world.heldResources(of: $0)) }
                XCTAssertTrue(held[0].isDisjoint(with: held[1]) && held[0].isDisjoint(with: held[2]) && held[1].isDisjoint(with: held[2]),
                              "second \(seconds)")
                XCTAssertEqual(world.occupancyConflicts(), [])
                for id in trains {
                    let train = try XCTUnwrap(world.train(id: id))
                    if let run = train.times?.run, !run.limits.isEmpty {
                        limited += 1
                        if case .limited(let curve)? = world.runCurve(of: run, for: train.performance),
                           case .onEdge(let traversal, _)? = train.position, traversal.edge == bow {
                            let elapsed = (world.clock.now.seconds - run.start.seconds) * 1000
                            let here = run.limits.first { $0.start <= curve.distance(at: elapsed) && curve.distance(at: elapsed) < $0.end }
                            if let here { XCTAssertLessThanOrEqual(curve.speed(at: elapsed) * 100, here.speed * 102) }
                        }
                    }
                    if arrived[id] == nil, train.execution == nil { arrived[id] = world.clock.now }
                }
                if trains.allSatisfy({ world.train(id: $0)?.execution == nil }) { break }
            }
            XCTAssertEqual(arrived.count, 3, "every train arrived (limits \(limits)): \(trains.map { String(describing: world.train(id: $0)?.execution) })")
            XCTAssertEqual(limited > 0, limits)
            arrivals[limits] = arrived
            let minutesRun = seconds / 60 + 1
            var minutes = start
            try minutes.advance(ticks: minutesRun)
            var byTicks = start
            byTicks.setSpeed(.x10)
            try byTicks.advance(ticks: minutesRun * 60)
            byTicks.setSpeed(.normal)
            XCTAssertEqual(minutes, byTicks, "limits \(limits)")
        }
        for (id, time) in try XCTUnwrap(arrivals[true]) {
            XCTAssertGreaterThanOrEqual(time, try XCTUnwrap(arrivals[false]?[id]))
        }
    }

    /// Planning an overtake (decision 217, item 8): a stop is added on a
    /// leg only where its runs fit under the limits. T3 (S1 to D) passes S2
    /// and runs on through the bow: from S2 the bow's limit makes the
    /// least time without limits too short.
    func testAnOvertakeStopIsPlannedUnderTheLimits() throws {
        for limits in [false, true] {
            let (world, trains, _) = try makeChain(limits: limits)
            let train = try XCTUnwrap(world.train(id: trains[2]))
            let points = try XCTUnwrap(world.trafficPoints(of: train, cycle: 0))
            let service = GameWorld.TrafficService(train: train, points: points)
            let s2 = try XCTUnwrap(world.stations.first { $0.name == "S2" }?.id)
            let j = try XCTUnwrap(points.firstIndex { $0.station == s2 && !$0.calls })
            let b = try XCTUnwrap(points.indices.first { $0 > j && points[$0].calls })
            let distance = points[(j + 1)...b].reduce(Int64(0)) { $0 + $1.distance }
            let least = try XCTUnwrap(RunningCurve.leastSeconds(length: distance, performance: train.performance))
            XCTAssertEqual(world.trafficStopBuildable(service, at: j, departure: points[b].arrival - least), !limits,
                           limits ? "too short under the bow's limit" : "just fits without limits")
        }
    }
}
