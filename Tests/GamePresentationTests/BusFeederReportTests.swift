import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 400, 10i-2: what a feeder bus adds, measured on the new game's
/// line between two towns (`BalanceReportTests.testALineBetweenTwoTowns`).
/// Not an assertion: with `BUS_REPORT=<days>` it plays the line with and
/// without a bus route at the first station and prints a Markdown table of
/// the station's trips, the company's fare trips and the route's takings.
final class BusFeederReportTests: XCTestCase {
    func testAFeederAtTheFirstStation() throws {
        guard let days = ProcessInfo.processInfo.environment["BUS_REPORT"].flatMap(Int.init), days > 0 else {
            throw XCTSkip("BUS_REPORT=<days> runs the report")
        }
        let buses = ProcessInfo.processInfo.environment["BUS_COUNT"].flatMap(Int.init) ?? 2
        let headway = ProcessInfo.processInfo.environment["BUS_HEADWAY"].flatMap(Int64.init) ?? 10
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let plain = try newGameLine(through: [towns[0], towns[1]])
        var fed = plain
        let station = try XCTUnwrap(fed.stations.first)
        // A road straight out of the station, away from the other town,
        // 2 km long, laid as a base map's road would be, and three stops
        // on it 1.0, 1.4 and 1.8 km out, past the station's 800 m.
        let away = (x: station.location.x - towns[1].x, y: station.location.y - towns[1].y)
        let length = FixedPoint.roundedSquareRoot(away.x * away.x + away.y * away.y)
        func point(metres: Int64) -> PlanPoint {
            let units = metres * WorldCoordinate.unitsPerMetre
            return PlanPoint(x: station.location.x + away.x * units / length, y: station.location.y + away.y * units / length)
        }
        func cell(_ point: PlanPoint) -> CellPosition {
            CellPosition(row: Int(point.y / Land.cellLength), column: Int(point.x / Land.cellLength))
        }
        let cells = Set(stride(from: Int64(0), through: 2_000, by: 16).map { cell(point(metres: $0)) })
        let blocks = Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })
        try fed.setRoads(Array(cells), in: Array(blocks))
        let stops = [1_800, 1_400, 1_000].map { cell(point(metres: $0)) }
        let route = try fed.createBusRoute(to: station.id, stops: stops, service: .every(minutes: headway), buses: buses)

        var rows = ["| Day | Station trips (no bus) | Station trips (bus) | Fare trips (no bus) | Fare trips (bus) | Bus riders | Bus fares | Bus cost | Bus net |",
                    "| --: | --: | --: | --: | --: | --: | --: | --: | --: |"]
        var without = try reportPlayer(plain), with = try reportPlayer(fed)
        try without.advance(ticks: 1)
        try with.advance(ticks: 1)
        var totals = (plain: Int64(0), fed: Int64(0), riders: Int64(0), net: Int64(0))
        for day in 1...days {
            try without.playDay()
            try with.playDay()
            let plainTrips = without.world.financeReport(.day).previous.fareTrips
            let fedTrips = with.world.financeReport(.day).previous.fareTrips
            let bus = with.world.busRoute(id: route.id)?.days.last
            totals.plain += plainTrips
            totals.fed += fedTrips
            totals.riders += bus?.riders ?? 0
            totals.net += (bus?.fares.amount ?? 0) - (bus?.cost.amount ?? 0)
            if day <= 3 || day % 10 == 0 || day == days {
                let demand = { (world: GameWorld) in world.passengers.first { $0.station == station.id }?.demand?.dailyTrips ?? 0 }
                rows.append("| \(day) | \(demand(without.world)) | \(demand(with.world)) | \(plainTrips) | \(fedTrips) | \(bus?.riders ?? 0) | "
                    + "\(dollars(bus?.fares.amount ?? 0)) | \(dollars(bus?.cost.amount ?? 0)) | \(dollars((bus?.fares.amount ?? 0) - (bus?.cost.amount ?? 0))) |")
            }
        }
        let route0 = try XCTUnwrap(with.world.busRoute(id: route.id))
        print("### A feeder at the first station (\(buses) buses, every \(headway) min; \(route0.metres) m, headway \(route0.headway ?? 0), "
            + "feeder \(route0.feederTrips) trips at \(route0.feederMinutes) min)\n" + rows.joined(separator: "\n"))
        print("\nOver \(days) days: fare trips \(totals.plain) → \(totals.fed) (+\(totals.plain > 0 ? (totals.fed - totals.plain) * 1_000 / totals.plain : 0)‰), "
            + "bus riders \(totals.riders), bus net \(dollars(totals.net))")
    }

    private func dollars(_ cents: Int64) -> String {
        "$\(cents / 100)"
    }
}
