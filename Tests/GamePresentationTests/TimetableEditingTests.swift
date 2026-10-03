import GameCore
import GamePresentation
import XCTest

/// Stage C2: editing a train's own timetable, one `setTrainTimetable` per
/// control. Times are worked out by hand: a first stop at the next whole
/// minute waiting a minute, three minutes to the next stop.
final class TimetableEditingTests: XCTestCase {
    func testStopsAreAddedAtTheNextMinuteThenThreeMinutesApart() async throws {
        try await MainActor.run {
            let session = GameSession(world: try makeLine())
            session.addStopToSelectedTrainTimetable(alpha)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "T1 now calls at Alpha: arrives 00:01, leaves 00:02."))
            session.addStopToSelectedTrainTimetable(beta)
            XCTAssertEqual(session.selectedTrain?.timetable, [
                ScheduledStop(station: alpha, arrival: GameTime(seconds: 60), departure: GameTime(seconds: 120)),
                ScheduledStop(station: beta, arrival: GameTime(seconds: 300), departure: GameTime(seconds: 360)),
            ])
            XCTAssertNil(session.selectedTrain?.timetablePeriod)

            let rows = session.world.timetableRows(of: TrainID(rawValue: 1), in: .english)
            XCTAssertEqual(rows.map(\.stationName), ["Alpha", "Beta"])
            XCTAssertEqual(rows.map(\.timesText), ["00:01 → 00:02", "00:05 → 00:06"])
            XCTAssertEqual(rows.map(\.detailText), ["waits 1 min", "3 min from Alpha · waits 1 min"])
            XCTAssertEqual(
                session.world.timetableRows(of: TrainID(rawValue: 1), in: .traditionalChinese).map(\.detailText),
                ["停 1 分", "距 Alpha 3 分 · 停 1 分"]
            )
            XCTAssertEqual(session.world.timetableSummary(of: TrainID(rawValue: 1), in: .english), "2 stops from Day 1 · 00:01 · runs once")
            XCTAssertEqual(session.world.timetableSummary(of: TrainID(rawValue: 1), in: .traditionalChinese), "2 站，第 1 日 · 00:01 起 · 只跑一次")
        }
    }

    func testMovingAnArrivalMovesTheRestAndNeverPassesTheStopBefore() async throws {
        try await MainActor.run {
            let session = try makeTimetabled()
            session.moveSelectedTrainArrival(at: 1, by: 60)
            XCTAssertEqual(times(session), [60, 120, 360, 420])
            XCTAssertEqual(session.message?.text, "T1 arrives at Beta at 00:06.")
            XCTAssertTrue(TimetableEditing.canArriveEarlier(1, in: session.selectedTrain!.timetable))
            session.moveSelectedTrainArrival(at: 1, by: -600)
            XCTAssertEqual(times(session), [60, 120, 120, 180], "no earlier than Alpha's departure")
            XCTAssertFalse(TimetableEditing.canArriveEarlier(1, in: session.selectedTrain!.timetable))

            // The first stop's arrival is the start: it moves everything.
            session.moveSelectedTrainArrival(at: 0, by: 120)
            XCTAssertEqual(times(session), [180, 240, 240, 300])
            session.moveSelectedTrainArrival(at: 0, by: -600)
            XCTAssertEqual(times(session), [0, 60, 60, 120], "never before second 0")
        }
    }

    func testMovingADepartureChangesTheWaitAndNeverLeavesBeforeArriving() async throws {
        try await MainActor.run {
            let session = try makeTimetabled()
            session.moveSelectedTrainDeparture(at: 0, by: 60)
            XCTAssertEqual(times(session), [60, 180, 360, 420])
            XCTAssertEqual(session.message?.text, "T1 leaves Alpha at 00:03.")
            session.moveSelectedTrainDeparture(at: 0, by: -600)
            XCTAssertEqual(times(session), [60, 60, 240, 300], "leaves the second it arrives at the earliest")
            XCTAssertFalse(TimetableEditing.canLeaveEarlier(0, in: session.selectedTrain!.timetable))
            XCTAssertTrue(TimetableEditing.canLeaveEarlier(1, in: session.selectedTrain!.timetable))
        }
    }

    func testRepeatingStartsAtTheShortestPeriodAndGrowsToFit() async throws {
        try await MainActor.run {
            let session = try makeTimetabled()
            // From 00:01 to 00:06: five minutes.
            session.setSelectedTrainTimetableRepeats(true)
            XCTAssertEqual(session.selectedTrain?.timetablePeriod, 300)
            XCTAssertEqual(session.message?.text, "T1's timetable repeats every 5 min.")
            session.changeSelectedTrainTimetablePeriod(by: 600)
            XCTAssertEqual(session.selectedTrain?.timetablePeriod, 900)
            session.changeSelectedTrainTimetablePeriod(by: -6_000)
            XCTAssertEqual(session.selectedTrain?.timetablePeriod, 300, "never shorter than the timetable")
            session.moveSelectedTrainDeparture(at: 1, by: 90)
            XCTAssertEqual(session.selectedTrain?.timetablePeriod, 420, "6 min 30 s, rounded up to whole minutes")
            XCTAssertEqual(session.world.timetableSummary(of: TrainID(rawValue: 1), in: .english), "2 stops from Day 1 · 00:01 · repeats every 7 min")
            XCTAssertEqual(session.world.timetablePeriodText(of: TrainID(rawValue: 1), in: .english), "Every 7 min")
            XCTAssertEqual(session.world.timetablePeriodText(of: TrainID(rawValue: 1), in: .traditionalChinese), "每 7 分")
            XCTAssertEqual(session.world.timetableRows(of: TrainID(rawValue: 1), in: .english)[1].timesText, "00:05 → 00:07:30")
            session.setSelectedTrainTimetableRepeats(false)
            XCTAssertNil(session.selectedTrain?.timetablePeriod)
            XCTAssertEqual(session.message?.text, "T1's timetable runs once.")
            XCTAssertNil(session.world.timetablePeriodText(of: TrainID(rawValue: 1), in: .english))
            XCTAssertEqual(TimetableEditing.shortestPeriod(of: [
                ScheduledStop(station: alpha, arrival: GameTime(seconds: 60), departure: GameTime(seconds: 60)),
            ]), 60, "at least a minute")
            XCTAssertNil(TimetableEditing.shortestPeriod(of: []))
        }
    }

    func testTurningRoundRemovingAndClearing() async throws {
        try await MainActor.run {
            let session = try makeTimetabled()
            session.setSelectedTrainTimetableRepeats(true)
            session.toggleSelectedTrainReverse(at: 1)
            XCTAssertEqual(session.selectedTrain?.timetable.map(\.reverses), [false, true])
            XCTAssertEqual(session.message?.text, "T1 turns round at Beta.")
            XCTAssertEqual(session.world.timetableRows(of: TrainID(rawValue: 1), in: .english).map(\.reverses), [false, true])
            session.toggleSelectedTrainReverse(at: 1)
            XCTAssertEqual(session.message?.text, "T1 no longer turns round at Beta.")

            session.removeSelectedTrainStop(at: 0)
            XCTAssertEqual(times(session), [300, 360])
            XCTAssertEqual(session.selectedTrain?.timetablePeriod, 300, "kept: the rest still fits")
            XCTAssertEqual(session.message?.text, "T1 no longer calls at Alpha.")
            session.removeSelectedTrainStop(at: 0)
            XCTAssertEqual(session.selectedTrain?.timetable, [])
            XCTAssertNil(session.selectedTrain?.timetablePeriod, "an empty timetable cannot repeat")

            let cleared = try makeTimetabled()
            cleared.setSelectedTrainTimetableRepeats(true)
            cleared.clearSelectedTrainTimetable()
            XCTAssertEqual(cleared.selectedTrain?.timetable, [])
            XCTAssertNil(cleared.selectedTrain?.timetablePeriod)
            XCTAssertEqual(cleared.message?.text, "Cleared T1's timetable.")
        }
    }

    func testGameCoreRefusesWhileTheServiceRunsAndForALinesTrain() async throws {
        try await MainActor.run {
            let session = try makeTimetabled()
            session.startSelectedTrainService()
            XCTAssertEqual(session.message?.kind, .success)
            let before = session.world
            session.moveSelectedTrainArrival(at: 1, by: 60)
            XCTAssertEqual(session.message?.kind, .failure)
            XCTAssertEqual(session.message?.text, GameError.trainServiceActive(TrainID(rawValue: 1)).playerMessage(in: .english))
            XCTAssertEqual(session.world, before)

            var world = try makeLine()
            let line = try world.createLine(named: "Main", stops: [alpha, beta])
            try world.assignTrain(TrainID(rawValue: 1), to: line.id)
            let onLine = GameSession(world: world)
            onLine.addStopToSelectedTrainTimetable(alpha)
            XCTAssertEqual(onLine.message?.text, GameError.trainOnLine(TrainID(rawValue: 1)).playerMessage(in: .english))
            XCTAssertEqual(onLine.selectedTrain?.timetable, [])
        }
    }

    func testTimesOnALaterDayShowTheDay() {
        let first = GameTime(seconds: 23 * 3_600 + 50 * 60)
        let firstDay = first.seconds / GameTime.secondsPerDay
        let stops = [
            ScheduledStop(station: alpha, arrival: first, departure: GameTime(seconds: first.seconds + 30)),
            ScheduledStop(station: beta, arrival: GameTime(seconds: 24 * 3_600 + 5 * 60), departure: GameTime(seconds: 24 * 3_600 + 6 * 60)),
        ]
        XCTAssertEqual(firstDay, 0)
        XCTAssertEqual(TimetableEditing.shortestPeriod(of: stops), 960, "16 minutes")
        XCTAssertEqual(TimetableEditing.period(600, fitting: stops), 960)
        XCTAssertEqual(TimetableEditing.period(1_200, fitting: stops), 1_200)
        XCTAssertNil(TimetableEditing.period(nil, fitting: stops))
        XCTAssertEqual(TimetableEditing.appending(beta, to: [], start: first), [
            ScheduledStop(station: beta, arrival: first, departure: GameTime(seconds: first.seconds + 60)),
        ])
    }
}

private let alpha = StationID(rawValue: 1)
private let beta = StationID(rawValue: 2)

/// A line of the track network from (0,1) to (4,1) (see `TestLine`),
/// Alpha (1,0) and Beta (3,0) beside it, train T1 standing at Alpha.
private func makeLine() throws -> GameWorld {
    var world = try makeWorld(width: 6, height: 3, balance: 100_000)
    let line = TestLine(tiles: 5, row: 1)
    try line.build(in: &world)
    try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
    try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
    let train = try world.purchaseTrain(named: "T1")
    try world.placeTrain(train.id, at: line.at(1, facingEast: true))
    return world
}

/// ``makeLine()`` with Alpha 00:01–00:02 and Beta 00:05–00:06.
@MainActor
private func makeTimetabled() throws -> GameSession {
    let session = GameSession(world: try makeLine())
    session.addStopToSelectedTrainTimetable(alpha)
    session.addStopToSelectedTrainTimetable(beta)
    return session
}

/// Every arrival and departure in order, in seconds.
@MainActor
private func times(_ session: GameSession) -> [Int64] {
    session.selectedTrain?.timetable.flatMap { [$0.arrival.seconds, $0.departure.seconds] } ?? []
}
