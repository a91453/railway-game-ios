@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 478: the three load charts. A line's riders between each pair
/// of its stops both ways, a section's riders hour by hour against what
/// its trains carry, and a line's fullest train each day against its
/// seats. The numbers are read from what the game already keeps (the
/// passenger plan, the line accounts), never stored.
final class LoadChartTests: XCTestCase {
    private func playedDemo() throws -> GameWorld {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 60)
        return world
    }

    // MARK: - Riders between stops

    func testALineWithoutAPlanSaysToRunTheGame() throws {
        let world = DemoWorld.make(in: .english)
        let line = try XCTUnwrap(world.lines.first { !$0.isFreight })
        let profile = LineLoadProfile(world: world, line: line.id)
        XCTAssertFalse(profile.hasPlan)
        XCTAssertTrue(profile.sections.isEmpty)
        XCTAssertEqual(profile.summaryText(in: .english), "Run the game a minute to see the riders.")
        XCTAssertNil(LineLoadProfile(world: world, line: LineID(rawValue: 9_999)).sections.first)
    }

    func testEachSectionCarriesTheLinesOwnLegsBothWays() throws {
        let world = try playedDemo()
        let flows = try XCTUnwrap(world.plannedPassengerLegFlows())
        let line = try XCTUnwrap(world.lines.first { line in !line.isFreight && !line.isRing && flows.contains { $0.line == line.id } })
        let profile = LineLoadProfile(world: world, line: line.id)
        XCTAssertTrue(profile.hasPlan)
        XCTAssertEqual(profile.sections.count, line.stops.count - 1)
        let names = line.stops.map { world.station(id: $0)?.name ?? "" }
        XCTAssertEqual(profile.sections.map(\.from), Array(names.dropLast()))
        XCTAssertEqual(profile.sections.map(\.to), Array(names.dropFirst()))
        XCTAssertEqual(profile.outboundName, "To \(names.last!)")
        XCTAssertEqual(profile.inboundName, "To \(names.first!)")

        // Worked out again by hand: a leg from stop i to stop j rides every
        // section between them, its whole day's riders on each.
        var outbound = Array(repeating: Int64(0), count: line.stops.count - 1)
        var inbound = outbound
        for flow in flows where flow.line == line.id {
            guard let i = line.stops.firstIndex(of: flow.from), let j = line.stops.firstIndex(of: flow.to) else { continue }
            let day = flow.hourly.reduce(0, +)
            for k in min(i, j)..<max(i, j) {
                if flow.direction == .outbound { outbound[k] += day } else { inbound[k] += day }
            }
        }
        XCTAssertEqual(profile.sections.map(\.outbound), outbound)
        XCTAssertEqual(profile.sections.map(\.inbound), inbound)
        XCTAssertGreaterThan(outbound.reduce(0, +) + inbound.reduce(0, +), 0)

        let chart = profile.chart(in: .english)
        XCTAssertEqual(chart.axis, .people)
        XCTAssertEqual(chart.legendNames, [profile.outboundName, profile.inboundName])
        XCTAssertEqual(chart.xLabels, profile.sections.map { "\($0.from) – \($0.to)" })
        XCTAssertEqual(chart.series[0].values, outbound.map { Double($0) })
        XCTAssertEqual(chart.series[1].values, inbound.map { Double($0) })
        XCTAssertEqual(chart.series.map(\.mark), [.bars, .bars])
    }

    private func profile() -> LineLoadProfile {
        func peak(_ hour: Int, _ load: Int64, _ capacity: Int64) -> LineLoadProfile.Peak {
            LineLoadProfile.Peak(hour: hour, load: load, capacity: capacity)
        }
        return LineLoadProfile(line: LineID(rawValue: 1), hasPlan: true, outboundName: "To Gamma", inboundName: "To Alpha", sections: [
            .init(index: 0, from: "Alpha", to: "Beta", outbound: 1_200, inbound: 900,
                  outboundPeak: peak(8, 240, 300), inboundPeak: peak(18, 150, 300)),
            .init(index: 1, from: "Beta", to: "Gamma", outbound: 3_100, inbound: 2_000,
                  outboundPeak: peak(8, 348, 300), inboundPeak: peak(17, 200, 300)),
        ])
    }

    func testTheSummaryNamesTheBusiestSectionAndItsFullestHour() {
        let profile = profile()
        XCTAssertEqual(profile.busiest?.index, 1)
        XCTAssertEqual(profile.summaryText(in: .english),
                       "Busiest: Beta → Gamma, 3,100 riders a day · fullest 08:00–09:00 at 116% of the seats")
        XCTAssertEqual(profile.summaryText(in: .traditionalChinese),
                       "最多人：Beta → Gamma，一天 3,100 人 · 最擠 08:00–09:00，座位的 116%")
        XCTAssertEqual(profile.sectionText(profile.sections[0], in: .english),
                       "Alpha – Beta · To Gamma 1,200 a day, fullest 08:00 80% · To Alpha 900 a day, fullest 18:00 50%")
    }

    func testNobodyRidingSaysSo() {
        let empty = LineLoadProfile(line: LineID(rawValue: 1), hasPlan: true, outboundName: "To B", inboundName: "To A", sections: [
            .init(index: 0, from: "A", to: "B", outbound: 0, inbound: 0, outboundPeak: nil, inboundPeak: nil),
        ])
        XCTAssertNil(empty.busiest)
        XCTAssertEqual(empty.summaryText(in: .english), "Nobody rides this line yet.")
    }

    func testTheFullestHourIsTheLargestShareOfTheSeats() {
        var loads = Array(repeating: Int64(0), count: 24)
        var capacities = Array(repeating: Int64(400), count: 24)
        loads[8] = 380; loads[18] = 300; capacities[18] = 200
        XCTAssertEqual(LineLoadProfile.Peak.fullest(loads: loads, capacities: capacities)?.hour, 18)
        loads[22] = 10; capacities[22] = 0
        XCTAssertEqual(LineLoadProfile.Peak.fullest(loads: loads, capacities: capacities)?.hour, 22, "riders with no trains come first")
        XCTAssertNil(LineLoadProfile.Peak.fullest(loads: Array(repeating: 0, count: 24), capacities: capacities))
    }

    // MARK: - A section hour by hour

    func testASectionKeepsItsHoursAndChartsRidersAgainstSeats() throws {
        let world = try playedDemo()
        let flow = SectionFlow(world: world)
        let report = NetworkFlowReport(world: world, flow: flow)
        let row = try XCTUnwrap(report.sections.first)
        XCTAssertEqual(row.loads, flow.sections[row.section].loads)
        XCTAssertEqual(row.capacities, flow.sections[row.section].capacities)

        let chart = row.hourlyChart(title: "Alpha → Beta", in: .english)
        XCTAssertEqual(chart.axis, .people)
        XCTAssertEqual(chart.xLabels.count, 24)
        XCTAssertEqual(chart.xLabels.first, "00:00")
        XCTAssertEqual(chart.legendNames, ["Riders", "Seats"])
        XCTAssertEqual(chart.series.map(\.mark), [.bars, .dashedLine])
        XCTAssertEqual(chart.series[0].values, row.loads.map { Double($0) })
        XCTAssertEqual(chart.series[1].values, row.capacities.map { Double($0) })
    }

    func testTheHourlySummaryCountsTheHoursOverTheSeats() {
        var loads = Array(repeating: Int64(0), count: 24)
        let capacities = Array(repeating: Int64(300), count: 24)
        loads[7] = 320; loads[8] = 348; loads[9] = 200; loads[18] = 310
        let row = NetworkFlowReport.SectionRow(
            section: 0, from: StationID(rawValue: 1), to: StationID(rawValue: 2), lines: [], hour: 8,
            load: 348, capacity: 300, percent: 116, dailyLoad: loads.reduce(0, +), loads: loads, capacities: capacities)
        XCTAssertEqual(row.hourlySummary(in: .english), "Fullest 08:00–09:00: 348 riders, 116% of the seats · over the seats 3 hours")
        XCTAssertEqual(row.hourlySummary(in: .traditionalChinese), "最擠 08:00–09:00：348 人，座位的 116% · 超過座位 3 個小時")
        XCTAssertEqual(row.hourText(8, in: .english), "08:00–09:00 · 348 riders · 300 seats · 116%")
    }

    // MARK: - The fullest train each day

    func testThePeakLoadChartIsInPercentAgainstTheSeats() {
        func day(_ day: Int64, peak: Int64) -> LineOperatingDay {
            var tally = LineTally()
            tally.peakLoad = peak
            return LineOperatingDay(LineDay(day: day, tally: tally))
        }
        let report = LineReport(line: LineID(rawValue: 1), name: "Red", today: nil, yesterday: nil,
                                days: [day(10, peak: 800), day(11, peak: 1_320), day(12, peak: 1_050)])
        let chart = report.peakLoadChart(in: .english)
        XCTAssertEqual(chart.axis, .percent)
        XCTAssertEqual(chart.yTitle, "Percent of the seats")
        XCTAssertEqual(chart.valueText(116), "116%")
        XCTAssertEqual(chart.series.first?.values, [80, 132, 105])
        XCTAssertTrue(chart.valueRange.contains(100), "the seats' rule is always in view")
        XCTAssertEqual(chart.summary, "Fullest Day 12 at 132% · over the seats 2 of 3 days")
        XCTAssertEqual(report.peakLoadChart(in: .traditionalChinese).summary, "最擠第 12 天，132% · 3 天中 2 天超過座位")

        let calm = LineReport(line: LineID(rawValue: 1), name: "Red", today: nil, yesterday: nil, days: [day(10, peak: 400)])
        XCTAssertEqual(calm.peakLoadChart(in: .english).summary, "Fullest Day 11 at 40% · never over the seats")
        XCTAssertEqual(calm.peakLoadChart(in: .english).valueRange.upperBound, 100)
    }
}
