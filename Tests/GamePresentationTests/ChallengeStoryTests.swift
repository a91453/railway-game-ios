@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 387: a challenge's story, its beats said at the moments the
/// world can tell, once each, and not again in a game loaded later.
final class ChallengeStoryTests: XCTestCase {
    /// A Pingxi challenge on a small map: Shifen and Pingxi on a line, the
    /// festival on day `festivalDay` of the year, announced a week before.
    private func pingxi(festivalDay: Int64 = PingxiChallenge.festivalDay) throws -> GameWorld {
        var world = GameWorld.newGame(eventSeed: 1)
        world.setDisruptions(nil)
        world.setCityRequests(seed: nil)
        let middle = PlanPoint(x: world.bounds.width / 2, y: world.bounds.height / 2)
        let shifen = try world.buildStation(named: "十分", at: middle).id
        let pingxi = try world.buildStation(named: "平溪", at: PlanPoint(x: middle.x + 64_000, y: middle.y)).id
        let line = try world.createLine(named: "平溪線", stops: [shifen, pingxi]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line, pattern: nil)
        try world.startScenario(Scenario(
            id: Challenge.pingxi.id, goals: [.dailyRiders(PingxiChallenge.ridersTarget), .annualNetProfit(PingxiChallenge.profitTarget)],
            goldDays: 360, silverDays: 720, deadlineDays: 1_080, insolvencyDays: 60,
            events: [shifen, pingxi].map {
                ScenarioEvent(station: $0, dayOfYear: festivalDay, days: PingxiChallenge.festivalDays, boost: PingxiChallenge.festivalBoost, notice: PingxiChallenge.festivalNotice)
            }
        ))
        return world
    }

    private func ids(_ world: GameWorld, today: Int64) -> [String] {
        PingxiChallenge.story.beats(at: StoryMoment.moments(in: world, today: today)).map(\.id)
    }

    func testThePingxiScriptHasItsTenBeatsAndFourEndings() {
        let beats = PingxiChallenge.story.beats
        XCTAssertEqual(beats.count, 14)
        XCTAssertEqual(Set(beats.map(\.id)).count, 14)
        XCTAssertEqual(beats.filter(\.moment.isEnding).count, 4)
        for beat in beats {
            XCTAssertFalse(beat.text(in: .english).isEmpty)
            XCTAssertFalse(beat.text(in: .traditionalChinese).isEmpty)
        }
        XCTAssertEqual(beats.filter(\.carriesFestivalAdvice).map(\.id), ["pingxi.4"])
        XCTAssertEqual(Set(beats.map(\.speaker)), Set(StoryCharacter.allCases))
        XCTAssertNotNil(ChallengeStory.named("history.pingxi"))
        XCTAssertNil(ChallengeStory.named("history.liuMingchuan"), "its script has not come yet")
    }

    func testTheDaysOfTheChallenge() throws {
        let world = try pingxi()
        // Day 1 is the day it started (day 0 of the game).
        XCTAssertEqual(ids(world, today: 0), [], "the day it started began before it")
        XCTAssertEqual(ids(world, today: 2), ["pingxi.1"])
        XCTAssertEqual(ids(world, today: 14), ["pingxi.2"])
        XCTAssertEqual(ids(world, today: 39), ["pingxi.3"])
        XCTAssertEqual(ids(world, today: 3), [])
    }

    func testTheFestivalEveryYear() throws {
        let world = try pingxi()
        for year: Int64 in [0, 1, 2] {
            let start = PingxiChallenge.festivalDay + year * 360
            XCTAssertEqual(ids(world, today: start - 7), ["pingxi.4"])
            XCTAssertEqual(ids(world, today: start), ["pingxi.5"])
            XCTAssertEqual(ids(world, today: start + 1), [])
            XCTAssertEqual(ids(world, today: start + 3), ["pingxi.6"])
        }
    }

    func testNoFestivalWithoutItsStationsOrDemandEvents() throws {
        var world = try pingxi()
        world.demandEvents = nil
        XCTAssertEqual(ids(world, today: PingxiChallenge.festivalDay), [])
    }

    func testAYearClosedAndTheFirstDayInProfit() throws {
        var world = try pingxi()
        XCTAssertEqual(ids(world, today: 360), [], "no year closed yet")
        let income = FinanceSummary(
            index: 0, fareRevenue: Money(1_000), operatingCost: Money(200), maintenanceCost: .zero, energyCost: .zero, staffCost: .zero, interestCost: .zero
        )
        let zero = AssetClassBalance.zero
        world.accounts.years = [AnnualStatement(year: 0, income: income, closing: BalanceSheet(cash: .zero, track: zero, stations: zero, rollingStock: zero, loan: .zero))]
        XCTAssertEqual(ids(world, today: 360), ["pingxi.10"])
        XCTAssertEqual(ids(world, today: 720), [], "the second year has not closed")

        var losing = DayAccount(day: 4)
        losing.operatingCost = Money(500)
        var earning = DayAccount(day: 5)
        earning.fareRevenue = Money(600)
        earning.operatingCost = Money(500)
        var again = DayAccount(day: 6)
        again.fareRevenue = Money(900)
        world.accounts.days = [losing, earning, again]
        XCTAssertEqual(ids(world, today: 5), [])
        XCTAssertEqual(ids(world, today: 6), ["pingxi.7"])
        XCTAssertEqual(ids(world, today: 7), [], "only the first")
    }

