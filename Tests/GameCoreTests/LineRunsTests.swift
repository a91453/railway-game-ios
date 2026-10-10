import Foundation
@testable import GameCore
import XCTest

/// A line's runs (ARCHITECTURE decision 133): the trains of a real
/// timetable, each one way between two of the line's stops at the times it
/// lists, sent out from where they stand instead of at a headway.
final class LineRunsTests: XCTestCase {
    private let track = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let blue = TrainID(rawValue: 1)

    /// Alpha → Gamma leaving at 00:10, calling at Beta 00:15–00:16; and
    /// back at 00:30, Beta 00:35–00:36, Alpha 00:40. Every day.
    private let out = LineRun(from: 0, to: 2, times: [
        LineRunTime(arrival: 600, departure: 600), LineRunTime(arrival: 900, departure: 960), LineRunTime(arrival: 1_200, departure: 1_200),
    ])
    private let back = LineRun(from: 2, to: 0, times: [
        LineRunTime(arrival: 1_800, departure: 1_800), LineRunTime(arrival: 2_100, departure: 2_160), LineRunTime(arrival: 2_400, departure: 2_400),
    ])

    /// Alpha, Beta and Gamma on a straight track, the line Main calling at
    /// all three, and the train Blue at Alpha facing Gamma, on the line.
    private func world(runs: [LineRun]? = nil) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try track.build(in: &world)
        try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try track.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        _ = try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        _ = try world.purchaseTrain(named: "Blue")
        try world.placeTrain(blue, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(blue, to: 1_024)
        try world.assignTrain(blue, to: main)
        try world.setLineRuns(main, to: runs ?? [out, back])
        // A tick a minute.
        world.setSpeed(.normal)
        return world
    }

    private func seconds(_ timetable: [ScheduledStop]?) -> [[Int64]] {
        (timetable ?? []).map { [$0.arrival.seconds, $0.departure.seconds] }
    }

    // MARK: - Sending trains out

    /// The run out sends Blue five minutes before it leaves, and the train
    /// keeps the run's times; at Gamma it waits for the run back, which
    /// turns it round first, and at Alpha the day's runs are done.
    func testRunsSendTheTrainOutAtTheirTimes() throws {
        var world = try world()
        try world.advance(ticks: 5)
        XCTAssertNil(world.train(id: blue)?.execution, "not yet: the run out leaves at 00:10")
        try world.advance(ticks: 1)
        let sent = try XCTUnwrap(world.train(id: blue))
        XCTAssertEqual(sent.timetable.map(\.station), [alpha, beta, gamma])
        XCTAssertEqual(seconds(sent.timetable), [[300, 600], [900, 960], [1_200, 1_200]])
        XCTAssertEqual(sent.timetable.map(\.reverses), [false, false, false])
        XCTAssertEqual(world.line(id: main)?.runDays, [0, nil])

        // 00:24: the run out ended at 00:20.
        try world.advance(ticks: 18)
        XCTAssertNil(world.train(id: blue)?.execution, "the run ended at Gamma")
        XCTAssertEqual(world.stationsStoppedAt(by: blue), [gamma])
        // The run back sends it at 00:25.
        try world.advance(ticks: 2)
        let back = try XCTUnwrap(world.train(id: blue))
        XCTAssertEqual(back.timetable.map(\.station), [gamma, beta, alpha])
        XCTAssertEqual(seconds(back.timetable), [[1_500, 1_800], [2_100, 2_160], [2_400, 2_400]])
        XCTAssertEqual(back.timetable.first?.reverses, true, "it came in facing Gamma")
        XCTAssertEqual(world.line(id: main)?.runDays, [0, 0])
        try world.advance(ticks: 20)
        XCTAssertEqual(world.stationsStoppedAt(by: blue), [alpha])
        XCTAssertNil(world.train(id: blue)?.execution)
        // The next day the run out goes again.
        try world.advance(ticks: 1_400)
        XCTAssertEqual(world.line(id: main)?.runDays, [1, 0])
        XCTAssertEqual(seconds(world.train(id: blue)?.timetable).first, [86_700, 87_000])
    }

