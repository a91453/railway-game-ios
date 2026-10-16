import GameCore
@testable import GamePresentation
import XCTest

/// Decision 178: the station panel's "即將進站" board reads the trains'
/// own timetables, their lateness and the fixed-timetable runs.
final class DepartureBoardTests: XCTestCase {
    private func playedDemo(ticks: Int = 30) throws -> GameWorld {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: ticks)
        return world
    }

    private func central(in world: GameWorld) throws -> StationID {
        try XCTUnwrap(world.stations.first { $0.name == "Central" }).id
    }

    func testTheBoardListsTheTrainsStillAheadAtTheStationSoonestFirstInEachDirection() throws {
        let world = try playedDemo()
        let station = try central(in: world)
        let board = DepartureBoard(world: world, station: station)
        XCTAssertFalse(board.isEmpty, "Central is on Line 1 and Line 2, whose trains are running")
        var ids = Set<String>()
        for direction in board.directions {
            XCTAssertFalse(direction.rows.isEmpty)
            XCTAssertLessThanOrEqual(direction.rows.count, DepartureBoard.rowsPerDirection)
            XCTAssertEqual(direction.rows.map(\.secondsAway), direction.rows.map(\.secondsAway).sorted())
            for row in direction.rows {
                XCTAssertTrue(ids.insert(row.id).inserted)
                XCTAssertLessThanOrEqual(row.secondsAway, DepartureBoard.horizonSeconds)
                XCTAssertGreaterThanOrEqual(row.secondsAway, 0)
                XCTAssertEqual(row.expected.seconds, world.clock.now.seconds + row.secondsAway)
                XCTAssertEqual(row.endsHere, direction.endsHere)
                XCTAssertNotNil(world.line(id: row.line))
            }
        }
        // Trains that end here are listed last.
        let flags = board.directions.map(\.endsHere)
        XCTAssertEqual(flags, flags.sorted { !$0 && $1 })
    }

    func testARowIsAtLeastItsTrainsScheduledArrivalAndAddsItsLateness() throws {
        let world = try playedDemo(ticks: 200)
        let station = try central(in: world)
        let board = DepartureBoard(world: world, station: station)
        for row in board.directions.flatMap(\.rows) where !row.passes && !row.isBoarding {
            let train = try XCTUnwrap(row.train.flatMap { world.train(id: $0) })
            let late = max(0, world.lateness(of: train.id) ?? 0)
            let scheduled = train.timetable.filter { $0.station == station }.map(\.arrival.seconds)
            let shifts = (0...60).map { Int64($0) * (train.timetablePeriod ?? 0) }
            let candidates = scheduled.flatMap { time in shifts.map { time + $0 + late } }
            XCTAssertTrue(candidates.contains(row.expected.seconds) || row.secondsAway == 0, "row \(row.id) is a scheduled call plus the lateness")
            XCTAssertEqual(row.lateMinutes, Int(late / 60))
        }
    }

    func testATrainAtThePlatformIsBoardingAndNothingBehindTheTrainIsListed() throws {
        var world = DemoWorld.make(in: .english)
        let station = try central(in: world)
        var sawBoarding = false
        for _ in 0..<400 {
            try world.advance(ticks: 1)
            let rows = DepartureBoard(world: world, station: station).directions.flatMap(\.rows)
            for row in rows {
                guard let train = row.train.flatMap({ world.train(id: $0) }), let execution = train.execution else { continue }
                if row.isBoarding {
                    sawBoarding = true
                    XCTAssertEqual(row.secondsAway, 0)
                    guard case .waitingAtStop(let at, _) = execution else { return XCTFail("boarding means waiting at a stop") }
                    XCTAssertEqual(train.timetable[at].station, station)
                }
            }
            if sawBoarding { break }
        }
        XCTAssertTrue(sawBoarding, "a train calls at Central within 400 ticks")
    }

    func testAStationOffTheLinesHasAnEmptyBoard() throws {
        let world = try playedDemo()
        XCTAssertTrue(DepartureBoard(world: world, station: StationID(rawValue: 9_999)).isEmpty)
    }

    func testTheWordingOfTheTimeAndTheLatenessBadge() {
        func row(secondsAway: Int64, boarding: Bool = false, late: Int = 0) -> DepartureBoard.Row {
            DepartureBoard.Row(
                id: "x", train: nil, trainName: "", line: LineID(rawValue: 1), lineName: "L", color: nil,
                destination: StationID(rawValue: 2), endsHere: false, passes: false, isBoarding: boarding,
                expected: GameTime(seconds: secondsAway), secondsAway: secondsAway, lateMinutes: late)
        }
        XCTAssertEqual(row(secondsAway: 0, boarding: true).awayText(in: .traditionalChinese), "進站中")
        XCTAssertEqual(row(secondsAway: 59).awayText(in: .traditionalChinese), "即將進站")
        XCTAssertEqual(row(secondsAway: 60).awayText(in: .traditionalChinese), "1 分")
        XCTAssertEqual(row(secondsAway: 725).awayText(in: .english), "12 min")
        XCTAssertNil(row(secondsAway: 300, late: 0).lateText(in: .traditionalChinese))
        XCTAssertEqual(row(secondsAway: 300, late: 3).lateText(in: .traditionalChinese), "慢 3 分")
        XCTAssertEqual(row(secondsAway: 300, late: 3).lateText(in: .english), "3 min late")
    }

    func testARunNotYetSentOutIsListedAtItsTimetablesTime() throws {
        var world = DemoWorld.make(in: .english)
        let line = try XCTUnwrap(world.lines.first)
        for id in line.trains { try? world.stopTrainService(id) }
        let now = world.clock.now.seconds
        let start = (now % GameTime.secondsPerDay) + 20 * 60
        let times = (0..<line.stops.count).map { LineRunTime(arrival: start + Int64($0) * 300, departure: start + Int64($0) * 300 + 30) }
        try world.setLineRuns(line.id, to: [LineRun(from: 0, to: line.stops.count - 1, times: times)])
        let last = line.stops[line.stops.count - 1]
        let board = DepartureBoard(world: world, station: last)
        let row = try XCTUnwrap(board.directions.flatMap(\.rows).first { $0.train == nil })
        XCTAssertTrue(row.endsHere, "the run ends at its last stop")
        XCTAssertEqual(row.secondsAway, 20 * 60 + Int64(line.stops.count - 1) * 300)
        XCTAssertEqual(row.line, line.id)
    }

    /// A run no train took out within the half hour it may still be sent is
    /// dropped for the day: no station down the line lists it as coming.
    func testARunNeverSentOutIsNotListedDownTheLine() throws {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 120)
        let line = try XCTUnwrap(world.lines.first)
        for id in line.trains { try? world.stopTrainService(id) }
        let now = world.clock.now.seconds
        let start = (now % GameTime.secondsPerDay) - 40 * 60
        let times = (0..<line.stops.count).map { LineRunTime(arrival: start + Int64($0) * 1_800, departure: start + Int64($0) * 1_800 + 30) }
        try world.setLineRuns(line.id, to: [LineRun(from: 0, to: line.stops.count - 1, times: times)])
        let last = line.stops[line.stops.count - 1]
        XCTAssertGreaterThan(start + Int64(line.stops.count - 1) * 1_800, now % GameTime.secondsPerDay, "the last stop is still ahead")
        let board = DepartureBoard(world: world, station: last)
        XCTAssertNil(board.directions.flatMap(\.rows).first { $0.train == nil })
    }

    /// Decision 223: the status capsule in words, the time struck through
    /// when late, and "前車誤點" for a late train close behind a late one.
    func testTheStatusAndTheStruckThroughTime() {
        func row(_ id: String, train: Int?, away: Int64, late: Int = 0, scheduled: Int64? = nil, boarding: Bool = false, passes: Bool = false) -> DepartureBoard.Row {
            DepartureBoard.Row(
                id: id, train: train.map { TrainID(rawValue: $0) }, trainName: "", line: LineID(rawValue: 1), lineName: "L", color: nil,
                destination: StationID(rawValue: 2), endsHere: false, passes: passes, isBoarding: boarding,
                expected: GameTime(seconds: away), secondsAway: away, lateMinutes: late,
                scheduled: scheduled.map { GameTime(seconds: $0) })
        }
        XCTAssertEqual(row("a", train: 1, away: 0, boarding: true).status, .boarding)
        XCTAssertEqual(row("a", train: 1, away: 60, passes: true).status, .passes)
        XCTAssertEqual(row("a", train: 1, away: 60).status.text(in: .traditionalChinese), "準點")
        let late = row("a", train: 1, away: 9 * 3600 + 12 * 60, late: 6, scheduled: 9 * 3600 + 6 * 60)
        XCTAssertEqual(late.status.text(in: .traditionalChinese), "誤點 6 分")
        XCTAssertEqual(late.replacedTimeText, "09:06")
        XCTAssertNil(row("a", train: 1, away: 600, scheduled: 600).replacedTimeText, "an on-time train strikes nothing")

        let marked = DepartureBoard.markingFollowers([
            late,
            row("b", train: 2, away: 9 * 3600 + 13 * 60, late: 4, scheduled: 9 * 3600 + 9 * 60),
            row("c", train: 3, away: 9 * 3600 + 40 * 60, late: 2),
            row("d", train: 4, away: 9 * 3600 + 41 * 60),
        ])
        XCTAssertEqual(marked.map(\.followsLateTrain), [false, true, false, false])
        XCTAssertEqual(marked[1].status.text(in: .traditionalChinese), "前車誤點 4 分", "its own lateness too")
        XCTAssertEqual(marked[1].status.text(in: .english), "4 min late, train ahead")
        XCTAssertEqual(marked[1].status, .lateBehind(minutes: 4))
        XCTAssertEqual(marked[2].status, .late(minutes: 2), "27 minutes behind a late train is late on its own")

        // A late train that runs past without calling is no train ahead at
        // the platform: the one behind it is late on its own, or behind
        // the late train that called before it.
        let passing = DepartureBoard.markingFollowers([
            row("p", train: 5, away: 9 * 3600, late: 6, passes: true),
            row("q", train: 6, away: 9 * 3600 + 3 * 60, late: 3),
        ])
        XCTAssertEqual(passing.map(\.followsLateTrain), [false, false])
        let between = DepartureBoard.markingFollowers([
            row("x", train: 7, away: 9 * 3600, late: 5),
            row("p", train: 5, away: 9 * 3600 + 2 * 60, late: 6, passes: true),
            row("y", train: 8, away: 9 * 3600 + 4 * 60, late: 3),
        ])
        XCTAssertEqual(between.map(\.followsLateTrain), [false, false, true])
    }

    func testATrainsRowKeepsItsTimetablesTimeBeforeTheLateness() throws {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 200)
        let station = try XCTUnwrap(world.stations.first { $0.name == "Central" }).id
        for row in DepartureBoard(world: world, station: station).directions.flatMap(\.rows) where !row.isBoarding {
            let scheduled = try XCTUnwrap(row.scheduled)
            XCTAssertLessThanOrEqual(scheduled.seconds, row.expected.seconds)
        }
    }
}
