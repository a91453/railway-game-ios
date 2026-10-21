import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 301: three ratings of a line as its riders would
/// find it (waiting from the headway, crowding from the fullest train,
/// punctuality from the trips on time), each out of 100 with the figure it
/// comes from; not rated without enough to go on; the fix beside the
/// weakest. Only shown: the world is not changed by working it out. And
/// the rolling-stock catalog's cost an hour.
@MainActor
final class LineSatisfactionTests: XCTestCase {
    private static let line = LineID(rawValue: 1)

    /// Decision 194's measures over 3 days: a train every 15 minutes each
    /// way on a line of 4 stops (3 legs) for 18 hours, the fullest train
    /// 70% full, 200 of 210 trips on time.
    private func measures(
        departures: Int64 = 1_296, boardings: Int64 = 20_000, peak: Int64 = 700, trips: Int64 = 210, late: Int64 = 10
    ) -> LineLossMeasures {
        LineLossMeasures(
            days: 3, fareRevenue: Money(10_000_000), boardings: boardings, departures: departures,
            trainDistance: 1_000_000, deadheadDistance: 0, peakLoadSum: peak * 3, trains: 4, seatsPerTrain: 1_280,
            trainKeepPerDay: Money(400_000), legsPerTrip: 3, serviceMinutes: 1_080, trips: trips, lateTrips: late
        )
    }

    // MARK: Scores

