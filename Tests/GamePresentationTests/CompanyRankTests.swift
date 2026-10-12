import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 181: the company's rank, its seven measures, its
/// titles and the milestones it suggests.
final class CompanyRankTests: XCTestCase {
    func testTheMeasuresAddUpToAThousand() {
        XCTAssertEqual(RankMeasure.allCases.reduce(0) { $0 + $1.maximum }, 1_000)
    }

    func testEachMeasureCountsLinearlyToItsFullMarks() {
        XCTAssertEqual(RankMeasure.bestDay.points(for: 0), 0)
        XCTAssertEqual(RankMeasure.bestDay.points(for: 300_000), 75)
        XCTAssertEqual(RankMeasure.bestDay.points(for: 500_000), 125)
        XCTAssertEqual(RankMeasure.bestDay.points(for: 1_000_000), 250)
        XCTAssertEqual(RankMeasure.bestDay.points(for: 3_000_000), 250)
        XCTAssertEqual(RankMeasure.network.points(for: 30_000), 10)
        XCTAssertEqual(RankMeasure.stations.points(for: 37), 37)
        XCTAssertEqual(RankMeasure.netWorth.points(for: -5_000_000), 0)
        XCTAssertEqual(RankMeasure.netWorth.points(for: 25_000_000_000), 100)
        XCTAssertEqual(RankMeasure.servedPeople.points(for: 1_000_000), 75)
        XCTAssertEqual(RankMeasure.punctuality.points(for: 900), 90)
    }

    func testTheOperatingRatioEarnsMoreTheLowerItIs() {
        let ratio = RankMeasure.operatingRatio
        XCTAssertEqual(ratio.points(for: 400), 100, "60% or less is full marks")
        XCTAssertEqual(ratio.points(for: 600), 100)
        XCTAssertEqual(ratio.points(for: 800), 50)
        XCTAssertEqual(ratio.points(for: 1_000), 0, "costs as large as the takings earn nothing")
        XCTAssertEqual(ratio.points(for: 5_000), 0)
    }

    func testATitleForEveryHundredPointsAndATycoonFrom960() {
        XCTAssertEqual(CompanyTitle(score: 0), .traineeClerk)
        XCTAssertEqual(CompanyTitle(score: 99), .traineeClerk)
        XCTAssertEqual(CompanyTitle(score: 100), .stationClerk)
        XCTAssertEqual(CompanyTitle(score: 350), .stationmaster)
        XCTAssertEqual(CompanyTitle(score: 959), .chairman)
        XCTAssertEqual(CompanyTitle(score: 960), .tycoon)
        XCTAssertEqual(CompanyTitle(score: 1_000), .tycoon)
        XCTAssertEqual(CompanyTitle.allCases.count, 11)
        XCTAssertEqual(CompanyTitle.chairman.title(in: .traditionalChinese), "董事長")
        XCTAssertEqual(CompanyTitle.tycoon.title(in: .traditionalChinese), "鐵道大亨")
    }

    func testTheScoreAndWhatTheNextTitleNeeds() {
        let figures = CompanyFigures(
            bestDayRiders: 30_000, trackMetres: 30_000, stations: 10, netWorth: Money(500_000_000), servedPeople: 100_000,
            operatingRatio: 800, punctuality: 1_000
        )
        let rank = CompanyRank(figures: figures)
        // 7 + 10 + 10 + 2 + 7, and the operating ratio's 50 and the trains'
        // 100 at 10 of the 20 stations: 25 + 50.
        XCTAssertEqual(rank.score, 111)
        XCTAssertEqual(rank.title, .stationClerk)
        XCTAssertEqual(rank.pointsToNextTitle, 89)
        XCTAssertEqual(rank.nextTitleText(in: .traditionalChinese), "再 89 分升為副站長")
        XCTAssertEqual(rank.headline(in: .english), "Station Clerk · 111 / 1,000")
        var larger = figures
        larger.stations = 40
        XCTAssertEqual(CompanyRank(figures: larger).parts.first { $0.measure == .punctuality }?.points, 100, "20 stations or more: full marks")
    }

    func testWithoutTakingsOrTrainsTheirMeasuresAreBlank() {
        let rank = CompanyRank(figures: CompanyFigures(bestDayRiders: 0))
        XCTAssertEqual(rank.score, 0)
        let ratio = try? XCTUnwrap(rank.parts.first { $0.measure == .operatingRatio })
        XCTAssertNil(ratio?.value)
        XCTAssertEqual(rank.partText(ratio!, in: .english), "Operating ratio — · 0 / 100")
    }

    func testTheMilestonesAreEachMeasuresNextRungTheRichestFirst() {
        let figures = CompanyFigures(
            bestDayRiders: 31_200, trackMetres: 12_000, stations: 4, netWorth: Money(300_000_000), servedPeople: 40_000,
            operatingRatio: 1_200, punctuality: 1_000
        )
        let milestones = CompanyRank(figures: figures).milestones()
        XCTAssertEqual(milestones.count, 3)
        XCTAssertEqual(milestones.map(\.gain), milestones.map(\.gain).sorted(by: >))
        XCTAssertFalse(milestones.contains { $0.measure == .punctuality }, "full marks need no milestone")
        let riders = try? XCTUnwrap(CompanyRank(figures: figures).milestones(count: 7).first { $0.measure == .bestDay })
        XCTAssertEqual(riders?.target, 50_000)
        XCTAssertEqual(riders?.text(in: .traditionalChinese), "每日旅客 50,000（目前 31,200）")
        let ratio = CompanyRank(figures: figures).milestones(count: 7).first { $0.measure == .operatingRatio }
        XCTAssertEqual(ratio?.target, 900, "a ratio climbs down")
    }

    func testAWorldIsMeasured() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 3 * 1_440 + 720)
        let figures = CompanyFigures(world: world)
        XCTAssertEqual(figures.stations, 2)
        XCTAssertGreaterThan(figures.trackMetres, 5_000, "the two towns are 5.4 km apart")
        XCTAssertGreaterThan(figures.bestDayRiders, 0)
        XCTAssertGreaterThan(figures.servedPeople, 0)
        XCTAssertNotNil(figures.operatingRatio)
        XCTAssertNotNil(figures.punctuality)
        let rank = CompanyRank(figures: figures)
        XCTAssertEqual(rank.score, rank.parts.reduce(0) { $0 + $1.points })
    }

    func testThePeopleServedAreCountedOnce() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let one = try newGameLine(through: [towns[0], towns[1]])
        let alone = CompanyFigures.servedPeople(in: one)
        let land = one.land.totals(within: Land.catchmentRadius, of: one.stations[0].location).residents
            + one.land.totals(within: Land.catchmentRadius, of: one.stations[1].location).residents
        XCTAssertGreaterThan(alone, 0)
        XCTAssertLessThanOrEqual(alone, land)
    }

    func testTheNextTownIsSaidFromTheNearestStation() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let town = try XCTUnwrap(UnservedCluster.largest(in: world))
        let text = town.suggestionText(in: world, language: .traditionalChinese)
        XCTAssertTrue(world.stations.contains { text.hasPrefix($0.name) }, text)
        XCTAssertTrue(text.contains("公里，約 "), text)
        XCTAssertTrue(town.suggestionText(in: .newGame(), language: .english).hasPrefix("A town of about"))
    }
}
