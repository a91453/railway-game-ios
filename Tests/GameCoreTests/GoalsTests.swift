import Foundation
@testable import GameCore
import XCTest

/// Decision 86: scenarios' goals, judged every managed midnight after the
/// year's closing; their ratings and failures; the era's train types; and
/// the fast-forward speed.
final class GoalsTests: XCTestCase {
    /// Five stations in a row, 1 km apart, in a managed world.
    private func makeStations(managed: Bool = true) throws -> (GameWorld, [StationID]) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 400_000, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        if managed { world.setEconomyMode(.management) }
        let ids = try (0..<5).map { index in
            try world.buildStation(named: "S\(index + 1)", at: PlanPoint(x: 1_024 + Int64(index) * 64_000, y: 4_096)).id
        }
        return (world, ids)
    }

    private func point(_ index: Int64) -> PlanPoint {
        PlanPoint(x: 1_024 + index * 64_000, y: 4_096)
    }

    private func scenario(_ goals: [Goal], gold: Int64 = 2, silver: Int64 = 4, deadline: Int64 = 6, insolvency: Int64? = nil,
                          types: [TrainType]? = nil, events: [ScenarioEvent] = []) -> Scenario {
        Scenario(id: "test", goals: goals, goldDays: gold, silverDays: silver, deadlineDays: deadline, insolvencyDays: insolvency,
                 trainTypes: types, events: events)
    }

    func testAScenarioNeedsAManagedCompanyAndSoundRules() throws {
        var (free, _) = try makeStations(managed: false)
        expect(.invalidScenario) { try free.startScenario(scenario([.dailyRiders(1)])) }
        var (world, _) = try makeStations()
        let before = world
        for bad in [
            scenario([]),
            scenario([.dailyRiders(1)], gold: 5, silver: 4),
            scenario([.dailyRiders(1)], gold: 0),
            scenario([.dailyRiders(0)]),
            scenario([.annualNetProfit(.zero)]),
            scenario([.connect(points: [point(0)], radius: 1_000)]),
            scenario([.connect(points: [point(0), PlanPoint(x: 500_000, y: 0)], radius: 1_000)]),
            scenario([.dailyRiders(1)], types: []),
            scenario([.dailyRiders(1)], deadline: Scenario.maximumDays + 1),
        ] {
            expect(.invalidScenario) { try world.startScenario(bad) }
        }
        XCTAssertEqual(world, before)
        try world.startScenario(scenario([.dailyRiders(1)]))
        XCTAssertEqual(world.scenario?.startDay, 0)
        XCTAssertEqual(world.scenario?.achieved, [nil])
    }

    func testPlacesAreConnectedByLinesThatShareAStationOrATransferGroup() throws {
        var (world, s) = try makeStations()
        let goal = [point(0), point(4)]
        XCTAssertNil(world.connectedStations(near: goal, radius: 2_048), "no line")
        try world.createLine(named: "West", stops: [s[0], s[1], s[2]])
        try world.createLine(named: "East", stops: [s[3], s[4]])
        XCTAssertNil(world.connectedStations(near: goal, radius: 2_048), "two networks")
        XCTAssertFalse(world.isMet(.connect(points: goal, radius: 2_048)))
        try world.linkTransfer(s[2], s[3])
        XCTAssertEqual(world.connectedStations(near: goal, radius: 2_048), [s[0], s[4]], "joined by the group")
        try world.unlinkTransfer(s[3])
        try world.createLine(named: "Link", stops: [s[2], s[3]])
        XCTAssertEqual(world.connectedStations(near: goal, radius: 2_048), [s[0], s[4]], "joined by a shared station")
        // A station farther than the radius does not count.
        XCTAssertNil(world.connectedStations(near: [point(0), PlanPoint(x: 1_024 + 4 * 64_000 + 3_000, y: 4_096)], radius: 2_048))
    }

    func testGoalsAreJudgedAtMidnightAndCompleteWithTheirRating() throws {
        var (world, s) = try makeStations()
        try world.startScenario(scenario([.connect(points: [point(0), point(1)], radius: 2_048), .equity(Money(1))]))
        // Before midnight nothing is judged, though both are met.
        try world.createLine(named: "Main", stops: [s[0], s[1]])
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.scenario?.achieved, [nil, nil])
        // The midnight that ends day 0 is settled at the start of the step from it.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.scenario?.achieved, [0, 0])
        XCTAssertEqual(world.scenario?.outcome, .completed(day: 0, rating: .gold))
        XCTAssertNil(world.scenarioProblem())
        // An ended scenario stays as it ended.
        try world.removeLine(LineID(rawValue: 1))
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.scenario?.outcome, .completed(day: 0, rating: .gold))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testTheRatingFollowsTheDaysItTookAndTheDeadlineLosesIt() throws {
        let rules = scenario([.population(1)], gold: 2, silver: 4, deadline: 6)
        XCTAssertEqual(rules.rating(afterDays: 1), .gold)
        XCTAssertEqual(rules.rating(afterDays: 2), .gold)
        XCTAssertEqual(rules.rating(afterDays: 3), .silver)
        XCTAssertEqual(rules.rating(afterDays: 6), .bronze)
        XCTAssertNil(rules.rating(afterDays: 7))

        // Nobody lives on this map: the population goal is never met, and
        // the sixth midnight loses it.
        var (world, _) = try makeStations()
        try world.startScenario(rules)
        try world.advance(ticks: 5 * 1_440 + 1)
        XCTAssertNil(world.scenario?.outcome)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.scenario?.outcome, .failed(day: 5, reason: .deadline))
        XCTAssertNil(world.scenarioProblem())

        // Met on the third day: silver.
        var (later, _) = try makeStations()
        try later.startScenario(rules)
        try later.advance(ticks: 2 * 1_440 + 1)
        try later.setLand([LandCell(row: 0, column: 0, use: .residential, residents: 10, jobs: 0)])
        try later.advance(ticks: 1_440)
        XCTAssertEqual(later.scenario?.achieved, [2])
        XCTAssertEqual(later.scenario?.outcome, .completed(day: 2, rating: .silver))
    }

    func testMidnightsInTheRedInARowLoseIt() throws {
        var (world, _) = try makeStations()
        try world.startScenario(scenario([.population(1)], gold: 10, silver: 20, deadline: 30, insolvency: 2))
        world.economy.settle(.zero - world.economy.balance - Money(1))
        try world.advance(ticks: 1_441)
        XCTAssertEqual(world.scenario?.insolventDays, 1)
        XCTAssertNil(world.scenario?.outcome)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.scenario?.outcome, .failed(day: 1, reason: .insolvency))
    }

    func testRidersPopulationTallBuildingsAndAClosedYearAreRead() throws {
        var (world, _) = try makeStations()
        XCTAssertEqual(world.lastDayTrips(), 0)
        var yesterday = DayAccount(day: -1)
        yesterday.fareTrips = 1_234
        world.accounts.days = [yesterday]
        XCTAssertEqual(world.lastDayTrips(), 1_234)
        XCTAssertTrue(world.isMet(.dailyRiders(1_234)))
        XCTAssertFalse(world.isMet(.dailyRiders(1_235)))
        let day = try JSONEncoder().encode(yesterday)
        XCTAssertTrue(String(decoding: day, as: UTF8.self).contains(#""fareTrips":1234"#))
        XCTAssertEqual(try JSONDecoder().decode(DayAccount.self, from: day), yesterday)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(DayAccount(day: 0)), as: UTF8.self).contains("fareTrips"))

        try world.setLand([
            LandCell(row: 0, column: 0, use: .residential, residents: 300, jobs: 0),
            LandCell(row: 0, column: 1, use: .office, residents: 0, jobs: 900),
        ])
        XCTAssertEqual(world.totalResidents(), 300)
        XCTAssertTrue(world.isMet(.population(300)))
        XCTAssertEqual(world.tallBuildingCount(), 0)
        XCTAssertFalse(world.isMet(.tallBuildings(1)))
        XCTAssertFalse(world.isMet(.annualNetProfit(Money(1))))
        XCTAssertTrue(world.isMet(.equity(Money(1))))
    }

    /// Riders are judged on the day that ended, however the time came: one
    /// advance skipping idle minutes past midnight, or a minute at a time.
    func testDailyRidersAreJudgedOnTheDayThatEndedHoweverTimeIsAdvanced() throws {
        var (world, _) = try makeStations()
        var today = DayAccount(day: 0)
        today.fareTrips = 5
        world.accounts.days = [today]
        try world.startScenario(scenario([.dailyRiders(1)]))
        var stepped = world
        try world.advance(ticks: 1_441)
        for _ in 0..<1_441 {
            try stepped.advance(ticks: 1)
        }
        XCTAssertEqual(stepped.scenario?.achieved, [0])
        XCTAssertEqual(world.scenario, stepped.scenario)
    }

    /// A scenario started on the stroke of a midnight not yet settled is
    /// judged from its own first day, so the save stays loadable.
    func testAScenarioStartedAtAnUnsettledMidnightKeepsALoadableSave() throws {
        var (world, _) = try makeStations()
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.clock.now, GameTime(seconds: GameTime.secondsPerDay))
        try world.startScenario(scenario([.equity(Money(1))]))
        XCTAssertEqual(world.scenario?.startDay, 1)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.scenario?.achieved, [nil], "day 0 ended before the scenario began")
        XCTAssertNil(world.scenario?.outcome)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(loaded, world)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.scenario?.achieved, [1])
    }

    func testTheErasTrainTypesAreTheOnlyOnesAllowed() throws {
        var (world, _) = try makeStations()
        let train = try world.purchaseTrain(named: "T1").id
        try world.startScenario(scenario([.population(1)], types: [.c, .d]))
        try world.setTrainType(train, to: .c)
        expect(.trainTypeUnavailable(.maglev)) { try world.setTrainType(train, to: .maglev) }
        try world.setTrainType(train, to: nil)
        XCTAssertNil(world.train(id: train)?.type)
    }

    func testFastForwardRunsTenMinutesATick() throws {
        var (world, _) = try makeStations()
        world.setSpeed(.fast)
        try world.advance(ticks: 144)
        XCTAssertEqual(world.clock.now, GameTime(seconds: GameTime.secondsPerDay))
        try world.advance(ticks: 1)
        // The day's settlement ran as at any speed.
        XCTAssertEqual(world.accounts.assets.map(\.days), [1, 1, 1, 1, 1])
    }

    func testABadScenarioInASaveIsRefused() throws {
        var (world, s) = try makeStations()
        try world.createLine(named: "Main", stops: [s[0], s[1]])
        try world.startScenario(scenario([.connect(points: [point(0), point(1)], radius: 2_048)]))
        try world.advance(ticks: 1_441)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = String(decoding: try encoder.encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""outcome":{"day":0,"rating":"gold"}"#), text)
        for (old, new) in [
            (#""rating":"gold""#, #""rating":"silver""#),
            (#""achieved":[0]"#, #""achieved":[5]"#),
            (#""achieved":[0]"#, #""achieved":[null]"#),
            (#""goldDays":2"#, #""goldDays":9"#),
            (#""startDay":0"#, #""startDay":3"#),
        ] {
            XCTAssertTrue(text.contains(old), old)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(text.replacingOccurrences(of: old, with: new).utf8)), new)
        }
    }

    private func expect(_ expected: GameError, _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? GameError, expected, file: file, line: line) }
    }

    /// Decision 90: a scenario's festival is announced its notice before
    /// its day of each year, raises its station's demand while it runs, and
    /// comes back the next year; a festival at a station that is gone is
    /// not held, and one at a station that never was is refused.
    func testAFestivalComesBackOnItsDayEveryYear() throws {
        var (world, s) = try makeStations()
        world.setDemandEvents(seed: 1)
        let festival = ScenarioEvent(station: s[1], dayOfYear: 5, days: 3, boost: 1_500, notice: 2)
        expect(.invalidScenario) {
            try world.startScenario(scenario([.population(1)], gold: 400, silver: 500, deadline: 900,
                                             events: [ScenarioEvent(station: StationID(rawValue: 99), dayOfYear: 5, days: 3, boost: 1_500, notice: 2)]))
        }
        try world.startScenario(scenario([.population(1)], gold: 400, silver: 500, deadline: 900, events: [festival]))
        func festivals() -> [DemandEvent] {
            world.demandEvents?.events.filter { $0.kind == .festival } ?? []
        }
        // Day 3 starts: announced for day 5.
        try world.advance(ticks: 2 * 1_440 + 1)
        XCTAssertEqual(festivals(), [])
        try world.advance(ticks: 1_440)
        XCTAssertEqual(festivals(), [DemandEvent(kind: .festival, station: s[1], announced: 3, start: 5, end: 8, boost: 1_500)])
        XCTAssertEqual(world.demandMultiplier(at: s[1]), 1_000, "not yet")
        try world.advance(ticks: 2 * 1_440)
        XCTAssertEqual(world.demandMultiplier(at: s[1]), 2_500, "two and a half times")
        try world.advance(ticks: 3 * 1_440)
        XCTAssertEqual(festivals(), [], "over")
        XCTAssertNil(world.demandEventProblem())
        // The next year's is announced on day 363.
        try world.advance(ticks: 355 * 1_440)
        XCTAssertEqual(festivals().map(\.start), [365])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)

        try world.removeStation(s[1])
        XCTAssertEqual(festivals(), [])
        try world.advance(ticks: 360 * 1_440)
        XCTAssertEqual(festivals(), [], "its station is gone")
    }
}

