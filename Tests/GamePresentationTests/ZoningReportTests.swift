@testable import GameCore
import Foundation
import GamePresentation
import XCTest

/// Decision 514: how long the zones of a typical start take to fill, and
/// how many of them never would (too far from a station, or a use the city
/// does not want). It asserts nothing and runs only on request:
///
///     BALANCE_REPORT=30 swift test -c release --skip-build \
///       --filter ZoningReportTests
///
/// The start is decision 137's first line that pays (the first town to the
/// second, seed 1, two stations, one train of four cars), zoned before the
/// first day in each of the ways below, then played `BALANCE_REPORT` days.
final class ZoningReportTests: XCTestCase {
    /// A rectangle of `side` cells a side round each place, zoned `zone`.
    private struct Plan {
        let title: String
        let zone: Zone
        let side: Int
        /// Where, from the line's stations: each station, or a point this
        /// far east of the first one (metres).
        let eastOfFirst: Int64?
    }

    private let plans = [
        Plan(title: "Homes, 9 × 9 cells (576 m) round each station", zone: .residential, side: 9, eastOfFirst: nil),
        Plan(title: "Homes, 25 × 25 cells (1.6 km) round each station", zone: .residential, side: 25, eastOfFirst: nil),
        Plan(title: "Homes, 9 × 9 cells 1.5 km from the first station", zone: .residential, side: 9, eastOfFirst: 1_500),
        Plan(title: "Shops, 25 × 25 cells round each station", zone: .commercial, side: 25, eastOfFirst: nil),
        Plan(title: "Offices, 25 × 25 cells round each station", zone: .office, side: 25, eastOfFirst: nil),
        Plan(title: "Schools and public offices, 25 × 25 cells round each station", zone: .civic, side: 25, eastOfFirst: nil),
    ]

    func testZonesOfAFirstLine() throws {
        guard let value = ProcessInfo.processInfo.environment["BALANCE_REPORT"] else {
            throw XCTSkip("set BALANCE_REPORT=<days> to print the zoning report")
        }
        let days = try XCTUnwrap(Int(value).flatMap { $0 > 0 ? $0 : nil })
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var start = try newGameLine(through: [towns[0], towns[1]])
        // Decision 139: `BALANCE_NO_CITY_DEMAND=1` measures the zones without
        // the city's valves.
        if ProcessInfo.processInfo.environment["BALANCE_NO_CITY_DEMAND"] != nil {
            start.setCityDemand(false)
        }
        var summary = [
            "| Plan | Zoned empty | Builds / waits / too far / not wanted (day 0) | Same, day 1 | First built | Fifth built | Built by day \(days) |",
            "| --- | --: | --- | --- | --: | --: | --: |",
        ]
        for plan in plans {
            var world = start
            let length = Land.cellLength
            let places = plan.eastOfFirst.map { [PlanPoint(x: world.stations[0].location.x + $0 * WorldCoordinate.unitsPerMetre, y: world.stations[0].location.y)] }
                ?? world.stations.map(\.location)
            var zoned: Set<CellPosition> = []
            for place in places {
                let row = Int(place.y / length), column = Int(place.x / length), half = plan.side / 2
                let rows = max(0, row - half)...min(Land.rows(in: world.bounds) - 1, row + half)
                let columns = max(0, column - half)...min(Land.columns(in: world.bounds) - 1, column + half)
                try world.setZone(plan.zone, rows: rows, columns: columns)
            }
            for cell in world.zones.cells where world.land.cell(row: cell.row, column: cell.column) == nil {
                zoned.insert(cell.position)
            }
            func outlook(_ world: GameWorld) -> String {
                let counts = ZoningOutlook(world: world).counts(in: world)
                return ZoneOutlook.allCases.map { "\(counts[$0] ?? 0)" }.joined(separator: " / ")
            }
            let dayZero = outlook(world)
            var player = try reportPlayer(world)
            try player.advance(ticks: 1)
            var first: Int?, fifth: Int?, dayOne = ""
            var rows = [
                "### \(plan.title)", "",
                "| Day | Zoned cells built | Builds / waits / too far / not wanted | Homes / shops / work demand |",
                "| --: | --: | --- | --- |",
            ]
            for day in 1...days {
                try player.playDay()
                let world = player.world
                let built = zoned.filter { world.land.cell(row: $0.row, column: $0.column) != nil }.count
                if day == 1 { dayOne = outlook(world) }
                if built >= 1, first == nil { first = day }
                if built >= 5, fifth == nil { fifth = day }
                let levels = world.cityDemandLevels
                rows.append("| \(day) | \(built) | \(outlook(world)) | \(levels.homes) / \(levels.shops) / \(levels.work) |")
            }
            let built = zoned.filter { player.world.land.cell(row: $0.row, column: $0.column) != nil }.count
            print(rows.joined(separator: "\n") + "\n")
            summary.append(
                "| \(plan.title) | \(zoned.count) | \(dayZero) | \(dayOne) | \(first.map(String.init) ?? "—") | \(fifth.map(String.init) ?? "—") | \(built) |"
            )
        }
        print("### Zoning on a first line\n\n" + summary.joined(separator: "\n"))
    }
}
