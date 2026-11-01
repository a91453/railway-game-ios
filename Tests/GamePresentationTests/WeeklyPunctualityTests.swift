import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// NEXT_PRIORITIES §22.17, first card: the line card's last seven days'
/// punctuality, with Taiwan Railway's past year beside it.
final class WeeklyPunctualityTests: XCTestCase {
    private static let line = LineID(rawValue: 1)

    private func day(_ day: Int64, trips: Int64, late: Int64) -> LineDay {
        var tally = LineTally()
        tally.trips = trips
        tally.lateTrips = late
        return LineDay(day: day, tally: tally)
    }

    func testAddsUpOnlyTheLastSevenSettledDays() throws {
        let records = (0...9).map { day(Int64($0), trips: 10, late: Int64($0)) }
        // Settled up to day 8 (day 9 is in progress): days 1–7 count.
        let weekly = try XCTUnwrap(WeeklyPunctuality(records: records, settledDay: 8))
        XCTAssertEqual(weekly.trips, 70)
        XCTAssertEqual(weekly.lateTrips, 1 + 2 + 3 + 4 + 5 + 6 + 7)
        XCTAssertEqual(weekly.permille, 600)
    }

    func testFewerThanTenTripsShowNothing() {
        XCTAssertNil(WeeklyPunctuality(records: [day(0, trips: 9, late: 0)], settledDay: 1))
        XCTAssertNotNil(WeeklyPunctuality(records: [day(0, trips: 10, late: 0)], settledDay: 1))
        XCTAssertNil(WeeklyPunctuality(records: [day(1, trips: 50, late: 0)], settledDay: 1), "the day in progress is not counted")
        XCTAssertNil(WeeklyPunctuality(records: [], settledDay: 1))
    }

    func testTextInBothLanguages() throws {
        let weekly = try XCTUnwrap(WeeklyPunctuality(records: [day(0, trips: 200, late: 13)], settledDay: 1))
        XCTAssertEqual(weekly.text(in: .traditionalChinese), "最近 7 天準點率 93%（台鐵近一年 93%）")
        XCTAssertEqual(weekly.text(in: .english), "On time, last 7 days: 93% (Taiwan Railway, past year: 93%)")
        let late = try XCTUnwrap(WeeklyPunctuality(records: [day(0, trips: 3, late: 3), day(1, trips: 7, late: 0)], settledDay: 2))
        XCTAssertEqual(late.text(in: .traditionalChinese), "最近 7 天準點率 70%（台鐵近一年 93%）")
        XCTAssertEqual(weekly.companyText(in: .traditionalChinese), "全公司最近 7 天準點率 93%（台鐵近一年 93%）")
        XCTAssertEqual(weekly.companyText(in: .english), "All lines on time, last 7 days: 93% (Taiwan Railway, past year: 93%)")
    }

    func testTaiwanRailwaysFigureIsTheAnalysisOne() throws {
        // tools/tra-delay-analysis/results/final_by_all.csv: 261,820 trips,
        // 92.92 % on time.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/tra-delay-analysis/results/final_by_all.csv")
        let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        let fields = try XCTUnwrap(rows.dropFirst().first).split(separator: ",")
        XCTAssertEqual(Int64(fields[1]), TaiwanRailwayPunctuality.pastYearTrips)
        let hundredths = try XCTUnwrap(Int64(fields[2].replacingOccurrences(of: ".", with: "")))
        XCTAssertEqual((hundredths + 5) / 10, TaiwanRailwayPunctuality.pastYearPermille)
    }

    // MARK: In a world

    func testANewGameLineShowsItOnItsCardOnceItsTripsFinish() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        XCTAssertNil(world.lineWeeklyPunctuality(Self.line), "no day settled yet")
        try world.advance(ticks: 1 + 2 * 1_440)
        let before = world
        let weekly = try XCTUnwrap(world.lineWeeklyPunctuality(Self.line))
        let diagnosis = try XCTUnwrap(world.lineLossDiagnosis(Self.line))
        XCTAssertEqual(diagnosis.weeklyPunctuality, weekly)
        XCTAssertEqual(weekly.trips, diagnosis.measures.trips, "two settled days: the same days as the card")
        XCTAssertEqual(weekly.lateTrips, diagnosis.measures.lateTrips)
        XCTAssertEqual(world, before, "working it out changes nothing")

        world.setRealisticOperation(false)
        XCTAssertNil(world.lineWeeklyPunctuality(Self.line), "not shown without realistic operation")
        XCTAssertNil(world.lineLossDiagnosis(Self.line)?.weeklyPunctuality)
        XCTAssertNil(world.lineWeeklyPunctuality(LineID(rawValue: 99)))
    }

    func testTheCompanysLineAddsUpEveryPassengerLine() throws {
        let world = ScreenshotScene.punctuality.make(in: .traditionalChinese)
        let passengerLines = world.lines.filter { !$0.isFreight }
        XCTAssertGreaterThan(passengerLines.count, 1)
        let weeklies = try passengerLines.map { try XCTUnwrap(world.lineWeeklyPunctuality($0.id), "\($0.name)") }
        let company = try XCTUnwrap(world.companyWeeklyPunctuality())
        XCTAssertEqual(company.trips, weeklies.reduce(0) { $0 + $1.trips })
        XCTAssertEqual(company.lateTrips, weeklies.reduce(0) { $0 + $1.lateTrips })

        var off = world
        off.setRealisticOperation(false)
        XCTAssertNil(off.companyWeeklyPunctuality(), "not shown without realistic operation")
        var noAccounts = world
        noAccounts.setLineAccounts(false)
        XCTAssertNil(noAccounts.companyWeeklyPunctuality())
    }

    func testTheCompanysLineNeedsTenTripsOverAllLinesAndNoneInANewGame() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        XCTAssertNil(world.companyWeeklyPunctuality(), "no day settled yet")
        try world.advance(ticks: 1 + 2 * 1_440)
        XCTAssertEqual(world.companyWeeklyPunctuality(), world.lineWeeklyPunctuality(Self.line), "one line: the same figure")
    }

    func testTheScreenshotSceneShowsItOnEveryPassengerLine() throws {
        let world = ScreenshotScene.punctuality.make(in: .traditionalChinese)
        XCTAssertTrue(world.realisticOperation)
        for line in world.lines where !line.isFreight {
            let weekly = try XCTUnwrap(world.lineLossDiagnosis(line.id)?.weeklyPunctuality, "\(line.name)")
            XCTAssertGreaterThanOrEqual(weekly.trips, WeeklyPunctuality.minimumTrips)
        }
    }
}
