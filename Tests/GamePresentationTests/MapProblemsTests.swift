import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 210: problems seen on the map at a middle zoom
/// too, held to a number: which stations get a waiting count, which
/// waiting trains a ring and a tag, and why a crowded station's
/// passengers wait.
final class MapProblemsTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)
    private static let main = LineID(rawValue: 1)

    // MARK: - Zoom

    func testTheLevelsFollowTheZoom() {
        XCTAssertEqual(MapProblems.level(referenceSize: 0.1), .hidden, "the whole island")
        XCTAssertEqual(MapProblems.level(referenceSize: MapProblems.mediumFrom - 0.01), .hidden)
        XCTAssertEqual(MapProblems.level(referenceSize: MapProblems.mediumFrom), .medium)
        XCTAssertEqual(MapProblems.level(referenceSize: MapScale.overviewBelow - 0.01), .medium)
        XCTAssertEqual(MapProblems.level(referenceSize: MapScale.overviewBelow), .full, "close up, as the station names")
        XCTAssertEqual(MapProblems.pillLimit(.hidden), 0)
        XCTAssertLessThan(MapProblems.pillLimit(.medium), MapProblems.pillLimit(.full))
    }

    // MARK: - Stations

    func testCrowdingFollowsTheBubblesThresholds() {
        let capacity = StationPassengers.capacity
        XCTAssertEqual(MapProblems.Crowding(waiting: 0), .normal)
        XCTAssertEqual(MapProblems.Crowding(waiting: capacity / 2 - 1), .normal)
        XCTAssertEqual(MapProblems.Crowding(waiting: capacity / 2), .crowded)
        XCTAssertEqual(MapProblems.Crowding(waiting: capacity - 1), .crowded)
        XCTAssertEqual(MapProblems.Crowding(waiting: capacity), .full)
        XCTAssertEqual(MapProblems.fill(waiting: capacity / 2), 0.5)
        XCTAssertEqual(MapProblems.fill(waiting: capacity * 2), 1, "a full ring goes round once")
        XCTAssertEqual(MapProblems.fill(waiting: -3), 0)
    }

    func testStationsAreOrderedFullThenCrowdedThenByCount() {
        let capacity = StationPassengers.capacity
        let counts: [StationID: Int64] = [
            StationID(rawValue: 1): 20,
            StationID(rawValue: 2): capacity / 2,
            StationID(rawValue: 3): 0,
            StationID(rawValue: 4): capacity,
            StationID(rawValue: 5): 300,
            StationID(rawValue: 6): 20,
        ]
        XCTAssertEqual(MapProblems.stationOrder(counts).map(\.station.rawValue), [4, 2, 5, 1, 6], "none waiting: no pill")
    }

    func testPlacementLeavesOutOverlapsAndStopsAtTheLimit() {
        var placement = MapProblems.Placement(limit: 2, gap: 2)
        XCTAssertTrue(placement.place(.init(x: 0, y: 0, width: 40, height: 14)))
        XCTAssertFalse(placement.place(.init(x: 30, y: 5, width: 40, height: 14)), "covers the first")
        XCTAssertFalse(placement.place(.init(x: 41, y: 0, width: 40, height: 14)), "closer than the gap")
        XCTAssertTrue(placement.place(.init(x: 43, y: 0, width: 40, height: 14)))
        XCTAssertTrue(placement.isFull)
        XCTAssertFalse(placement.place(.init(x: 200, y: 200, width: 10, height: 10)), "past the limit")
        XCTAssertEqual(placement.placed.count, 2)
    }

    // MARK: - Trains

    private func wait(_ train: Int64, deadlocked: Bool = false) -> TrafficOverlay.Wait {
        let at = WorldCoordinate(x: train * 1_000, y: 0)
        return .init(
            train: TrainID(rawValue: Int(train)), holder: TrainID(rawValue: 99), holderName: "Express", reason: deadlocked ? .deadlock : .route,
            isDeadlocked: deadlocked, contested: .init(), from: at, to: at, heading: PlanVector(dx: 1, dy: 0)
        )
    }

    func testTheDeadlockedComeFirstAndTheRingsAreHeldToANumber() {
        let waits = (1...20).map { wait(Int64($0), deadlocked: $0 == 17) }
        let shown = MapProblems.shownWaits(waits) { $0.train.rawValue != 2 }
        XCTAssertEqual(shown.count, MapProblems.waitMarkLimit)
        XCTAssertEqual(shown.map(\.train.rawValue), [17, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], "one out of view")
        XCTAssertLessThanOrEqual(MapProblems.waitTagLimit, MapProblems.waitMarkLimit)
    }

    func testATagSaysWhyAndForWhom() {
        let cases: [(TrafficOverlay.WaitReason, String, String)] = [
            (.meet, "Meet · Express", "等交會 · Express"),
            (.standAside, "Stand aside · Express", "待避 · Express"),
            (.following, "Following · Express", "跟車 · Express"),
            (.route, "Route · Express", "等進路 · Express"),
            (.deadlock, "Deadlock · Express", "死結 · Express"),
        ]
        for (reason, english, chinese) in cases {
            XCTAssertEqual(reason.tag(holder: "Express", in: .english), english)
            XCTAssertEqual(reason.tag(holder: "Express", in: .traditionalChinese), chinese)
        }
        XCTAssertEqual(TrafficOverlay.WaitReason.route.tag(holder: "Tze-Chiang Limited Express 101", in: .english), "Route · Tze-Chian…", "ten characters with the ellipsis")
        XCTAssertEqual(TrafficOverlay.WaitReason.meet.tag(holder: "", in: .traditionalChinese), "等交會")
    }

    func testTheRingsPulseOnlyWhileTheGameRuns() throws {
        XCTAssertNil(MapProblems.pulse(at: 0.4, reduceMotion: true, running: true))
        XCTAssertNil(MapProblems.pulse(at: 0.4, reduceMotion: false, running: false))
        XCTAssertEqual(try XCTUnwrap(MapProblems.pulse(at: 0.4, reduceMotion: false, running: true)), 0.25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(MapProblems.pulse(at: MapProblems.pulseBeat + 0.8, reduceMotion: false, running: true)), 0.5, accuracy: 1e-9)
    }

    // MARK: - Why they wait

    private func crowdedWorld() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        try world.createLine(named: "Main", stops: [Self.alpha, Self.beta])
        try world.setStationDemand(Self.alpha, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        try world.setStationDemand(Self.beta, to: StationDemand(kind: .office, dailyTrips: 1_000))
        world.setSpeed(.normal)
        try world.advance(ticks: 480)
        return world
    }

    func testAStationWithoutAnyoneWaitingHasNoReason() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000)
        try world.buildStation(named: "Alpha", at: TestLine.centre(1, 0))
        XCTAssertNil(world.stationWaitReason(of: Self.alpha))
        XCTAssertNil(world.stationWaitReason(of: StationID(rawValue: 42)))
    }

    func testTheReasonIsTheLineMostWaitForWithoutATrain() throws {
        let world = try crowdedWorld()
        let reason = try XCTUnwrap(world.stationWaitReason(of: Self.alpha))
        let waiting = world.waitingPassengers(at: Self.alpha)
        let first = try XCTUnwrap(waiting.map(\.since).min())
        XCTAssertEqual(reason.kind, .noTrains)
        XCTAssertEqual(reason.line, Self.main)
        XCTAssertEqual(reason.terminus, "Beta", "outbound, toward the last stop")
        XCTAssertEqual(reason.waiting, waiting.reduce(Int64(0)) { $0 + $1.count })
        XCTAssertEqual(reason.longestMinutes, (world.clock.now.seconds - first.seconds) / 60)
        XCTAssertGreaterThan(reason.longestMinutes, 0)
        XCTAssertEqual(reason.text(in: .english), "No trains on Main")
        XCTAssertEqual(reason.text(in: .traditionalChinese), "Main沒有列車")
    }

    func testWithATrainTheReasonSaysWhereToAndHowLong() throws {
        var world = try crowdedWorld()
        let train = try world.purchaseTrain(named: "T1")
        try world.assignTrain(train.id, to: Self.main, pattern: nil)
        let reason = try XCTUnwrap(world.stationWaitReason(of: Self.alpha))
        XCTAssertEqual(reason.kind, .waitingFor)
        let minutes = reason.longestMinutes
        XCTAssertEqual(reason.text(in: .english), "Most for Main to Beta · up to \(minutes) min")
        XCTAssertEqual(reason.text(in: .traditionalChinese), "多數等Main往Beta · 最久 \(minutes) 分")
        let fresh = StationWaitReason(kind: .waitingFor, line: Self.main, lineName: "紅線", terminus: nil, waiting: 3, longestMinutes: 0)
        XCTAssertEqual(fresh.text(in: .traditionalChinese), "多數等紅線", "no time under a minute, no end without one")
    }
}
