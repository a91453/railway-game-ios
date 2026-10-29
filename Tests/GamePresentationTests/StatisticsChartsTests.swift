@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 472: the station panel's groups, a station's rush hours, each
/// line's trend and peak load, and the network's fullest sections ranked.
final class StatisticsChartsTests: XCTestCase {
    // MARK: - The station panel's groups

    func testEverySectionIsInOneGroupAndTheGroupsKeepThePanelsOrder() {
        let parts = StationPanelGroup.allCases.flatMap(\.parts)
        XCTAssertEqual(parts, StationPanelPart.allCases, "the groups, one after another, list every section once in order")
        XCTAssertEqual(StationPanelGroup.allCases.first, .operations, "what a station is opened for comes first")
        XCTAssertEqual(StationPanelGroup.operations.parts.first, .buyLine)
        XCTAssertTrue(StationPanelGroup.operations.parts.contains(.platforms), "removing a platform is with the platforms (#516)")
        XCTAssertEqual(StationPanelGroup.freight.parts, [.freight, .removal], "demolishing stays last")
    }

    func testALessonsFreightYardButtonIsInTheFreightGroup() {
        XCTAssertEqual(StationPanelGroup.holding(.freightYard), .freight)
        XCTAssertNil(StationPanelGroup.holding(.addTrain), "a lines panel button is in no station group")
    }

    func testFoldsAreKeptAsTextAndUnfoldedOnRequest() {
        var folds = StationPanelFolds(stored: "")
        XCTAssertFalse(StationPanelGroup.allCases.contains(where: folds.isFolded), "everything unfolded at first")
        folds.toggle(.area)
        folds.toggle(.riders)
        XCTAssertEqual(folds.stored, "riders,area")
        XCTAssertEqual(StationPanelFolds(stored: "area,unknown,riders"), folds, "an unknown name is left out")
        XCTAssertEqual(StationPanelGroup.allCases.filter(\.isFoldable), [.riders, .area, .freight], "the first group has no heading to fold")
        folds.toggle(.operations)
        XCTAssertFalse(folds.isFolded(.operations))
        XCTAssertFalse(StationPanelFolds(stored: "operations").isFolded(.operations), "an old or hand-made text cannot fold it either")
        folds.unfold(.area)
        XCTAssertFalse(folds.isFolded(.area))
        folds.toggle(.riders)
        XCTAssertEqual(folds.stored, "")
        XCTAssertEqual(StationGroupTitles.all(in: .traditionalChinese), ["營運", "旅客與運量", "周邊與土地", "貨運與拆除"])
    }

    // MARK: - A station's trips by hour

    private static let commuterDay: [Int64] = [
        0, 0, 0, 0, 0, 10, 60, 180, 200, 120, 60, 50,
        55, 50, 50, 60, 90, 150, 190, 120, 60, 30, 10, 0,
    ]

    func testRushHoursAreTheRunsNearTheBusiestHour() {
        XCTAssertEqual(StationFlow.rushHours(of: Self.commuterDay), [7...8, 17...18])
        XCTAssertEqual(StationFlow.rushText(of: Self.commuterDay, in: .english), "Rush 07:00–09:00, 17:00–19:00")
        XCTAssertEqual(StationFlow.rushText(of: Self.commuterDay, in: .traditionalChinese), "尖峰 07:00–09:00、17:00–19:00")

        XCTAssertEqual(StationFlow.rushHours(of: Array(repeating: 0, count: 24)), [], "no trips, no rush")
        XCTAssertEqual(StationFlow.rushHours(of: Array(repeating: 40, count: 24)), [], "an even day has no rush")
        var late = Array(repeating: Int64(1), count: 24)
        late[23] = 9
        XCTAssertEqual(StationFlow.rushText(of: late, in: .english), "Rush 23:00–24:00")
    }

    func testTheHourChartHasABarAnHourAndSaysItsRush() {
        let flow = StationFlow(entries: Self.commuterDay, exits: Array(repeating: 0, count: 24), isShape: false)
        let chart = flow.chart(.entries, in: .english)
        XCTAssertEqual(chart.axis, .people)
        XCTAssertEqual(chart.xLabels.count, 24)
        XCTAssertEqual(chart.xLabels[7], "07:00")
        XCTAssertEqual(chart.series[0].values[8], 200)
        XCTAssertEqual(chart.legendNames, [], "one series: the title names it")
        XCTAssertEqual(chart.summary, "1,545 a day · busiest 08:00, 200 · Rush 07:00–09:00, 17:00–19:00")
        XCTAssertEqual(flow.chart(.exits, in: .traditionalChinese).title, "出站")
        XCTAssertEqual(flow.chart(.exits, in: .english).summary, "0 a day · busiest 00:00, 0")
    }

    // MARK: - A line's trend and load

    private func day(_ index: Int64, riders: Int64, peak: Int64 = 500) -> LineOperatingDay {
        var tally = LineTally()
        tally.boardings = riders
        tally.peakLoad = peak
        return LineOperatingDay(LineDay(day: index, tally: tally))
    }

