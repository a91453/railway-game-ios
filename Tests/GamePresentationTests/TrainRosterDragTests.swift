import GameCore
@testable import GamePresentation
import XCTest

/// Arranging trains on the roster by dragging (decision 512): where the
/// finger is, how far in time, and what letting go does, which is one
/// edit Undo takes back.
@MainActor
final class TrainRosterDragTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let first = LineID(rawValue: 1)
    private let second = LineID(rawValue: 2)
    private static let track = TestLine(tiles: 7)

    /// Stations A, B and C on one track; lines A–B and B–C, each to run
    /// one train; train One on the first line.
    private func build(flexDispatch: Bool = true) throws -> (GameWorld, TrainID) {
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
        try world.placeTrain(one, at: Self.track.at(1, facingEast: true))
        try world.setTrainMovementRate(one, to: 1024)
        try world.assignTrain(one, to: first)
        world.setFlexDispatch(flexDispatch)
        world.setLineAccounts(true)
        world.setSpeed(.normal)
        return (world, one)
    }

    func testTheRowUnderTheFinger() {
        XCTAssertNil(TrainRosterDrag.row(atY: 10, axisHeight: 24, rowHeight: 44, rows: 3), "on the hours")
        XCTAssertEqual(TrainRosterDrag.row(atY: 24, axisHeight: 24, rowHeight: 44, rows: 3), 0)
        XCTAssertEqual(TrainRosterDrag.row(atY: 24 + 44 * 2 + 43, axisHeight: 24, rowHeight: 44, rows: 3), 2)
        XCTAssertNil(TrainRosterDrag.row(atY: 24 + 44 * 3, axisHeight: 24, rowHeight: 44, rows: 3), "below the last")
        XCTAssertNil(TrainRosterDrag.row(atY: 30, axisHeight: 24, rowHeight: 0, rows: 3))
    }

    /// A sideways drag in minutes, snapped to five.
    func testASidewaysDragSnapsToFiveMinutes() {
        // 90 points an hour: 7.5 points a five minutes.
        XCTAssertEqual(TrainRosterDrag.shift(forWidth: 0, hourWidth: 90), 0)
        XCTAssertEqual(TrainRosterDrag.shift(forWidth: 3, hourWidth: 90), 0)
        XCTAssertEqual(TrainRosterDrag.shift(forWidth: 4, hourWidth: 90), 5 * 60)
        XCTAssertEqual(TrainRosterDrag.shift(forWidth: 90, hourWidth: 90), 3_600)
        XCTAssertEqual(TrainRosterDrag.shift(forWidth: -23, hourWidth: 90), -15 * 60)
        XCTAssertEqual(TrainRosterDrag.shift(forWidth: .infinity, hourWidth: 90), 0)
        XCTAssertEqual(TrainRosterDrag.shift(forWidth: 30, hourWidth: 0), 0)
        XCTAssertGreaterThanOrEqual(TrainRosterDrag.handleSize, 44, "the touch target")
    }

    /// Between trips a line's train goes to the other line in one edit,
    /// which Undo takes back.
    func testDroppingATrainBetweenTripsGivesItToTheOtherLine() throws {
        var (world, one) = try build()
        // On the hour the train has come back and waits for its next trip.
        try world.advance(ticks: 60)
        XCTAssertFalse(try XCTUnwrap(world.trips(of: one).last).isRunning)
        let session = GameSession(world: world)

        XCTAssertEqual(session.rosterLineMove(of: one, to: first)?.verdict, .sameLine)
        XCTAssertEqual(session.rosterLineMove(of: one, to: first)?.drops, false)
        let move = try XCTUnwrap(session.rosterLineMove(of: one, to: second))
        XCTAssertEqual(move.verdict, .moves)
        XCTAssertEqual(move.text(in: .english), "To Second")
        // First is left none of the one it runs.
        XCTAssertEqual(move.notes, ["First is set to run 1 and keeps 0"])
        XCTAssertEqual(session.world, world, "the preview changes nothing")

        session.moveTrain(one, toLine: second)
        XCTAssertEqual(session.world.assignedLine(of: one), second)
        guard case .command(.edit(.moveTrainToLine(one, second)))? = session.commandLog.entries.last?.action else {
            return XCTFail("one command, logged")
        }
        session.undo()
        XCTAssertEqual(session.world.assignedLine(of: one), first)

        // With flexible dispatch it runs empty to the line and on.
        session.moveTrain(one, toLine: second)
        var moved = session.world
        try moved.advance(ticks: 120)
        XCTAssertTrue(moved.trips(of: one).contains { $0.line == second && !$0.isDeadhead })
    }

    /// Out on a trip it waits: a line's train finishes its trip as a
    /// service of its own, which no line can take (`trainServiceActive`).
    func testATrainOnATripIsNotMoved() throws {
        var (world, one) = try build()
        try world.advance(ticks: 3)
        XCTAssertTrue(try XCTUnwrap(world.trips(of: one).last).isRunning)
        let session = GameSession(world: world)
        let move = try XCTUnwrap(session.rosterLineMove(of: one, to: second))
        XCTAssertEqual(move.verdict, .onATrip)
        XCTAssertFalse(move.drops)
        XCTAssertEqual(move.text(in: .traditionalChinese), "正在跑這一趟：跑完再拖")
        // Sent anyway, it is refused whole.
        session.moveTrain(one, toLine: second)
        XCTAssertEqual(session.world.assignedLine(of: one), first)
        XCTAssertFalse(session.canUndo)
    }

    /// The preview says what holds the train once it is moved: without
    /// flexible dispatch it must stop at the line first, and a line
    /// running fewer trains does not use it.
    func testThePreviewSaysWhatHoldsTheTrain() throws {
        var (world, one) = try build(flexDispatch: false)
        try world.advance(ticks: 60)
        let two = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(two, at: Self.track.at(3, facingEast: true))
        try world.setTrainMovementRate(two, to: 1024)
        try world.assignTrain(two, to: second)
        let session = GameSession(world: world, language: .traditionalChinese)
        let move = try XCTUnwrap(session.rosterLineMove(of: one, to: second))
        XCTAssertEqual(move.verdict, .moves)
        XCTAssertEqual(move.notes.first, "Second 只跑 1 列：要加開到 2 列才會用到它")
        XCTAssertTrue(move.notes.contains("它要停到B才會出發"), "\(move.notes)")
    }

    /// A train of its own repeating timetable waiting at its first stop.
    private func ownTimetable() throws -> (GameWorld, TrainID) {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        try Self.track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3)] {
            _ = try Self.track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        let own = try world.purchaseTrain(named: "Own").id
        try world.placeTrain(own, at: Self.track.at(1, facingEast: true))
        try world.setTrainMovementRate(own, to: 1024)
        // Each cycle waits at A from ten to the hour to the hour.
        try world.setTrainTimetable(own, to: [
            ScheduledStop(station: a, arrival: GameTime(minutes: 50), departure: GameTime(minutes: 60)),
            ScheduledStop(station: b, arrival: GameTime(minutes: 70), departure: GameTime(minutes: 71), reverses: true),
            ScheduledStop(station: a, arrival: GameTime(minutes: 80), departure: GameTime(minutes: 81), reverses: true),
        ], repeatingEvery: 3_600)
        try world.startTrainService(own)
        world.setLineAccounts(true)
        world.setSpeed(.normal)
        return (world, own)
    }

    func testAShiftedTimetableStaysAfterSecondZero() throws {
        let (world, own) = try ownTimetable()
        let train = try XCTUnwrap(world.train(id: own))
        let later = try XCTUnwrap(TrainRosterDrag.shiftedTimetable(of: train, by: 15 * 60))
        XCTAssertEqual(later.map(\.arrival.seconds), [65, 85, 95].map { $0 * 60 })
        // An hour earlier than minute 50 is a period on: minute 50 again
        // less the hour, so 50 − 60 + 60.
        let earlier = try XCTUnwrap(TrainRosterDrag.shiftedTimetable(of: train, by: -60 * 60 - 20 * 60))
        XCTAssertEqual(earlier.map(\.arrival.seconds), [30, 50, 60].map { $0 * 60 })
    }

    /// Waiting at its first stop, its timetable moves in one edit: the
    /// next departure later, its stops' times moved together.
    func testDraggingAPlannedBoxMovesItsTimetable() throws {
        let (world, own) = try ownTimetable()
        guard case .waitingAtStop(0, _) = world.train(id: own)?.execution else { return XCTFail("waits at A") }
        let session = GameSession(world: world)
        let roster = TrainRoster(world: world)
        let row = try XCTUnwrap(roster.rows.first { $0.train == own })
        let planned = try XCTUnwrap(row.cells.first { $0.state == .planned })
        XCTAssertNotNil(TrainRosterDrag.plannedCell(of: row, at: planned.start + 60))
        XCTAssertNil(TrainRosterDrag.plannedCell(of: row, at: planned.start - 60))

        XCTAssertEqual(TrainRosterDrag.shift(of: own, by: 0, in: world, roster: roster)?.verdict, .unchanged)
        let shift = try XCTUnwrap(TrainRosterDrag.shift(of: own, by: 15 * 60, in: world, roster: roster))
        XCTAssertEqual(shift.verdict, .moves(departure: 75 * 60))
        XCTAssertEqual(shift.text(in: .english), "+15 min · leaves 01:15")
        XCTAssertNil(shift.clash)

        session.shiftTrainTimetable(own, by: 15 * 60)
        let moved = try XCTUnwrap(session.world.train(id: own))
        XCTAssertEqual(moved.timetable.map(\.departure.seconds), [75, 86, 96].map { $0 * 60 })
        XCTAssertNotNil(moved.execution, "its service runs on")
        guard case .command(.edit(.shiftTrainTimetable(own, by: 900)))? = session.commandLog.entries.last?.action else {
            return XCTFail("one command, logged")
        }
        session.undo()
        XCTAssertEqual(session.world.train(id: own)?.timetable.first?.departure.seconds, 60 * 60)
    }

    /// L3-5 (#1588's review): moved to leave before now, it leaves a cycle
    /// later, and the preview says how long that is.
    func testAMoveBeforeNowSaysHowLongItWaits() throws {
        var (world, own) = try ownTimetable()
        while world.clock.now.seconds < 30 * 60 { try world.advance(ticks: 1) }
        guard case .waitingAtStop(0, _) = world.train(id: own)?.execution else { return XCTFail("waits at A") }
        let roster = TrainRoster(world: world)
        let soon = try XCTUnwrap(TrainRosterDrag.shift(of: own, by: -15 * 60, in: world, roster: roster))
        XCTAssertNil(soon.waits, "45 past the hour is still to come")
        XCTAssertEqual(soon.text(in: .english), "-15 min · leaves 00:45")
        // 15 past the hour has gone: the next cycle's, at 01:15.
        let later = try XCTUnwrap(TrainRosterDrag.shift(of: own, by: -45 * 60, in: world, roster: roster))
        XCTAssertEqual(later.verdict, .moves(departure: 75 * 60))
        XCTAssertEqual(later.waits, 75 * 60 - world.clock.now.seconds)
        let minutes = (75 * 60 - world.clock.now.seconds + 59) / 60
        XCTAssertEqual(later.text(in: .english), "-45 min · leaves 01:15 (in \(minutes) min)")
        XCTAssertEqual(later.text(in: .traditionalChinese), "-45 分 · 01:15 開（\(minutes) 分後）")
        XCTAssertEqual(TrainRosterDrag.Shift.waitText(23 * 3_600 + 15 * 60, in: .traditionalChinese), "23 小時 15 分")
        XCTAssertEqual(TrainRosterDrag.Shift.waitText(2 * 3_600, in: .english), "2 h")
    }

    /// Out on its trip it is not moved: its service would stop halfway.
    func testATimetableMovesOnlyAtItsFirstStop() throws {
        var (world, own) = try ownTimetable()
        while world.train(id: own).map({ if case .travellingToStop = $0.execution { false } else { true } }) ?? false {
            try world.advance(ticks: 1)
        }
        let shift = try XCTUnwrap(TrainRosterDrag.shift(of: own, by: 10 * 60, in: world, roster: TrainRoster(world: world)))
        XCTAssertEqual(shift.verdict, .notAtFirstStop(station: "A"))
        XCTAssertFalse(shift.drops)
        XCTAssertEqual(shift.text(in: .traditionalChinese), "停在A等發車時才能改")
        let session = GameSession(world: world)
        session.shiftTrainTimetable(own, by: 10 * 60)
        XCTAssertEqual(session.world, world, "refused whole")
    }
}

extension TrainRosterDragTests {
    /// Opened from a line's page, the roster shows that line's trains.
    func testTheRosterOfOneLine() throws {
        var (world, one) = try build()
        let two = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(two, at: Self.track.at(3, facingEast: true))
        try world.setTrainMovementRate(two, to: 1024)
        try world.assignTrain(two, to: second)
        try world.advance(ticks: 30)
        let roster = TrainRoster(world: world)
        XCTAssertEqual(roster.rows.map(\.train), [one, two])
        XCTAssertEqual(roster.only(line: second).rows.map(\.train), [two])
        XCTAssertEqual(roster.only(line: nil), roster)
    }
}