    /// A run that runs only at weekends does not go on day 0, a Monday; a
    /// run with no train at its start waits for one half an hour, and is
    /// then dropped for the day.
    func testDaysAndLateRuns() throws {
        let weekend = (1 << 0) | (1 << 6)
        let saturday = LineRun(from: 0, to: 2, times: out.times, days: weekend)
        var world = try world(runs: [saturday])
        try world.advance(ticks: 60)
        XCTAssertNil(world.train(id: blue)?.execution)
        XCTAssertEqual(world.line(id: main)?.runDays, [nil])
        XCTAssertTrue(saturday.runs(onDay: 5), "day 5 is a Saturday")
        XCTAssertFalse(saturday.runs(onDay: 0))

        // Only the run back, from Gamma, where no train stands: it is never
        // sent, and the train at Alpha stays.
        var late = try self.world(runs: [back])
        try late.advance(ticks: 120)
        XCTAssertNil(late.train(id: blue)?.execution)
        XCTAssertEqual(late.line(id: main)?.runDays, [nil])
        XCTAssertEqual(late.line(id: main)?.dueRuns(at: GameTime(seconds: 1_800 + LineRun.latestDispatch)).map { $0.run }, [0])
        XCTAssertEqual(late.line(id: main)?.dueRuns(at: GameTime(seconds: 1_801 + LineRun.latestDispatch)).map { $0.run }, [])
    }

    /// Advancing many minutes at once skips the idle ones but sends the
    /// trains out exactly as minute by minute.
    func testIdleMinutesAreSkippedExactly() throws {
        var once = try world()
        var stepwise = once
        try once.advance(ticks: 3_000)
        for _ in 0..<3_000 { try stepwise.advance(ticks: 1) }
        XCTAssertEqual(once, stepwise)
        XCTAssertEqual(once.line(id: main)?.runDays, [2, 2])
    }

    // MARK: - Riders and the line's queries

    /// A run's riders go its way to its end, and the line's headway is the
    /// span of its runs shared between the runs each way.
    func testRidersGoTheRunsWayAndTheHeadwayComesFromTheRuns() throws {
        var world = try world()
        try world.advance(ticks: 6)
        let train = try XCTUnwrap(world.train(id: blue))
        XCTAssertEqual(world.directionEnd(of: train, from: 0), 2, "one way to its end, not half way")
        XCTAssertEqual(world.lineHeadway(main, at: .peak), 1_440, "one run each way: a day")
        XCTAssertEqual(world.lineTrainsInService(main, at: .low), 1)

        let later = LineRun(from: 0, to: 2, times: out.times.map { LineRunTime(arrival: $0.arrival + 3_600, departure: $0.departure + 3_600) })
        var two = try self.world(runs: [out, later, back])
        XCTAssertEqual(two.lineHeadway(main, at: .peak), 60, "the runs out an hour apart")
        try two.setLineRuns(main, to: [])
        XCTAssertFalse(two.line(id: main)?.hasRuns ?? true)
    }

    // MARK: - Commands