    private func report(riders: [Int64], today: LineOperatingDay? = nil) -> LineReport {
        let days = riders.enumerated().map { day(Int64($0.offset), riders: $0.element, peak: 870) }
        return LineReport(line: LineID(rawValue: 1), name: "Red", today: today, yesterday: days.last, days: days)
    }

    func testTheTrendComparesTheLastWeekWithTheOneBefore() {
        let up = report(riders: Array(repeating: 100, count: 9) + Array(repeating: 112, count: 7))
        XCTAssertEqual(up.ridersChangePercent, 12)
        XCTAssertEqual(up.trendText(in: .english), "Riders up 12% on the week before")
        XCTAssertEqual(up.trendText(in: .traditionalChinese), "運量比前一週多 12%")

        let down = report(riders: Array(repeating: 300, count: 7) + Array(repeating: 199, count: 7))
        XCTAssertEqual(down.ridersChangePercent, -34, "-33.67 rounds away from zero")
        XCTAssertEqual(down.trendText(in: .traditionalChinese), "運量比前一週少 34%")

        XCTAssertEqual(report(riders: Array(repeating: 50, count: 14)).trendText(in: .english), "Riders level with the week before")
        XCTAssertNil(report(riders: Array(repeating: 50, count: 13)).ridersChangePercent, "two whole weeks are needed")
        XCTAssertNil(report(riders: Array(repeating: 0, count: 7) + Array(repeating: 9, count: 7)).ridersChangePercent, "nobody rode the week before")
    }

    func testTheSparklineNeedsTwoDaysAndTheGaugeFallsBackToToday() {
        XCTAssertEqual(report(riders: [5]).sparkline, [])
        XCTAssertEqual(report(riders: [5, 8, 3]).sparkline, [5, 8, 3])

        let gauge = try? XCTUnwrap(report(riders: [5, 8]).loadGauge)
        XCTAssertEqual(gauge, LineLoadGauge(percent: 87, isYesterday: true))
        XCTAssertEqual(gauge?.fraction ?? 0, 0.87, accuracy: 1e-9)
        XCTAssertEqual(gauge?.text(in: .traditionalChinese), "昨日最滿 87%")

        let first = LineReport(line: LineID(rawValue: 1), name: "Red", today: day(0, riders: 40, peak: 1_234), yesterday: nil, days: [])
        XCTAssertEqual(first.loadGauge, LineLoadGauge(percent: 123, isYesterday: false))
        XCTAssertEqual(first.loadGauge?.fraction, 1, "full at 100%")
        XCTAssertEqual(first.loadGauge?.isOverload, true)
        XCTAssertEqual(first.loadGauge?.text(in: .english), "Fullest train today 123%")
        XCTAssertNil(LineReport(line: LineID(rawValue: 1), name: "Red", today: nil, yesterday: nil, days: []).loadGauge)
    }

    // MARK: - The network's fullest sections

    private func section(_ index: Int, _ from: Int, _ to: Int, hour: Int = 8, percent: Int?) -> NetworkFlowReport.SectionRow {
        NetworkFlowReport.SectionRow(
            section: index, from: StationID(rawValue: from), to: StationID(rawValue: to), lines: [], hour: hour,
            load: Int64(percent ?? 10) * 10, capacity: percent == nil ? 0 : 1_000, percent: percent, dailyLoad: 1_000)
    }

    func testTheRankingLeavesOutSectionsWithoutTrainsAndTellsTwinsApart() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        let report = NetworkFlowReport(hasPlan: true, sections: [
            section(0, 1, 2, percent: nil),
            section(1, 1, 2, hour: 7, percent: 130),
            section(2, 1, 2, hour: 17, percent: 90),
            section(3, 2, 3, percent: 60),
        ])
        XCTAssertEqual(report.rankedSections.map(\.section), [1, 2, 3])
        let chart = report.rankingChart(in: world, language: .english)
        XCTAssertEqual(chart.axis, .percent)
        XCTAssertEqual(chart.xLabels, ["Alpha → Beta", "Alpha → Beta (17:00)", "Beta → Gamma"])
        XCTAssertEqual(chart.series[0].values, [130, 90, 60])
        XCTAssertEqual(chart.valueText(130), "130%")
        XCTAssertEqual(chart.summary, "1 of the 3 fullest sections carry more than their seats")
        XCTAssertEqual(NetworkFlowReport(sections: [section(3, 2, 3, percent: 60)]).rankingChart(in: world, language: .traditionalChinese).summary,
                       "最擠的區間滿載 60%")
        XCTAssertEqual(NetworkFlowReport().rankingChart(in: world, language: .english).xLabels, [])
    }
}

/// The groups' titles, for the test above to read in one line.
private enum StationGroupTitles {
    static func all(in language: DisplayLanguage) -> [String] {
        StationPanelGroup.allCases.map { $0.title(in: language) }
    }
}