    func testRedCashTheRidersGoalAndTheEndings() throws {
        var world = try pingxi()
        world.scenario?.insolventDays = 1
        XCTAssertEqual(ids(world, today: 20), ["pingxi.9"])
        world.scenario?.insolventDays = 2
        XCTAssertEqual(ids(world, today: 20), [], "only the first midnight in the red")
        world.scenario?.insolventDays = 0

        world.scenario?.achieved[0] = 62
        XCTAssertEqual(ids(world, today: 63), ["pingxi.8"])
        XCTAssertEqual(ids(world, today: 64), [])

        XCTAssertNil(PingxiChallenge.story.ending(in: world))
        // The year closed at the same midnight: the ending is said alone.
        world.scenario?.outcome = .completed(day: 359, rating: .gold)
        let income = FinanceSummary(
            index: 0, fareRevenue: Money(1_000), operatingCost: .zero, maintenanceCost: .zero, energyCost: .zero, staffCost: .zero, interestCost: .zero
        )
        let zero = AssetClassBalance.zero
        world.accounts.years = [AnnualStatement(year: 0, income: income, closing: BalanceSheet(cash: .zero, track: zero, stations: zero, rollingStock: zero, loan: .zero))]
        XCTAssertEqual(ids(world, today: 360), ["pingxi.gold"])
        XCTAssertEqual(PingxiChallenge.story.ending(in: world)?.id, "pingxi.gold")
        for (rating, id) in [(ScenarioRating.silver, "pingxi.silver"), (.bronze, "pingxi.bronze")] {
            world.scenario?.outcome = .completed(day: 800, rating: rating)
            XCTAssertEqual(ids(world, today: 801), [id])
            XCTAssertEqual(PingxiChallenge.story.ending(in: world)?.speaker, rating == .silver ? .xiaoWei : .stationMaster)
        }
        world.scenario?.outcome = .failed(day: 90, reason: .insolvency)
        XCTAssertEqual(ids(world, today: 91), ["pingxi.failed"])
        XCTAssertEqual(
            PingxiChallenge.story.ending(in: world)?.text(in: .traditionalChinese),
            "這一次，平溪線沒能撐下去。但它在 1980 年代也差點停駛，是有人不肯放棄才留下來的，再接手一次吧。"
        )
    }

    /// The teller says a day's beats when it sees the day begin, once; a
    /// game it first looks at (one loaded, say) says nothing of its day.
    func testTheTellerSaysEachDayOnceAndNotAfterALoad() throws {
        var world = try pingxi()
        var teller = StoryTeller()
        XCTAssertEqual(teller.look(at: world), [])
        try world.advance(ticks: 2 * 1_440 + 1)
        XCTAssertEqual(teller.look(at: world).map(\.id), ["pingxi.1"])
        XCTAssertEqual(teller.look(at: world), [], "said once")
        var loaded = StoryTeller()
        XCTAssertEqual(loaded.look(at: world), [], "a game loaded on the day is not told it again")
    }

    /// Decision 387: the festival's notice is one card, the story's line
    /// over the station master's.
    func testTheFestivalNoticeCarriesTheStationMastersWord() throws {
        var world = try pingxi(festivalDay: 8)
        try world.advance(ticks: 1_441)
        let beat = try XCTUnwrap(PingxiChallenge.story.beatsToday(in: world).first)
        XCTAssertEqual(beat.id, "pingxi.4")
        XCTAssertEqual(beat.advice(in: world), .festivalComing(days: 7, stations: ["十分", "平溪"], percent: 150))
        XCTAssertEqual(beat.advice(in: world)?.text(in: .traditionalChinese), "7 天後是天燈節，十分、平溪的旅客會多 150%。先加開列車吧。")
    }

    func testTheCharactersNames() {
        XCTAssertEqual(StoryCharacter.ahSong.name(in: .traditionalChinese), "阿松伯")
        XCTAssertEqual(StoryCharacter.xiaoWei.name(in: .english), "Xiaowei")
        XCTAssertNil(StoryCharacter.stationMaster.portrait)
        XCTAssertEqual(StoryCharacter.allCases.compactMap(\.portrait), ["StoryAhSong", "StoryXiaoWei", "StoryMia"])
    }
}