    func testWaitingIsFullAtSixMinutesAndNoneAtThirtySix() {
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 3), 100)
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 6), 100)
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 10), 86)
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 15), 70)
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 20), 53)
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 22), 46)
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 23), 43)
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 30), 20)
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 36), 0)
        XCTAssertEqual(LineSatisfaction.waitingScore(headway: 60), 0)
    }

    func testCrowdingIsFullAtSixtyPercentAndNoneAtOneHundredAndTen() {
        XCTAssertEqual(LineSatisfaction.crowdingScore(peakPermille: 0), 100)
        XCTAssertEqual(LineSatisfaction.crowdingScore(peakPermille: 600), 100)
        XCTAssertEqual(LineSatisfaction.crowdingScore(peakPermille: 750), 70)
        XCTAssertEqual(LineSatisfaction.crowdingScore(peakPermille: 875), 45)
        XCTAssertEqual(LineSatisfaction.crowdingScore(peakPermille: 900), 40, "decision 194's crowded is poor")
        XCTAssertEqual(LineSatisfaction.crowdingScore(peakPermille: 1_100), 0)
    }

    func testPunctualityIsNoneAtEightyPercentAndFullAtNinetyEight() {
        XCTAssertEqual(LineSatisfaction.punctualityScore(onTimePermille: 1_000), 100)
        XCTAssertEqual(LineSatisfaction.punctualityScore(onTimePermille: 980), 100)
        XCTAssertEqual(LineSatisfaction.punctualityScore(onTimePermille: 925), 70)
        XCTAssertEqual(LineSatisfaction.punctualityScore(onTimePermille: 920), 67)
        XCTAssertEqual(LineSatisfaction.punctualityScore(onTimePermille: 880), 45)
        XCTAssertEqual(LineSatisfaction.punctualityScore(onTimePermille: 879), 44)
        XCTAssertEqual(LineSatisfaction.punctualityScore(onTimePermille: 800), 0)
        XCTAssertEqual(LineSatisfaction.punctualityScore(onTimePermille: 500), 0)
    }

    func testTheBands() {
        XCTAssertEqual(LineSatisfaction.Grade(score: 100), .good)
        XCTAssertEqual(LineSatisfaction.Grade(score: 70), .good)
        XCTAssertEqual(LineSatisfaction.Grade(score: 69), .fair)
        XCTAssertEqual(LineSatisfaction.Grade(score: 45), .fair)
        XCTAssertEqual(LineSatisfaction.Grade(score: 44), .poor)
        XCTAssertEqual(LineSatisfaction.Grade(score: 0), .poor)
    }

    // MARK: From the measures

    func testThreeItemsFromTheMeasures() throws {
        let satisfaction = LineSatisfaction(line: Self.line, days: 3, measures: measures(), countsTrips: true)
        XCTAssertEqual(measures().headwayMinutes, 15)
        XCTAssertEqual(satisfaction.items.map(\.aspect), [.waiting, .crowding, .punctuality])
        XCTAssertEqual(satisfaction.items.map(\.rating), [
            .rated(score: 70, figure: 15), .rated(score: 80, figure: 700), .rated(score: 85, figure: 952),
        ])
        XCTAssertEqual(satisfaction.items.map(\.grade), [.good, .good, .good])
        XCTAssertNil(satisfaction.weakest, "all good: no fix offered")
        XCTAssertTrue(satisfaction.isRated)

        let waiting = satisfaction.items[0], crowding = satisfaction.items[1], punctuality = satisfaction.items[2]
        XCTAssertEqual(satisfaction.spanText(in: .english), "Riders' view, last 3 days")
        XCTAssertEqual(satisfaction.spanText(in: .traditionalChinese), "乘客感受（最近 3 天）")
        XCTAssertNil(satisfaction.waitingText(in: .english))
        XCTAssertEqual(waiting.scoreText(in: .english), "70%")
        XCTAssertEqual(waiting.detail(in: .english), "About 7.5 min on average, estimated from a train every 15 min")
        XCTAssertEqual(waiting.detail(in: .traditionalChinese), "平均約 7.5 分，由每 15 分一班估算")
        XCTAssertEqual(crowding.detail(in: .english), "The fullest train of a day leaves 70% full on average")
        XCTAssertEqual(crowding.detail(in: .traditionalChinese), "每天最擠的一班平均坐滿 70%")
        XCTAssertEqual(punctuality.detail(in: .english), "95% of trips no more than 5 min late")
        XCTAssertEqual(punctuality.detail(in: .traditionalChinese), "95% 的車次誤點不超過 5 分鐘")
        XCTAssertEqual(waiting.spokenText(in: .english), "Waiting 70%, Good: About 7.5 min on average, estimated from a train every 15 min")
        XCTAssertNil(waiting.advice(in: .english))
    }

    /// A higher score is always better, so each item's name says what is
    /// good in both languages: "Room on board" 30% is a crowded train, and
    /// the Chinese must not read as "30% crowded".
    func testEachTitleNamesWhatAHighScoreMeans() {
        XCTAssertEqual(LineSatisfaction.Aspect.allCases.map { $0.title(in: .english) }, ["Waiting", "Room on board", "On time"])
        XCTAssertEqual(LineSatisfaction.Aspect.allCases.map { $0.title(in: .traditionalChinese) }, ["候車", "車上空間", "準點"])
    }

    func testTheWeakestBelowGoodGetsTheAdvice() throws {
        // A train every 30 min (half the departures), the fullest 95% full.
        let satisfaction = LineSatisfaction(
            line: Self.line, days: 3, measures: measures(departures: 648, peak: 950), countsTrips: true
        )
        XCTAssertEqual(satisfaction.items.map(\.score), [20, 30, 85])
        XCTAssertEqual(satisfaction.items.map(\.grade), [.poor, .poor, .good])
        let weakest = try XCTUnwrap(satisfaction.weakest)
        XCTAssertEqual(weakest.aspect, .waiting)
        XCTAssertEqual(weakest.detail(in: .traditionalChinese), "平均約 15 分，由每 30 分一班估算")
        XCTAssertEqual(weakest.advice(in: .english), "Run trains more often to cut the wait.")
        XCTAssertEqual(weakest.advice(in: .traditionalChinese), "班距縮短，候車就短。")
        XCTAssertEqual(satisfaction.items[1].advice(in: .traditionalChinese), "加開列車，或改用長一點的列車。")
        XCTAssertEqual(LineSatisfaction.Aspect.waiting.fixKind, .longHeadway)
        XCTAssertEqual(LineSatisfaction.Aspect.crowding.fixKind, .longHeadway)
        XCTAssertNil(LineSatisfaction.Aspect.punctuality.fixKind, "no one-tap fix for lateness")

        // Late trains only: the advice names what helps, without a button.
        let late = LineSatisfaction(line: Self.line, days: 3, measures: measures(late: 40), countsTrips: true)
        XCTAssertEqual(late.weakest?.aspect, .punctuality)
        XCTAssertEqual(late.weakest?.score, 5)
        XCTAssertNotNil(late.weakest?.advice(in: .traditionalChinese))
    }

    func testTooFewToRateSaysSoRatherThanAScore() {
        let few = LineSatisfaction(
            line: Self.line, days: 1, measures: measures(departures: 11, boardings: 99, trips: 9, late: 0), countsTrips: true
        )
        XCTAssertEqual(few.items.map(\.rating), [.tooFew, .tooFew, .tooFew])
        XCTAssertFalse(few.isRated)
        XCTAssertNil(few.weakest)
        XCTAssertEqual(few.items.map { $0.scoreText(in: .traditionalChinese) }, ["尚未評分", "尚未評分", "尚未評分"])
        XCTAssertEqual(few.items[0].scoreText(in: .english), "Not rated yet")
        XCTAssertEqual(few.items[0].detail(in: .traditionalChinese), "開出的班次還太少。")
        XCTAssertEqual(few.items[1].detail(in: .traditionalChinese), "搭車的人還太少。")
        XCTAssertEqual(few.items[2].detail(in: .traditionalChinese), "跑完的車次還太少。")

        // Enough trains, but nobody aboard: waiting rated, crowding not.
        let empty = LineSatisfaction(line: Self.line, days: 3, measures: measures(boardings: 0), countsTrips: true)
        XCTAssertNotNil(empty.items[0].score)
        XCTAssertEqual(empty.items[1].rating, .tooFew)
    }

    func testPunctualityWithoutRealisticOperationIsNotCounted() {
        let satisfaction = LineSatisfaction(line: Self.line, days: 3, measures: measures(trips: 0, late: 0), countsTrips: false)
        XCTAssertEqual(satisfaction.items[2].rating, .notCounted)
        XCTAssertEqual(satisfaction.items[2].scoreText(in: .traditionalChinese), "尚未評分")
        XCTAssertEqual(satisfaction.items[2].detail(in: .traditionalChinese), "開啟寫實運轉才會計算。")
        XCTAssertEqual(satisfaction.items[2].detail(in: .english), "Counted only with realistic operation on.")
    }

    // MARK: In a world

    func testANewLineIsNotRatedUntilItsFirstDay() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        let first = try XCTUnwrap(world.lineSatisfaction(Self.line))
        XCTAssertEqual(first.days, 0)
        XCTAssertTrue(first.items.isEmpty)
        XCTAssertEqual(first.spanText(in: .traditionalChinese), "乘客感受：尚未評分")
        XCTAssertEqual(first.waitingText(in: .traditionalChinese), "這條線營運滿一天之後才有分數。")
        XCTAssertEqual(first.waitingText(in: .english), "Scores come after the line's first full day of running.")

        try world.advance(ticks: 1 + 2 * 1_440)
        let before = world
        let rated = try XCTUnwrap(world.lineSatisfaction(Self.line))
        let diagnosis = try XCTUnwrap(world.lineLossDiagnosis(Self.line))
        XCTAssertTrue(world.realisticOperation, "a new game counts its trips (decision 207)")
        XCTAssertEqual(rated, LineSatisfaction(line: Self.line, days: diagnosis.days, measures: diagnosis.measures, countsTrips: true))
        XCTAssertEqual(rated.days, 2)
        XCTAssertNotNil(rated.items[0].score, "the train ran")
        XCTAssertNotNil(rated.items[1].score, "riders rode")
        XCTAssertNotNil(rated.items[2].score, "its trips finished")
        XCTAssertEqual(world, before, "working it out changes nothing")

        world.setRealisticOperation(false)
        XCTAssertEqual(world.lineSatisfaction(Self.line)?.items[2].rating, .rated(score: 100, figure: 1_000), "trips already counted stay")
    }

    func testAFreightLineOrNoLineHasNone() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        XCTAssertNil(world.lineSatisfaction(LineID(rawValue: 99)))
    }

    func testTheMemoOffersTheFixOfTheWeakestAndWorksItOutOncePerDay() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.economy.earn(Money(10_000_000_000))
        // Without traffic control a shorter headway can be run (decision
        // 194's fix; under it the single track holds one train).
        try world.setTrafficControl(false)
        try world.advance(ticks: 1 + 2 * 1_440)
        let session = GameSession(world: world)
        let memo = LineSatisfactionMemo()
        let satisfaction = try XCTUnwrap(memo.satisfaction(Self.line, of: session))
        XCTAssertEqual(satisfaction, session.world.lineSatisfaction(Self.line))
        let expected = satisfaction.weakest?.aspect.fixKind.flatMap { session.world.lineLossFix($0, on: Self.line) }
        XCTAssertEqual(memo.fix(Self.line, of: session), expected)
        if let weakest = satisfaction.weakest, weakest.aspect != .punctuality {
            XCTAssertNotNil(expected, "one train every round trip: more trains shorten the wait")
        }
        _ = memo.satisfaction(Self.line, of: session)
        XCTAssertEqual(memo.workedOut, 1, "the same revision and day")
    }

    // MARK: The catalog's cost an hour

    func testACatalogTrainsCostAnHourIsItsDayOverTwentyFourHours() {
        XCTAssertEqual(RollingStockCatalog.hourlyCost(daily: Money(103_200)), Money(4_300))
        XCTAssertEqual(RollingStockCatalog.hourlyCost(daily: Money(120_000)), Money(5_000))
        XCTAssertEqual(RollingStockCatalog.hourlyCost(daily: Money(118_800)), Money(5_000), "$49.50 rounds half up")
        XCTAssertEqual(RollingStockCatalog.hourlyCost(daily: .zero), .zero)
        let world = DemoWorld.make(in: .english)
        let train = RollingStockCatalog.train(.a, cars: 4, in: world)
        XCTAssertEqual(train.hourly, RollingStockCatalog.hourlyCost(daily: world.dailyRunningCost(of: .a, cars: 4)))
        XCTAssertGreaterThan(train.hourly, .zero)
    }
}
