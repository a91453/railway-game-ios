import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 256: fares float over the station they were
/// taken at, a goal met is checked off with a tune, a town that grew a
/// step is ringed. Read from the world before and after a step; never
/// changes it.
@MainActor
final class ActionFeedbackTests: XCTestCase {
    private func fare(_ station: Int, _ train: Int, _ dollars: Int64) -> StationFare {
        StationFare(
            station: StationID(rawValue: station), location: PlanPoint(x: Int64(station) * 1_000, y: 0),
            train: TrainID(rawValue: train), amount: Money(dollars * 100)
        )
    }

    func testFaresAtAStationWithinASecondMakeOneFloat() {
        var board = FareFloatBoard()
        board.add([fare(1, 1, 12), fare(2, 1, 5)], at: 10)
        board.add([fare(1, 2, 8)], at: 10.5)
        XCTAssertEqual(board.floats.map(\.text), ["+$20", "+$5"], "the second train's fares join the first's float")
        XCTAssertEqual(board.floats.first?.trains, [TrainID(rawValue: 1), TrainID(rawValue: 2)])
        board.add([fare(1, 1, 3)], at: 11.1)
        XCTAssertEqual(board.floats.map(\.text), ["+$20", "+$5", "+$3"], "a second later, a float of its own")
        board.expire(at: 11.25)
        XCTAssertEqual(board.floats.map(\.text), ["+$3"], "the first two are gone after 1.2 s")
        board.expire(at: 12.3)
        XCTAssertTrue(board.floats.isEmpty)
    }

    func testTheBoardKeepsTheNewestFloatsUpToItsMost() {
        var board = FareFloatBoard()
        board.add((1...20).map { fare($0, 1, Int64($0)) }, at: 0)
        XCTAssertEqual(board.floats.count, FareFloatBoard.maximum)
        XCTAssertEqual(board.floats.first?.station, StationID(rawValue: 20 - FareFloatBoard.maximum + 1), "the oldest go first")
        XCTAssertEqual(Set(board.floats.map(\.id)).count, board.floats.count)
    }

    func testAFloatTakesItsMotionRulesAndHoldsBetweenThem() {
        // Decision 253's pop in and cardOut out, within the design's 1.2 s.
        XCTAssertEqual(FareFloatBoard.hold, FareFloatBoard.lifetime - MotionRule.pop.seconds - MotionRule.cardOut.seconds)
        XCTAssertGreaterThan(FareFloatBoard.hold, 0.5)
        var board = FareFloatBoard()
        board.add([fare(1, 1, 13_400)], at: 0)
        XCTAssertEqual(board.floats.first?.text, "+$13k")
    }

    func testAtHighSpeedOnlyTheFollowedTrainAndTheMiddleStationsFloat() {
        var board = FareFloatBoard()
        board.add((1...6).map { fare($0, $0, 10) }, at: 0)
        let middle = { (point: PlanPoint) in Double(abs(point.x - 4_000)) }
        XCTAssertEqual(board.shown(fast: false, followed: nil, distance: middle).count, 6, "slower, every float")
        XCTAssertEqual(
            board.shown(fast: true, followed: nil, distance: middle).map(\.station.rawValue), [3, 4, 5],
            "the three nearest the middle, in the board's order"
        )
        XCTAssertEqual(
            board.shown(fast: true, followed: TrainID(rawValue: 1), distance: middle).map(\.station.rawValue), [1, 3, 4, 5],
            "and the followed train's"
        )
        XCTAssertFalse(FareFloatBoard.isFast(.x60))
        XCTAssertTrue(FareFloatBoard.isFast(.normal))
        XCTAssertTrue(FareFloatBoard.isFast(.fast))
    }

