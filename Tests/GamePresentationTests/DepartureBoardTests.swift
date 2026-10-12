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
}
