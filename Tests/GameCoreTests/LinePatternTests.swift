import Foundation
import GameCore
import XCTest

/// Short workings and expresses (Phase 4 Stage Q3, ARCHITECTURE decision
/// 24): a line's patterns, calling at some of its stops, each with its own
/// counts, targets and trains; the room they share on each segment; and
/// their dispatch.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class LinePatternTests: XCTestCase {
    // A straight line, dead ends at both ends, a station above every other
    // tile:
    //
    //       A(1,0)  B(3,0)  C(5,0)  D(7,0)
    //         |       |       |       |
    //   o  -  a - o - b - o - c - o - d  -  o
    //
    // The line plans with a crawl (Stage W2c, `crawl`): each stop is 120 s
    // from the next, and A to D non-stop 350 s. Main (A, B, C, D) takes 12
    // minutes of travel, a minute at B and C each way and two at each end:
    // 20. B-C and back is 4 + 4 = 8; A-D non-stop and back is 700 s + 4
    // minutes, 940 s, which the line plans as 16 minutes.
    private let a = GridPosition(x: 1, y: 1)
    private let b = GridPosition(x: 3, y: 1)
    private let c = GridPosition(x: 5, y: 1)
    private let d = GridPosition(x: 7, y: 1)
    private let stationA = StationID(rawValue: 1)
    private let stationB = StationID(rawValue: 2)
    private let stationC = StationID(rawValue: 3)
    private let stationD = StationID(rawValue: 4)
    private let main = LineID(rawValue: 1)
    private let unknownLine = LineID(rawValue: 9)
    private let one = TrainID(rawValue: 1)
    private let two = TrainID(rawValue: 2)
    private let three = TrainID(rawValue: 3)
    private let ghost = TrainID(rawValue: 99)
    /// The line's performance (Stage W2c): a crawl at 1 km/h, about a link
    /// a minute. It reaches 1 km/h in 4 s and stops from it in 4 s, covering
    /// 35.6 units each time: two links take 8 + 111.2 s, planned as 120, and
    /// six 8 + 341.6 s, planned as 350.
    private let crawl = TrainPerformance(acceleration: 250, braking: 250, topSpeed: 1)

    private func makeWorld(minute: Int64 = 480) throws -> GameWorld {
        var world = try GameWorld(
            width: 9, height: 2, economy: GameEconomy(balance: 2_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minute), speed: .normal)
        )
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: .east)
        for x in 1...7 {
            try world.buildTrack(at: GridPosition(x: x, y: 1), connections: [.east, .west])
        }
        try world.buildTrack(at: GridPosition(x: 8, y: 1), connections: .west)
        for (name, x) in [("A", 1), ("B", 3), ("C", 5), ("D", 7)] {
            try world.buildStation(named: name, at: GridPosition(x: x, y: 0))
        }
        try world.createLine(named: "Main", stops: [stationA, stationB, stationC, stationD])
        try world.setLinePerformance(main, to: crawl)
        return world
    }

    /// Main at 5 / 2 / 0 trains, a short working B-C (pattern 0) at
    /// 4 / 1 / 1 with a 20-minute target at low, and an express A-D
    /// (pattern 1) at 2 / 1 / 0.
    private func makePatternWorld(minute: Int64 = 480) throws -> GameWorld {
        var world = try makeWorld(minute: minute)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 5, offPeak: 2, low: 0))
        try world.addLinePattern(main, calling: [1, 2])
        try world.addLinePattern(main, calling: [0, 3])
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 4, offPeak: 1, low: 1), pattern: 0)
        try world.setLineTargetHeadways(main, to: TargetHeadways(low: 20), pattern: 0)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 2, offPeak: 1, low: 0), pattern: 1)
        return world
    }

    /// A trip's stop for a train sent out at minute `sent`: arriving and
    /// leaving `arrival` and `departure` seconds after it (Stage W2b: a
    /// trip leaves its first call 42 s after the train is sent out).
    private func stop(_ station: StationID, sent: Int64, _ arrival: Int64, _ departure: Int64, reverses: Bool = false) -> ScheduledStop {
        ScheduledStop(
            station: station, arrival: GameTime(seconds: sent * 60 + arrival), departure: GameTime(seconds: sent * 60 + departure), reverses: reverses
        )
    }

    private func stop(_ station: StationID, _ arrival: Int64, _ departure: Int64, reverses: Bool = false) -> ScheduledStop {
        ScheduledStop(station: station, arrival: GameTime(minutes: arrival), departure: GameTime(minutes: departure), reverses: reverses)
    }

    // MARK: - Commands

    /// Adding checks the line, then the calls: two or more, rising, each an
    /// index of one of the line's stops. A new pattern goes after the
    /// others, with nothing in service, no targets and no trains; it is
    /// free and changes nothing else.
    func testAddingAPatternChecksTheLineThenItsCalls() throws {
        var world = try makeWorld()
        let before = world
        XCTAssertThrowsGameError(try world.addLinePattern(unknownLine, calling: [9]), .unknownLine(unknownLine))
        for calls in [[], [1], [2, 1], [1, 1], [-1, 2], [0, 4], [0, 2, 2], [3, 2, 1]] {
            XCTAssertThrowsGameError(try world.addLinePattern(main, calling: calls), .invalidLinePattern)
        }
        XCTAssertEqual(world, before, "refused commands change nothing")

        XCTAssertEqual(try world.addLinePattern(main, calling: [1, 2]), 0)
        XCTAssertEqual(try world.addLinePattern(main, calling: [0, 2, 3]), 1)
        XCTAssertEqual(try world.addLinePattern(main, calling: [1, 2]), 2, "the same calls twice are two services")
        let patterns = try XCTUnwrap(world.line(id: main)?.patterns)
        XCTAssertEqual(patterns.map(\.calls), [[1, 2], [0, 2, 3], [1, 2]])
        XCTAssertEqual(patterns[1], LinePattern(calls: [0, 2, 3]))
        XCTAssertEqual(patterns[1].trainsInService, .none)
        XCTAssertEqual(patterns[1].targetHeadways, .none)
        XCTAssertEqual(patterns[1].trains, [])
        XCTAssertNil(patterns[1].lastDispatch)
        XCTAssertEqual(world.economy, before.economy, "patterns are free")
        XCTAssertEqual(world.trains, before.trains)
    }

    /// Counts and targets for a pattern check the line, then the pattern,
    /// then the value; the line's own service stays as it was.
    func testPatternCountsAndTargetsCheckThePatternFirst() throws {
        var world = try makeWorld()
        try world.addLinePattern(main, calling: [1, 2])
        let before = world
        XCTAssertThrowsGameError(
            try world.setLineTrainsInService(unknownLine, to: TrainsInService(peak: -1, offPeak: 0, low: 0), pattern: 5), .unknownLine(unknownLine)
        )
        XCTAssertThrowsGameError(
            try world.setLineTrainsInService(main, to: TrainsInService(peak: -1, offPeak: 0, low: 0), pattern: 1), .unknownLinePattern(1)
        )
        XCTAssertThrowsGameError(
            try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 0, low: 0), pattern: -1), .unknownLinePattern(-1)
        )
        XCTAssertThrowsGameError(
            try world.setLineTrainsInService(main, to: TrainsInService(peak: -1, offPeak: 0, low: 0), pattern: 0), .invalidTrainsInService
        )
        XCTAssertThrowsGameError(try world.setLineTargetHeadways(main, to: TargetHeadways(peak: 1), pattern: 2), .unknownLinePattern(2))
        XCTAssertThrowsGameError(try world.setLineTargetHeadways(main, to: TargetHeadways(peak: 1), pattern: 0), .invalidHeadway)
        XCTAssertEqual(world, before)

        try world.setLineTrainsInService(main, to: TrainsInService(peak: 3, offPeak: 2, low: 1), pattern: 0)
        try world.setLineTargetHeadways(main, to: TargetHeadways(offPeak: 30), pattern: 0)
        let line = try XCTUnwrap(world.line(id: main))
        XCTAssertEqual(line.patterns[0].trainsInService, TrainsInService(peak: 3, offPeak: 2, low: 1))
        XCTAssertEqual(line.patterns[0].targetHeadways, TargetHeadways(offPeak: 30))
        XCTAssertEqual(line.trainsInService, .none, "the line's own service is untouched")
        XCTAssertEqual(line.targetHeadways, .none)
    }

    /// Assigning to a pattern checks the train, the line, the pattern, that
    /// the train is on no line or pattern, and that it runs no service of
    /// its own, in that order. Unassigning takes it off whichever service
    /// it is on.
    func testAssigningToAPatternChecksInOrder() throws {
        var world = try makeWorld()
        try world.addLinePattern(main, calling: [1, 2])
        for index in 1...3 {
            try world.purchaseTrain(named: "T\(index)")
        }
        try world.placeTrain(three, at: .atNode(b, heading: .east))
        try world.setTrainTimetable(three, to: [stop(stationB, 480, 500)])
        try world.startTrainService(three)

        let before = world
        XCTAssertThrowsGameError(try world.assignTrain(ghost, to: unknownLine, pattern: 7), .unknownTrain(ghost))
        XCTAssertThrowsGameError(try world.assignTrain(one, to: unknownLine, pattern: 7), .unknownLine(unknownLine))
        XCTAssertThrowsGameError(try world.assignTrain(one, to: main, pattern: 7), .unknownLinePattern(7))
        XCTAssertThrowsGameError(try world.assignTrain(three, to: main, pattern: 0), .trainServiceActive(three))
        XCTAssertEqual(world, before)

        try world.assignTrain(two, to: main, pattern: 0)
        try world.assignTrain(one, to: main, pattern: 0)
        XCTAssertThrowsGameError(try world.assignTrain(one, to: main), .trainOnLine(one))
        XCTAssertThrowsGameError(try world.assignTrain(one, to: main, pattern: 0), .trainOnLine(one))
        XCTAssertEqual(world.line(id: main)?.patterns[0].trains, [one, two], "kept in ID order")
        XCTAssertEqual(world.line(id: main)?.trains, [])
        XCTAssertEqual(world.assignedLine(of: one), main)
        XCTAssertEqual(world.assignedPattern(of: one), 0)
        XCTAssertNil(world.assignedPattern(of: three))

        // A line's own train has a line but no pattern.
        try world.stopTrainService(three)
        try world.assignTrain(three, to: main)
        XCTAssertEqual(world.assignedLine(of: three), main)
        XCTAssertNil(world.assignedPattern(of: three))

        // The manual controls are closed to a pattern's train, as to a line's.
        XCTAssertThrowsGameError(try world.setTrainTimetable(one, to: []), .trainOnLine(one))
        XCTAssertThrowsGameError(try world.startTrainService(one), .trainOnLine(one))

        try world.unassignTrain(one)
        XCTAssertEqual(world.line(id: main)?.patterns[0].trains, [two])
        XCTAssertNil(world.assignedLine(of: one))
        XCTAssertThrowsGameError(try world.unassignTrain(one), .trainNotOnLine(one))
    }

    /// New stops keep the patterns' calls as indices; stops that would
    /// leave a pattern calling past the last are refused, after the stops
    /// themselves are checked.
    func testNewStopsKeepPatternsThatStillFit() throws {
        var world = try makeWorld()
        try world.addLinePattern(main, calling: [0, 3])
        let before = world
        XCTAssertThrowsGameError(try world.setLineStops(main, to: [stationA]), .invalidLineStops)
        XCTAssertThrowsGameError(try world.setLineStops(main, to: [stationA, StationID(rawValue: 9)]), .unknownStation(StationID(rawValue: 9)))
        XCTAssertThrowsGameError(try world.setLineStops(main, to: [stationA, stationB, stationC]), .invalidLinePattern)
        XCTAssertEqual(world, before)

        try world.setLineStops(main, to: [stationD, stationC, stationB, stationA, stationB])
        XCTAssertEqual(world.line(id: main)?.patterns.map(\.calls), [[0, 3]], "now D to A")
        XCTAssertEqual(world.lineJourney(main, pattern: 0)?.legs.map { [$0.from, $0.to] }, [[0, 3], [3, 0]])
    }

    /// Removing a pattern takes its trains off the line, moves the later
    /// patterns down one index and leaves a train on a trip to finish it
    /// as an ordinary service.
    func testRemovingAPatternUnassignsItsTrains() throws {
        var world = try makePatternWorld()
        let shuttle = try world.purchaseTrain(named: "Shuttle").id
        let express = try world.purchaseTrain(named: "Express").id
        try world.placeTrain(shuttle, at: .atNode(b, heading: .east))
        try world.setTrainMovementRate(shuttle, to: 1024)
        try world.assignTrain(shuttle, to: main, pattern: 0)
        try world.assignTrain(express, to: main, pattern: 1)
        try world.advance(ticks: 1)
        XCTAssertNotNil(world.train(id: shuttle)?.execution, "sent out at 480")

        let before = world
        XCTAssertThrowsGameError(try world.removeLinePattern(unknownLine, at: 0), .unknownLine(unknownLine))
        XCTAssertThrowsGameError(try world.removeLinePattern(main, at: 2), .unknownLinePattern(2))
        XCTAssertEqual(world, before)

        try world.removeLinePattern(main, at: 0)
        XCTAssertEqual(world.line(id: main)?.patterns.map(\.calls), [[0, 3]])
        XCTAssertEqual(world.assignedPattern(of: express), 0, "the express moved down")
        XCTAssertNil(world.assignedLine(of: shuttle))
        XCTAssertEqual(world.train(id: shuttle), before.train(id: shuttle), "the train itself is untouched")

        // The trip ends on its return (486:42) once the train has dwelt
        // there, at 487:24, and nothing sends it out again.
        try world.advance(ticks: 20)
        XCTAssertNil(world.train(id: shuttle)?.execution)
        XCTAssertEqual(world.train(id: shuttle)?.timetable.first?.departure, GameTime(seconds: 480 * 60 + 42))
    }

    // MARK: - Derived

    /// A pattern's journey calls only at its calls, the legs numbered by
    /// the line's stops, from a platform of its first call.
    func testPatternJourneysCallOnlyAtTheirCalls() throws {
        let world = try makePatternWorld()
        let short = try XCTUnwrap(world.lineJourney(main, pattern: 0))
        XCTAssertEqual(short.start, .atNode(b, heading: .north))
        XCTAssertEqual(short.legs.map { [$0.from, $0.to] }, [[1, 2], [2, 1]])
        XCTAssertEqual(short.legs.map(\.route), [[GridPosition(x: 4, y: 1), c], [GridPosition(x: 4, y: 1), b]])
        XCTAssertEqual(short.legs.map(\.seconds), [120, 120])
        XCTAssertEqual(short.roundTripSeconds, 480)
        XCTAssertEqual(short.roundTripMinutes, 8)

        let express = try XCTUnwrap(world.lineJourney(main, pattern: 1))
        XCTAssertEqual(express.start, .atNode(a, heading: .north))
        XCTAssertEqual(express.legs.map { [$0.from, $0.to] }, [[0, 3], [3, 0]])
        XCTAssertEqual(express.legs.map(\.seconds), [350, 350], "it passes B and C")
        XCTAssertEqual(express.roundTripSeconds, 940)
        XCTAssertEqual(express.roundTripMinutes, 16, "rounded up")

        XCTAssertEqual(world.lineJourney(main)?.legs.map(\.seconds), [120, 120, 120, 120, 120, 120])
        XCTAssertEqual(world.lineJourney(main)?.roundTripSeconds, 1200)
        XCTAssertEqual(world.lineJourney(main)?.roundTripMinutes, 20)
        XCTAssertEqual(world.lineJourney(main, pattern: nil), world.lineJourney(main))
        XCTAssertNil(world.lineJourney(main, pattern: 2))
        XCTAssertNil(world.lineJourney(main, pattern: -1))
        XCTAssertNil(world.lineJourney(unknownLine, pattern: 0))

        XCTAssertEqual(world.lineMaximumTrains(main), 10)
        XCTAssertEqual(world.lineMaximumTrains(main, pattern: 0), 4)
        XCTAssertEqual(world.lineMaximumTrains(main, pattern: 1), 8)
        XCTAssertNil(world.lineMaximumTrains(main, pattern: 2))
    }

    /// Each segment carries at most 720 trains a day; services claim it in
    /// order, the line's own first, each with a day's trains at its
    /// headway, rounded up, on every segment from its first call to its
    /// last.
    func testServicesShareEverySegmentInOrder() throws {
        let world = try makePatternWorld()
        XCTAssertEqual(ServiceLine.segmentCapacity, 720)

        // Peak: Main 5 trains 4 apart, 360 on every segment. The short
        // working asks for 4 trains 2 apart, 720, on B-C, where 360 is
        // left: 3 trains (3 apart, 480) do not fit, 2 (4 apart, 360) do.
        // Nothing is left on B-C for the express, which crosses it.
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak), 5)
        XCTAssertEqual(world.lineHeadway(main, at: .peak), 4)
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak, pattern: 0), 2)
        XCTAssertEqual(world.lineHeadway(main, at: .peak, pattern: 0), 4)
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak, pattern: 1), 0)
        XCTAssertNil(world.lineHeadway(main, at: .peak, pattern: 1))
        XCTAssertEqual(world.lineSegmentLoads(main, at: .peak), [360, 720, 360])

        // Off-peak: 2 trains 10 apart (144), 1 train 8 apart (180), 1
        // train 16 apart (90): all fit.
        XCTAssertEqual(world.lineTrainsInService(main, at: .offPeak, pattern: 1), 1)
        XCTAssertEqual(world.lineHeadway(main, at: .offPeak, pattern: 1), 16)
        XCTAssertEqual(world.lineSegmentLoads(main, at: .offPeak), [234, 414, 234])

        // Low: Main runs none; the short working keeps its 20-minute
        // target with one train (72). A-B and C-D are not covered.
        XCTAssertEqual(world.lineTrainsInService(main, at: .low), 0)
        XCTAssertEqual(world.lineTrainsInService(main, at: .low, pattern: 0), 1)
        XCTAssertEqual(world.lineHeadway(main, at: .low, pattern: 0), 20)
        XCTAssertEqual(world.lineSegmentLoads(main, at: .low), [0, 72, 0])

        XCTAssertNil(world.lineSegmentLoads(unknownLine, at: .low))
        XCTAssertNil(world.lineTrainsInService(main, at: .low, pattern: 2))
        XCTAssertNil(world.lineHeadway(unknownLine, at: .low, pattern: 0))
    }

    /// The line's own service is never cut, and a pattern whose journey
    /// cannot be driven takes no room.
    func testTheLinesOwnServiceIsNeverCutAndUndrivablePatternsTakeNoRoom() throws {
        var world = try makePatternWorld()
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 10, offPeak: 0, low: 0))
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak), 10, "10 trains 2 apart: all 720")
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak, pattern: 0), 0)
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak, pattern: 1), 0)
        XCTAssertEqual(world.lineSegmentLoads(main, at: .peak), [720, 720, 720])

        // Cut the track between C and D: Main and the express cannot be
        // driven, and the short working has B-C to itself.
        try world.removeTrack(at: GridPosition(x: 6, y: 1))
        XCTAssertNil(world.lineTrainsInService(main, at: .peak))
        XCTAssertNil(world.lineTrainsInService(main, at: .peak, pattern: 1))
        XCTAssertEqual(world.lineTrainsInService(main, at: .peak, pattern: 0), 4)
        XCTAssertEqual(world.lineHeadway(main, at: .peak, pattern: 0), 2)
        XCTAssertEqual(world.lineSegmentLoads(main, at: .peak), [0, 720, 0])
    }

    // MARK: - Dispatch

    /// A pattern sends its own trains out from its first call, on trips
    /// calling only at its calls, when it runs trains beside the services
    /// before it: the express waits through the peak, when the short
    /// working fills B-C, and is sent out at 600.
    func testPatternsSendTheirOwnTrainsOut() throws {
        var world = try makePatternWorld()
        let shuttle = try world.purchaseTrain(named: "Shuttle").id
        let express = try world.purchaseTrain(named: "Express").id
        try world.placeTrain(shuttle, at: .atNode(b, heading: .east))
        try world.placeTrain(express, at: .atNode(a, heading: .east))
        for id in [shuttle, express] {
            try world.setTrainMovementRate(id, to: 1024)
        }
        try world.assignTrain(shuttle, to: main, pattern: 0)
        try world.assignTrain(express, to: main, pattern: 1)

        try world.advance(ticks: 1)
        XCTAssertEqual(
            world.train(id: shuttle)?.timetable,
            [stop(stationB, sent: 480, 0, 42), stop(stationC, sent: 480, 162, 282, reverses: true), stop(stationB, sent: 480, 402, 402, reverses: true)]
        )
        XCTAssertEqual(world.line(id: main)?.patterns[0].lastDispatch, GameTime(minutes: 480))
        XCTAssertNil(world.line(id: main)?.lastDispatch, "the line's own service sent nothing")
        XCTAssertEqual(world.train(id: express)?.timetable, [], "no room at peak")

        // Back at B at 486:42, where the trip ends at 487:24; the next is
        // sent out at 488, due since 484 and one train of two running.
        try world.advance(ticks: 8)
        XCTAssertEqual(world.train(id: shuttle)?.timetable.first, stop(stationB, sent: 488, 0, 42))
        XCTAssertEqual(world.line(id: main)?.patterns[0].lastDispatch, GameTime(minutes: 488))

        // Every 8 minutes up to 592, and at 600, off-peak (one train, 8
        // apart); at 600 the express is sent out too, calling at A and D
        // only.
        try world.advance(ticks: 112)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 601))
        XCTAssertEqual(world.train(id: shuttle)?.timetable.first, stop(stationB, sent: 600, 0, 42))
        XCTAssertEqual(
            world.train(id: express)?.timetable,
            [stop(stationA, sent: 600, 0, 42), stop(stationD, sent: 600, 392, 512, reverses: true), stop(stationA, sent: 600, 862, 862, reverses: true)]
        )
        XCTAssertEqual(world.line(id: main)?.patterns[1].lastDispatch, GameTime(minutes: 600))

        // Single steps agree with the batch.
        var stepped = try makePatternWorld()
        let s = try stepped.purchaseTrain(named: "Shuttle").id
        let e = try stepped.purchaseTrain(named: "Express").id
        try stepped.placeTrain(s, at: .atNode(b, heading: .east))
        try stepped.placeTrain(e, at: .atNode(a, heading: .east))
        for id in [s, e] {
            try stepped.setTrainMovementRate(id, to: 1024)
        }
        try stepped.assignTrain(s, to: main, pattern: 0)
        try stepped.assignTrain(e, to: main, pattern: 1)
        for _ in 0..<121 {
            try stepped.advance(ticks: 1)
        }
        XCTAssertEqual(stepped, world)
    }

    // MARK: - Saving

    /// Patterns save only when a line has some, and load back equal;
    /// patterns that break a rule are refused rather than repaired.
    func testPatternsSaveAndBadPatternsAreRefused() throws {
        var world = try makePatternWorld()
        let shuttle = try world.purchaseTrain(named: "Shuttle").id
        try world.placeTrain(shuttle, at: .atNode(b, heading: .east))
        try world.setTrainMovementRate(shuttle, to: 1024)
        try world.assignTrain(shuttle, to: main, pattern: 0)
        try world.advance(ticks: 3)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let text = String(decoding: data, as: UTF8.self)
        // Stage W2a: saved times are seconds, minute 480 is 28800.
        XCTAssertTrue(text.contains(#""patterns":[{"calls":[1,2],"lastDispatch":28800,"targetHeadways":{"low":20},"trains":[1],"#), text)
        XCTAssertTrue(text.contains(#"{"calls":[0,3],"trainsInService":{"low":0,"offPeak":1,"peak":2}}"#), "unused keys are left out")

        let plain = try encoder.encode(try makeWorld())
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("patterns"), "a line without patterns saves as before")

        func refused(_ old: String, _ new: String, _ why: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(text.contains(old), "fixture text changed: \(old)", file: file, line: line)
            let bad = Data(text.replacingOccurrences(of: old, with: new).utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: bad), why, file: file, line: line)
        }
        refused(#""calls":[1,2]"#, #""calls":[2,1]"#, "calls must rise")
        refused(#""calls":[1,2]"#, #""calls":[1]"#, "two calls or more")
        refused(#""calls":[0,3]"#, #""calls":[0,4]"#, "a call past the last stop")
        refused(#""calls":[1,2]"#, #""calls":[-1,2]"#, "a negative call")
        refused(#""trains":[1],"#, #""trains":[7],"#, "an unknown train")
        refused(#""trains":[1],"#, #""trains":[1,1],"#, "a train twice")
        refused(#""lastDispatch":28800"#, #""lastDispatch":54000"#, "a dispatch after the clock")
        refused(#""lastDispatch":28800"#, #""lastDispatch":null"#, "an explicit null")
        refused(#""targetHeadways":{"low":20}"#, #""targetHeadways":{"low":1}"#, "a target below 2")
        refused(#""trainsInService":{"low":0,"offPeak":1,"peak":2}}"#, #""trainsInService":{"low":0,"offPeak":1,"peak":-2}}"#, "a negative count")
        refused(#""patterns":[{"#, #""trains":[1],"patterns":[{"#, "a train on the line and on a pattern")
    }
}