    /// A line running in a session: each step's fares are its trips' new
    /// fares, at the station each last called at, and together they are
    /// what the trips took.
    func testASessionFloatsTheFaresItsTripsTake() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        let line = TestLine(tiles: 7, row: 1)
        try line.build(in: &world)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try line.buildStation(named: name, beside: x, at: 0, in: &world)
        }
        let main = LineID(rawValue: 1)
        try world.createLine(named: "Main", stops: [StationID(rawValue: 1), StationID(rawValue: 2), StationID(rawValue: 3)])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)
        world.setEconomyMode(.management)
        // The trip log, which the fares are read from, keeps with the
        // lines' accounts (as in the app's new games).
        world.setLineAccounts(true)
        try world.setStationDemand(StationID(rawValue: 1), to: StationDemand(kind: .residential, dailyTrips: 200_000))
        try world.setStationDemand(StationID(rawValue: 3), to: StationDemand(kind: .office, dailyTrips: 200_000))

        let session = GameSession(world: world)
        XCTAssertNil(session.farePulse)
        var floated = Money.zero
        var serial = 0
        var stations: Set<StationID> = []
        for _ in 0..<90 {
            session.advance(realElapsed: GameSession.tickInterval)
            guard let pulse = session.farePulse, pulse.serial != serial else { continue }
            serial = pulse.serial
            for fare in pulse.fares {
                XCTAssertEqual(fare.train, train.id)
                XCTAssertEqual(fare.location, session.world.station(id: fare.station)?.point)
                stations.insert(fare.station)
                floated = floated + fare.amount
            }
        }
        let taken = session.world.tripLog.reduce(Money.zero) { $0 + $1.fare }
        XCTAssertGreaterThan(taken, .zero, "the test needs fares")
        // Under a dollar a step is left out.
        XCTAssertLessThanOrEqual(floated, taken)
        XCTAssertGreaterThan(floated.amount, taken.amount * 9 / 10)
        XCTAssertFalse(stations.isEmpty)
    }

    func testAGoalMetPulsesWithItsTitleAndTheTune() throws {
        var world = try GameWorld(
            bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 1_000_000), clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        try world.startScenario(Scenario(id: "custom.1", goals: [.equity(Money(1))], goldDays: 1, silverDays: 5, deadlineDays: 9))
        let session = GameSession(world: world, language: .english)
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        for _ in 0..<1_441 where session.goalPulse == nil {
            session.advance(realElapsed: GameSession.tickInterval)
        }
        let pulse = try XCTUnwrap(session.goalPulse, "met at the first midnight")
        let title = try XCTUnwrap(session.world.goalProgress(in: .english).first?.title)
        XCTAssertEqual(pulse, GoalPulse(titles: [title], serial: 1))
        XCTAssertEqual(pulse.text(in: .english), "Goal met: \(title)")
        XCTAssertEqual(heard.filter { $0 == .goalMet }.count, 1)
        XCTAssertEqual(SoundCue.goalMet.category, .effects, "the tune follows the effects' volume")
        XCTAssertEqual(SoundCue.goalMet.resource.name, "goal-met")

        // Met already: the next step pulses nothing.
        session.advance(realElapsed: GameSession.tickInterval)
        XCTAssertEqual(session.goalPulse?.serial, 1)
    }

    func testSeveralGoalsSayHowMany() {
        let pulse = GoalPulse(titles: ["A", "B"], serial: 1)
        XCTAssertEqual(pulse.text(in: .english), "2 goals met")
        XCTAssertEqual(pulse.text(in: .traditionalChinese), "達成 2 個目標")
        XCTAssertEqual(GoalPulse(titles: ["每日運量"], serial: 1).text(in: .traditionalChinese), "目標達成：每日運量")
    }

    func testATownGrowsAStepForEachQuarterOfItsStart() {
        XCTAssertEqual(TownGrowthPulse.step(dailyTrips: 1_000, base: 1_000), 0)
        XCTAssertEqual(TownGrowthPulse.step(dailyTrips: 1_249, base: 1_000), 0)
        XCTAssertEqual(TownGrowthPulse.step(dailyTrips: 1_250, base: 1_000), 1)
        XCTAssertEqual(TownGrowthPulse.step(dailyTrips: 4_000, base: 1_000), 12, "four times its start")
        XCTAssertEqual(TownGrowthPulse.step(dailyTrips: 900, base: 1_000), 0, "shrunk below its start")
        XCTAssertEqual(TownGrowthPulse.step(dailyTrips: 10, base: 0), 0)
    }

    func testTheTownsThatGrewAStepAreRingedTheMostGrownFirst() {
        func town(_ station: Int, _ before: Int64, _ after: Int64, _ growth: Int64) -> TownGrowthPulse.Town {
            TownGrowthPulse.Town(station: StationID(rawValue: station), base: 1_000, before: before, after: after, growth: growth)
        }
        let towns = [
            town(1, 1_200, 1_215, 15), // not yet a step
            town(2, 1_240, 1_255, 12),
            town(3, 1_490, 1_505, 10),
            town(4, 1_245, 1_260, 12),
            town(5, 1_740, 1_760, 11),
            town(6, 1_300, 1_280, -15), // shrank
        ]
        XCTAssertEqual(TownGrowthPulse.grown(towns).map(\.rawValue), [2, 4, 5], "the most grown three, then by station")
        XCTAssertEqual(TownGrowthPulse.maximum, 3)
        XCTAssertTrue(TownGrowthPulse.grown([town(1, 1_250, 1_260, 10)]).isEmpty, "already that step")
    }

    func testAWorldsTownsAreReadFromItsGrowth() throws {
        var world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000, speed: .normal)
        world.setEconomyMode(.management)
        world.setTownGrowth(true)
        for index in 0..<3 {
            let station = try world.buildStation(named: "S\(index)", at: PlanPoint(x: 1_000 + Int64(index) * 2_000, y: 2_000)).id
            try world.setStationDemand(station, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        }
        XCTAssertTrue(TownGrowthPulse.grown(from: world, to: world).isEmpty, "no growth seen yet")
        let before = world
        try world.advance(ticks: 1_441)
        XCTAssertEqual(world.townGrowth?.places.map(\.base), [1_000, 1_000, 1_000], "growth saw each town")
        XCTAssertTrue(TownGrowthPulse.grown(from: before, to: world).isEmpty, "unserved towns grow no step")
    }
}
