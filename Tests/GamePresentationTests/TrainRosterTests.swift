import GameCore
@testable import GamePresentation
import XCTest

/// The train roster (ARCHITECTURE decision 223, point 3): a row for each
/// train, a cell for each trip of the trip log.
final class TrainRosterTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let first = LineID(rawValue: 1)
    private let second = LineID(rawValue: 2)
    private static let track = TestLine(tiles: 7)

    /// Two lines, A–B and B–C, one train each, managed with line accounts
    /// (so the trip log is kept and its trips take fares); the people of A
    /// and C go to each other.
    private func build() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        try Self.track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3), ("C", 5)] {
            _ = try Self.track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        try world.createLine(named: "First", stops: [a, b])
        try world.createLine(named: "Second", stops: [b, c])
        for line in [first, second] {
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        }
        let one = try world.purchaseTrain(named: "One").id
        let two = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(one, at: Self.track.at(1, facingEast: true))
        try world.placeTrain(two, at: Self.track.at(3, facingEast: true))
        try world.setTrainMovementRate(one, to: 1024)
        try world.setTrainMovementRate(two, to: 1024)
        // The second line's train first, so the roster's order is the
        // lines' and not the trains'.
        try world.assignTrain(two, to: second)
        try world.assignTrain(one, to: first)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_500))
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 1_500))
        world.setPassengerRoutingMode(.network)
        world.setEconomyMode(.management)
        world.setLineAccounts(true)
        world.setSpeed(.normal)
        return world
    }

    /// A row for each train in the lines' order, a cell for each of
    /// today's trips with its number, its stations and its fare; the row's
    /// takings are its cells' fares.
    func testEachTripIsACellOfItsTrainsRow() throws {
        var world = try build()
        try world.advance(ticks: 600)
        let roster = TrainRoster(world: world)
        XCTAssertEqual(roster.rows.map(\.name), ["One", "Two"])
        XCTAssertEqual(roster.rows.map(\.line), [first, second])
        XCTAssertEqual(roster.rows.map(\.lineCode), roster.rows.map { $0.line.flatMap { LineBadge.codes(for: world.lines)[$0] } })
        let one = roster.rows[0]
        let trips = world.trips(of: one.train)
        XCTAssertEqual(one.cells.count, trips.count)
        XCTAssertEqual(one.cells.map(\.number), Array(1...trips.count))
        XCTAssertEqual(one.cells.map(\.start), trips.map(\.sentOut.seconds))
        XCTAssertEqual(one.cells.first?.routeText, "A → A")
        XCTAssertEqual(one.revenue, trips.reduce(.zero) { $0 + $1.fare })
        XCTAssertGreaterThan(one.revenue, .zero)
        XCTAssertEqual(one.revenue, one.cells.reduce(.zero) { $0 + $1.fare })
        // Finished trips end where they arrived; the last may still run.
        for (cell, trip) in zip(one.cells, trips) where !trip.isRunning {
            XCTAssertEqual(cell.end, trip.arrival?.seconds)
            XCTAssertEqual(cell.state, .onTime)
        }
        if let last = trips.last, last.isRunning {
            XCTAssertEqual(one.cells.last?.state, .running(lateMinutes: 0))
            XCTAssertGreaterThanOrEqual(one.cells.last?.end ?? 0, roster.now)
        }
        XCTAssertTrue(roster.rows.allSatisfy { (1...100).contains($0.utilisation) })
        // A line's train has no planned boxes, and says why in a word.
        XCTAssertTrue(roster.rows.allSatisfy { $0.isDispatchedByLine && !$0.cells.contains { $0.state == .planned } })
        XCTAssertEqual(one.dispatchText(in: .traditionalChinese), "依路線派車")
        XCTAssertEqual(one.dispatchText(in: .english), "Dispatched by line")
        XCTAssertEqual(roster.summaryText(in: .english), "Today · 2 trains · average use \(roster.averageUtilisation!)%")
        XCTAssertEqual(roster.summaryText(in: .traditionalChinese), "今天 · 2 列 · 平均使用率 \(roster.averageUtilisation!)%")
    }

    /// Yesterday's roster is yesterday's trips only, its use measured to
    /// midnight.
    func testYesterdayShowsYesterdaysTrips() throws {
        var world = try build()
        try world.advance(ticks: 1_440 + 120)
        let today = TrainRoster(world: world, day: .today)
        let yesterday = TrainRoster(world: world, day: .yesterday)
        XCTAssertEqual(yesterday.dayStart + GameTime.secondsPerDay, today.dayStart)
        for row in yesterday.rows {
            XCTAssertFalse(row.cells.isEmpty)
            XCTAssertTrue(row.cells.allSatisfy { (yesterday.dayStart..<yesterday.dayEnd).contains($0.start) })
            XCTAssertFalse(row.cells.contains { $0.state == .planned })
        }
        for row in today.rows {
            // Today's, or one that ran into today.
            XCTAssertTrue(row.cells.allSatisfy { $0.start >= today.dayStart || $0.end >= today.dayStart })
        }
        XCTAssertGreaterThan(yesterday.rows[0].cells.count, today.rows[0].cells.count)
    }

    /// A trip sent out before midnight and still running after it is
    /// today's as well: a running train's row is not empty.
    func testATripRunningPastMidnightIsInTodaysRow() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        try Self.track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3)] {
            _ = try Self.track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        let own = try world.purchaseTrain(named: "Own").id
        try world.placeTrain(own, at: Self.track.at(1, facingEast: true))
        try world.setTrainMovementRate(own, to: 1024)
        // Each cycle starts at ten to the hour and is back twenty minutes later.
        try world.setTrainTimetable(own, to: [
            ScheduledStop(station: a, arrival: GameTime(minutes: 50), departure: GameTime(minutes: 51)),
            ScheduledStop(station: b, arrival: GameTime(minutes: 60), departure: GameTime(minutes: 61), reverses: true),
            ScheduledStop(station: a, arrival: GameTime(minutes: 70), departure: GameTime(minutes: 71), reverses: true),
        ], repeatingEvery: 3_600)
        try world.startTrainService(own)
        world.setLineAccounts(true)
        world.setSpeed(.normal)
        while world.clock.now.seconds < GameTime.secondsPerDay + 5 * 60 {
            try world.advance(ticks: 1)
        }
        let trip = try XCTUnwrap(world.trips(of: own).last)
        XCTAssertTrue(trip.isRunning)
        XCTAssertLessThan(trip.sentOut.seconds, GameTime.secondsPerDay, "sent out before midnight")

        let row = try XCTUnwrap(TrainRoster(world: world).rows.first { $0.train == own })
        XCTAssertEqual(row.cells.first?.start, trip.sentOut.seconds)
        XCTAssertEqual(row.cells.first?.state, .running(lateMinutes: 0))
        XCTAssertEqual(row.cells.first?.number, 1)
        XCTAssertGreaterThan(row.utilisation, 0)
        // Yesterday's roster has it too, where it began.
        let yesterday = try XCTUnwrap(TrainRoster(world: world, day: .yesterday).rows.first { $0.train == own })
        XCTAssertEqual(yesterday.cells.last?.start, trip.sentOut.seconds)
    }

    /// Without the trip log (no line accounts) the trains are still listed
    /// today, with no trips.
    func testWithoutTheLogTheTrainsHaveNoCells() throws {
        var world = try build()
        world.setLineAccounts(false)
        try world.advance(ticks: 60)
        let roster = TrainRoster(world: world)
        XCTAssertEqual(roster.rows.count, 2)
        XCTAssertTrue(roster.rows.allSatisfy { $0.cells.isEmpty && $0.utilisation == 0 && $0.revenue == .zero })
        XCTAssertEqual(TrainRoster(world: world, day: .yesterday).rows, [])
    }

    /// A train of its own on a timetable repeating every hour: its trips
    /// still to come today are planned cells, numbered on.
    func testARepeatingTimetablesTripsToComeArePlanned() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        try Self.track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3)] {
            _ = try Self.track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        let own = try world.purchaseTrain(named: "Own").id
        try world.placeTrain(own, at: Self.track.at(1, facingEast: true))
        try world.setTrainMovementRate(own, to: 1024)
        try world.setTrainTimetable(own, to: [
            ScheduledStop(station: a, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: b, arrival: GameTime(minutes: 10), departure: GameTime(minutes: 11), reverses: true),
            ScheduledStop(station: a, arrival: GameTime(minutes: 20), departure: GameTime(minutes: 21), reverses: true),
        ], repeatingEvery: 3_600)
        try world.startTrainService(own)
        world.setLineAccounts(true)
        world.setSpeed(.normal)
        try world.advance(ticks: 22 * 60 + 30)
        let row = try XCTUnwrap(TrainRoster(world: world).rows.first)
        XCTAssertNil(row.line)
        XCTAssertFalse(row.isDispatchedByLine)
        XCTAssertNil(row.dispatchText(in: .english))
        let done = row.cells.filter { $0.state != .planned }
        let planned = row.cells.filter { $0.state == .planned }
        XCTAssertFalse(done.isEmpty)
        // 23:00 is the only cycle still to start today.
        XCTAssertEqual(planned.map(\.start), [23 * 3_600])
        XCTAssertEqual(planned.map(\.end), [23 * 3_600 + 20 * 60])
        // It goes to B, where it turns, as the departure board says.
        XCTAssertEqual(planned.map(\.routeText), ["A → B"])
        XCTAssertEqual(row.cells.compactMap(\.number), Array(1...row.cells.count))
        XCTAssertEqual(planned.first?.detailText(in: .english), "No. \(row.cells.count) · Planned")
        XCTAssertEqual(planned.first?.fare, .zero)
    }

    /// A late trip carries "+N" besides its colour, and the words a screen
    /// reader says.
    func testALateCellSaysHowLate() {
        let late = TrainRoster.Cell(number: 4, from: "Taipei", to: "Hsinchu", start: 3_600, end: 4_800,
                                    fare: Money(210_000), state: .late(minutes: 6), isEmptyRun: false)
        XCTAssertTrue(late.isLate)
        XCTAssertEqual(late.lateText, "+6")
        XCTAssertEqual(late.detailText(in: .english), "No. 4 · $2.1k")
        XCTAssertEqual(late.detailText(in: .traditionalChinese), "第 4 趟 · $2.1k")
        XCTAssertEqual(late.spokenText(in: .english), "Taipei → Hsinchu，01:00–01:20，6 min late，$2.1k")
        let running = TrainRoster.Cell(number: 5, from: "A", to: "B", start: 0, end: 60, fare: .zero, state: .running(lateMinutes: 0), isEmptyRun: false)
        XCTAssertFalse(running.isLate)
        XCTAssertNil(running.lateText)
        let empty = TrainRoster.Cell(number: nil, from: "A", to: "B", start: 0, end: 60, fare: .zero, state: .onTime, isEmptyRun: true)
        XCTAssertEqual(empty.detailText(in: .traditionalChinese), "回送")
    }

    func testShortMoney() {
        XCTAssertEqual(TrainRoster.shortMoney(Money(85_000)), "$850")
        XCTAssertEqual(TrainRoster.shortMoney(Money(540_000)), "$5.4k")
        XCTAssertEqual(TrainRoster.shortMoney(Money(999_960_00)), "$1.0M")
        XCTAssertEqual(TrainRoster.shortMoney(Money(12_345_600)), "$123k")
        XCTAssertEqual(TrainRoster.shortMoney(Money(120_000_000)), "$1.2M")
        XCTAssertEqual(TrainRoster.shortMoney(.zero), "$0")
    }

    /// On an iPhone held sideways, many trains take the short rows.
    func testManyRowsTakeTheShortRows() {
        XCTAssertFalse(TrainRosterLayout.usesCompactRows(rows: 6, height: 300))
        XCTAssertTrue(TrainRosterLayout.usesCompactRows(rows: 7, height: 300))
    }
}
