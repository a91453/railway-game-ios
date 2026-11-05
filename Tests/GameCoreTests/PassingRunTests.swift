import Foundation
@testable import GameCore
import XCTest

/// Decision 605: a run (decision 133) can pass stops without calling there,
/// as the Taoyuan Airport MRT's express trains pass every station but a
/// few. The network is ``LocalPassTests``': double track 13.4 km long,
/// West, A, Middle, B and East about 3.3 km apart, Middle with a loop
/// beside the eastbound track (its platform on e12).
final class PassingRunTests: XCTestCase {
    private func at(_ seconds: Int64, _ dwell: Int64 = 0) -> LineRunTime { LineRunTime(arrival: seconds, departure: seconds + dwell) }

    /// One line, two runs from West: a stopping one at 10:00 calling at all
    /// five stations, and an express at 13:00 calling only at West and East,
    /// back from East at 26:00 (it stands at East's one eastbound platform
    /// until then). Both trains stand at West.
    private func line() throws -> (world: GameWorld, local: TrainID, express: TrainID, stations: [StationID], line: LineID) {
        var (world, line, ids) = try LocalPassTests.world()
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 4, times: [at(600), at(780, 60), at(1_020, 60), at(1_260, 60), at(1_500)]),
            LineRun(from: 0, to: 4, times: [at(780), at(1_440)], passes: [1, 2, 3]),
            LineRun(from: 4, to: 0, times: [at(1_560), at(2_220)], passes: [3, 2, 1]),
        ])
        var trains: [TrainID] = []
        for (i, position) in [TrainPosition.onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 14_336),
                              .onEdge(TrackTraversal(edge: .edge(6), direction: .forward), offset: 14_336)].enumerated() {
            let id = try world.purchaseTrain(named: "T\(i + 1)").id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: position)
            if case .onEdge(_, let offset) = position { try world.setTrainContinuation(id, along: [], stoppingAt: offset) }
            try world.setTrainMovementRate(id, to: 1_024)
            try world.assignTrain(id, to: line)
            trains.append(id)
        }
        world.setSpeed(.x1)
        return (world, trains[0], trains[1], ids, line)
    }

    func testARunCallsOnlyWhereItDoesNotPass() {
        let express = LineRun(from: 0, to: 4, times: [at(0), at(10)], passes: [1, 2, 3])
        XCTAssertEqual(express.calls, [0, 4])
        XCTAssertTrue(express.isValid(stopCount: 5))
        let back = LineRun(from: 4, to: 0, times: [at(0), at(5), at(10)], passes: [3, 1])
        XCTAssertEqual(back.calls, [4, 2, 0])
        XCTAssertTrue(back.isValid(stopCount: 5))
        XCTAssertEqual(LineRun(from: 0, to: 4, times: (0..<5).map { at(Int64($0)) }).calls, [0, 1, 2, 3, 4], "a run without passes calls everywhere, as before")
    }

    func testPassesThatAreNotBetweenItsCallsAreRefused() {
        XCTAssertFalse(LineRun(from: 0, to: 4, times: [at(0), at(5), at(10)], passes: [0, 2]).isValid(stopCount: 5), "its first call")
        XCTAssertFalse(LineRun(from: 0, to: 4, times: [at(0), at(5), at(10)], passes: [2, 4]).isValid(stopCount: 5), "its last call")
        XCTAssertFalse(LineRun(from: 0, to: 3, times: [at(0), at(5), at(10)], passes: [4]).isValid(stopCount: 5), "beyond it")
        XCTAssertFalse(LineRun(from: 0, to: 4, times: [at(0), at(5), at(10)], passes: [3, 1]).isValid(stopCount: 5), "out of order")
        XCTAssertFalse(LineRun(from: 0, to: 4, times: [at(0), at(5), at(10)], passes: [2, 2]).isValid(stopCount: 5), "twice")
        XCTAssertFalse(LineRun(from: 0, to: 4, times: (0..<5).map { at(Int64($0)) }, passes: [2]).isValid(stopCount: 5), "a time for a stop it passes")
    }

    func testARingRunPassesStopsRoundItsWay() {
        let run = LineRun(from: 4, to: 1, times: [at(0), at(5), at(10)], way: .inner, passes: [5])
        XCTAssertEqual(run.calls(stopCount: 6), [4, 0, 1])
        XCTAssertTrue(run.isValid(stopCount: 6, ring: true))
        XCTAssertFalse(LineRun(from: 4, to: 1, times: [at(0), at(5), at(10)], way: .inner, passes: [2]).isValid(stopCount: 6, ring: true), "not on its way round")
        let lap = LineRun(from: 0, to: 0, times: [at(0), at(5), at(6), at(7), at(8), at(10)], way: .outer, passes: [3])
        XCTAssertEqual(lap.calls(stopCount: 6), [0, 5, 4, 2, 1, 0])
        XCTAssertTrue(lap.isValid(stopCount: 6, ring: true))
    }

    func testPassesAreSavedAndLeftOutWhenThereAreNone() throws {
        let run = LineRun(from: 0, to: 4, times: [at(0), at(10)], passes: [1, 2, 3])
        let data = try JSONEncoder().encode(run)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""passes":[1,2,3]"#))
        XCTAssertEqual(try JSONDecoder().decode(LineRun.self, from: data), run)
        let plain = try JSONEncoder().encode(LineRun(from: 0, to: 1, times: [at(0), at(10)]))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("passes"), "a run calling everywhere is written as before")
        XCTAssertThrowsError(try JSONDecoder().decode(LineRun.self, from: Data(#"{"from":0,"to":1,"times":[[0,0],[10,10]],"passes":[]}"#.utf8)))
    }

    func testALineRefusesARunWhosePassesDoNotFitIt() throws {
        var (world, line, _) = try LocalPassTests.world()
        let before = world
        XCTAssertThrowsError(try world.setLineRuns(line, to: [LineRun(from: 0, to: 4, times: [at(0), at(10)], passes: [1, 2])]))
        XCTAssertEqual(world, before)
    }

    /// Riders are not sent to a stop only a passing run goes by.
    func testOnlyRunsCallingAtBothServeARide() throws {
        var (world, line, _) = try LocalPassTests.world()
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 4, times: [at(0), at(5), at(10)], passes: [1, 3])])
        let served = try XCTUnwrap(world.line(id: line))
        XCTAssertTrue(served.runsServe(from: 0, to: 2))
        XCTAssertTrue(served.runsServe(from: 2, to: 4))
        XCTAssertFalse(served.runsServe(from: 0, to: 1), "it passes A")
        XCTAssertFalse(served.runsServe(from: 3, to: 4), "it passes B")
        XCTAssertFalse(served.runsServe(from: 4, to: 0), "nor goes back")
    }

    func testReversingTheStopsKeepsThePassedStations() throws {
        var (world, line, _) = try LocalPassTests.world()
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 4, times: [at(0), at(5), at(10)], passes: [1, 3])])
        let stations = try XCTUnwrap(world.line(id: line)).stops
        try world.reverseLineStops(line)
        let reversed = try XCTUnwrap(world.line(id: line))
        let run = reversed.runs[0]
        XCTAssertEqual(run.passes.map { reversed.stops[$0] }, [stations[1], stations[3]], "passed in the same order, along the same way")
        XCTAssertEqual(reversed.calls(of: run).map { reversed.stops[$0] }, [stations[0], stations[2], stations[4]])
    }

    /// The express's train is sent out on a timetable of its two calls
    /// only, runs through A, Middle and B without stopping, and gets to
    /// East first; the stopping train calls at each.
    func testTheExpressRunsThroughTheStopsItPasses() throws {
        var (world, local, express, ids, _) = try line()
        var stoppedAt: [TrainID: Set<StationID>] = [local: [], express: []]
        var arrived: [TrainID: Int] = [:]
        var timetable: [StationID] = []
        var last: [TrainID: TrainPosition?] = [:]
        for second in 1...2_400 {
            try world.advance(ticks: 10)
            if timetable.isEmpty, world.train(id: express)!.execution != nil { timetable = world.train(id: express)!.timetable.map(\.station) }
            for id in [local, express] {
                let train = world.train(id: id)!
                defer { last[id] = train.position }
                for station in ids where last[id] == train.position && world.isStopped(train, at: station) && train.execution != nil {
                    stoppedAt[id]!.insert(station)
                }
                if arrived[id] == nil, world.isStopped(train, at: ids[4]), train.execution == nil || stoppedAt[id]!.contains(ids[4]) { arrived[id] = second }
            }
        }
        XCTAssertEqual(timetable, [ids[0], ids[4]], "sent out calling only at West and East")
        XCTAssertTrue(stoppedAt[express]!.isDisjoint(with: ids[1...3]), "it stopped at none it passes: \(stoppedAt[express]!)")
        XCTAssertEqual(stoppedAt[local]!.intersection(ids[1...3]), Set(ids[1...3]), "the stopping train called at each")
        let fast = try XCTUnwrap(arrived[express]), stopping = try XCTUnwrap(arrived[local])
        XCTAssertLessThan(fast, stopping, "the express reached East first")
    }

    /// Under traffic control the stopping train stands aside in Middle's
    /// loop and the express goes by on the straight track.
    func testUnderTrafficControlTheExpressOvertakesAtTheLoop() throws {
        var (world, local, express, ids, _) = try line()
        try world.setTrafficControl(true)
        var arrived: [TrainID: Int] = [:]
        var stoodAt: Set<TrackEdgeID> = []
        for second in 1...2_400 {
            try world.advance(ticks: 10)
            for id in [local, express] where arrived[id] == nil && world.isStopped(world.train(id: id)!, at: ids[4]) && world.train(id: id)!.execution == nil {
                arrived[id] = second
            }
            if arrived[local] == nil, world.isStopped(world.train(id: local)!, at: ids[2]), case .onEdge(let standing, _)? = world.train(id: local)!.position { stoodAt.insert(standing.edge) }
        }
        XCTAssertEqual(stoodAt, [.edge(12)], "in the loop, the straight track left to the express")
        let fast = try XCTUnwrap(arrived[express]), stopping = try XCTUnwrap(arrived[local])
        XCTAssertLessThan(fast, stopping, "the express reached East first")
    }

    // MARK: - The save

    /// Version 87 (decision 605): the line with its express runs, after
    /// fifteen minutes, the express on its way through A; saved byte for byte,
    /// it is the world this build makes.
    func testVersionEightySevenKeepsThePasses() throws {
        var (made, _, express, ids, line) = try line()
        try made.advance(ticks: 9_000)
        XCTAssertEqual(made.train(id: express)?.timetable.map(\.station), [ids[0], ids[4]])
        let url = SavedGameTests.fixtures.appendingPathComponent("v87-passing-runs.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["PASSING_RUN_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 87)
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.line(id: line)?.runs.map(\.passes), [[], [1, 2, 3], [3, 2, 1]])
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 87,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
        try world.advance(ticks: 9_000)
        try made.advance(ticks: 9_000)
        XCTAssertEqual(world, made, "and runs on the same")
    }

    /// Saves from before runs could pass stops (a bought line's, a ring's)
    /// read with every run calling at every stop.
    func testAnEarlierSaveCallsEverywhere() throws {
        for name in ["v66-line-acquisition.json", "v80-ring-runs.json"] {
            let data = try Data(contentsOf: SavedGameTests.fixtures.appendingPathComponent(name))
            let world = try JSONDecoder().decode(SavedGame.self, from: data).world
            let runs = world.lines.flatMap(\.runs)
            XCTAssertFalse(runs.isEmpty, name)
            XCTAssertTrue(runs.allSatisfy(\.passes.isEmpty), name)
            XCTAssertTrue(world.lines.allSatisfy { line in line.runs.allSatisfy { line.calls(of: $0).count == $0.times.count } }, name)
        }
    }
}