    func testSettingRunsChecksThem() throws {
        var world = try world(runs: [])
        let before = world
        XCTAssertThrowsError(try world.setLineRuns(LineID(rawValue: 9), to: [out])) { XCTAssertEqual($0 as? GameError, .unknownLine(LineID(rawValue: 9))) }
        let bad = [
            LineRun(from: 1, to: 1, times: [LineRunTime(arrival: 0, departure: 0)]),
            LineRun(from: 0, to: 3, times: out.times + [LineRunTime(arrival: 1_300, departure: 1_300)]),
            LineRun(from: 0, to: 2, times: Array(out.times.prefix(2))),
            LineRun(from: 0, to: 2, times: [out.times[1], out.times[0], out.times[2]]),
            LineRun(from: 0, to: 2, times: out.times, days: 0),
            LineRun(from: 0, to: 2, times: out.times, days: 128),
            LineRun(from: 0, to: 1, times: [LineRunTime(arrival: -1, departure: 0), LineRunTime(arrival: 60, departure: 60)]),
            LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 0, departure: LineRun.latestSecond), LineRunTime(arrival: LineRun.latestSecond, departure: LineRun.latestSecond)]),
        ]
        for run in bad {
            XCTAssertThrowsError(try world.setLineRuns(main, to: [run])) { XCTAssertEqual($0 as? GameError, .invalidLineRuns, "\(run)") }
        }
        XCTAssertEqual(world, before, "refused runs change nothing")

        // A line with runs takes no pattern and is no ring; one with a
        // pattern, or calling at a station twice, takes no runs.
        try world.setLineRuns(main, to: [out])
        XCTAssertThrowsError(try world.addLinePattern(main, calling: [0, 2])) { XCTAssertEqual($0 as? GameError, .invalidLinePattern) }
        XCTAssertThrowsError(try world.setLineRing(main, to: true)) { XCTAssertEqual($0 as? GameError, .invalidLineRuns) }
        let twice = try world.createLine(named: "Twice", stops: [alpha, beta, alpha]).id
        XCTAssertThrowsError(try world.setLineRuns(twice, to: [LineRun(from: 0, to: 1, times: Array(out.times.prefix(2)))])) {
            XCTAssertEqual($0 as? GameError, .invalidLineRuns)
        }

        // Not while one of its trains runs a service.
        try world.advance(ticks: 6)
        XCTAssertNotNil(world.train(id: blue)?.execution)
        XCTAssertThrowsError(try world.setLineRuns(main, to: [])) { XCTAssertEqual($0 as? GameError, .trainServiceActive(blue)) }
    }

    /// Reversing the stops keeps each run at the same stations; new stops
    /// end the runs; a copy has them, none run yet.
    func testLineEditsKeepOrEndTheRuns() throws {
        var world = try world()
        try world.advance(ticks: 6)
        try world.reverseLineStops(main)
        let reversed = try XCTUnwrap(world.line(id: main))
        XCTAssertEqual(reversed.runs.map { [$0.from, $0.to] }, [[2, 0], [0, 2]])
        XCTAssertEqual(reversed.runs.map { $0.calls.map { reversed.stops[$0] } }, [[alpha, beta, gamma], [gamma, beta, alpha]])
        XCTAssertEqual(reversed.runDays, [0, nil])

        let copy = try world.duplicateLine(main, named: "Copy")
        XCTAssertEqual(copy.runs, reversed.runs)
        XCTAssertEqual(copy.runDays, [nil, nil])

        try world.setLineStops(main, to: [alpha, gamma])
        XCTAssertEqual(world.line(id: main)?.runs, [])
        XCTAssertEqual(world.line(id: main)?.runDays, [])
    }

    // MARK: - Saving

    /// Version 30 (decision 133): the line Main with its two runs, the run
    /// out sent on day 0 and Blue on it. It saves byte for byte and is the
    /// world this build makes.
    func testVersionThirtyKeepsTheRuns() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v30-line-runs.json")
        var made = try world()
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["LINE_RUNS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 30)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.line(id: main)?.runs, [out, back])
        XCTAssertEqual(world.line(id: main)?.runDays, [0, nil])
        XCTAssertEqual(seconds(world.train(id: blue)?.timetable), [[300, 600], [900, 960], [1_200, 1_200]])
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 30,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    func testRunsSaveAndLoad() throws {
        var world = try world()
        try world.advance(ticks: 6)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(XCTUnwrap(world.line(id: main))), encoding: .utf8))
        XCTAssertTrue(json.contains(#""runDays":[0,null]"#), json)

        // A line saved without runs reads as a headway line; runs a line
        // cannot have are refused.
        let plain = try JSONEncoder().encode(ServiceLine(id: main, name: "Main", stops: [alpha, beta, gamma]))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("runs"))
        let line = try XCTUnwrap(world.line(id: main))
        for broken in [
            #""runs":[]"#,
            #""runs":[{"from":0,"to":0,"times":[[0,0]]}]"#,
            #""runs":[{"from":0,"to":2,"times":[[600,600],[900,960],[1200,1200]]}],"runDays":[0,0]"#,
            #""runs":[{"from":0,"to":2,"times":[[600,600],[900,960],[1200,1200]]}],"runDays":[-1]"#,
        ] {
            let text = String(decoding: try JSONEncoder().encode(ServiceLine(id: line.id, name: line.name, stops: line.stops)), as: UTF8.self)
                .replacingOccurrences(of: #""stops":"#, with: broken + #","stops":"#)
            XCTAssertThrowsError(try JSONDecoder().decode(ServiceLine.self, from: Data(text.utf8)), broken)
        }
    }
}
