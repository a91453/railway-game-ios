import Foundation
import GameCore
import GamePresentation
import XCTest

/// A new game played for weeks without a player, printed day by day as a
/// Markdown table, so a balance change can be measured before and after it
/// instead of worked out by hand (ROADMAP, the 2026-10-07 balance report).
/// It asserts nothing and runs only on request:
///
///     BALANCE_REPORT=60 swift test -c release -Xswiftc -enable-testing \
///       --filter BalanceReportTests
///
/// `BALANCE_REPORT` is the days to play. A release build plays the first
/// line's 60 days in seconds and the demo map's in some four minutes.
final class BalanceReportTests: XCTestCase {
    /// `NewGameBalanceTests`' first line: three stations through the first
    /// town on 448 m of track and one train of four cars, $914,800.
    func testAFirstLine() throws {
        let days = try requestedDays()
        var world = GameWorld.newGame()
        let tile = Int64(1_024)
        let cars = 4
        let platform = Int64(cars) * Train.carLength
        let x = GameWorld.newGameBounds.width / 2 - 16 * tile, y = GameWorld.newGameBounds.height / 2
        let west = try world.buildTrackNode(at: WorldCoordinate(x: x + 2 * tile, y: y))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: x + 30 * tile, y: y))
        let edge = try world.buildTrackEdge(from: west, to: east)
        var stops: [StationID] = []
        for middle in [tile + platform / 2, 14 * tile, 27 * tile - platform / 2] {
            let station = try world.buildStation(named: "S\(stops.count)", at: PlanPoint(x: x + 2 * tile + middle, y: y)).id
            try world.addTrackPlatform(station, on: edge, from: middle - platform / 2, to: middle + platform / 2)
            stops.append(station)
        }
        let line = try world.createLine(named: "Line 1", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        try play(&world, days: days, title: "A first line")
    }

    /// The demo map (decision 78): three lines and four trains, $2,291,200.
    func testTheDemoMap() throws {
        let days = try requestedDays()
        var world = DemoWorld.make(in: .english)
        try play(&world, days: days, title: "The demo map")
    }

    private func requestedDays() throws -> Int {
        guard let value = ProcessInfo.processInfo.environment["BALANCE_REPORT"] else {
            throw XCTSkip("set BALANCE_REPORT=<days> to print the balance report")
        }
        return try XCTUnwrap(Int(value).flatMap { $0 > 0 ? $0 : nil }, "BALANCE_REPORT is a whole number of days")
    }

    /// Plays `days` whole days from the first minute and prints a row at
    /// the end of each: everything the network's stations reach is its
    /// catchment, every station of the world is the network's.
    private func play(_ world: inout GameWorld, days: Int, title: String) throws {
        let stops = world.stations.map(\.id)
        let cost = GameWorld.startingBalance - world.economy.balance
        var lines = [
            "### \(title): built for \(dollars(cost.amount)), \(stops.count) stations",
            "",
            "| Day | Balance | Fares | Operating profit | Recovered | Trips a day | Catchment people | D1 / D2 / D3 / D4 / stock | Fullest D3 | Land value avg / max | Service |",
            "| --: | --: | --: | --: | --: | --: | --: | --- | --: | --- | --- |",
        ]
        try world.advance(ticks: 1)
        for day in 1...days {
            try world.advance(ticks: 1_440)
            lines.append(row(world, day: day, stops: stops, cost: cost))
        }
        print(lines.joined(separator: "\n"))
    }

    private func row(_ world: GameWorld, day: Int, stops: [StationID], cost: Money) -> String {
        let report = world.financeReport(.day).previous
        let trips = stops.reduce(Int64(0)) { $0 + (world.stationDemand(of: $1)?.dailyTrips ?? 0) }
        let points = stops.compactMap { world.station(id: $0)?.location }
        let radius = Land.catchmentRadius
        let catchment = world.land.cells.filter { cell in
            points.contains { point in
                let dx = cell.middle.x - point.x, dy = cell.middle.y - point.y
                return dx * dx + dy * dy < radius * radius
            }
        }
        let people = catchment.reduce(Int64(0)) { $0 + $1.residents + $1.jobs }
        // Existing stock first, then D1 to D4.
        var heights = [0, 0, 0, 0, 0]
        // How full the fullest D3 is, in per cent of its main count: the
        // next D4 is raised from the D3s that are full.
        var fullest = Int64(0)
        for cell in catchment {
            guard let building = world.buildings.building(row: cell.row, column: cell.column) else { continue }
            heights[building.kind == .existingStock ? 0 : building.density.rawValue] += 1
            if building.kind == .city, building.density == .d3 {
                let table = Building.tableCapacity(of: cell.use, .d3)
                let main = cell.use == .residential ? (cell.residents, table.residents) : (cell.jobs, table.jobs)
                if main.1 > 0 {
                    fullest = max(fullest, main.0 * 100 / main.1)
                }
            }
        }
        let values = catchment.compactMap { world.landValue(row: $0.row, column: $0.column)?.value }
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Int64(values.count)
        let service = stops.compactMap { world.townGrowth(of: $0)?.lastService }.min() ?? 0
        let recovered = (world.economy.balance.amount - (GameWorld.startingBalance - cost).amount) * 100 / cost.amount
        return "| \(day) | \(dollars(world.economy.balance.amount)) | \(dollars(report.fareRevenue.amount)) | "
            + "\(dollars(report.operatingProfit.amount)) | \(recovered)% | \(trips) | \(people) | "
            + "\(heights[1]) / \(heights[2]) / \(heights[3]) / \(heights[4]) / \(heights[0]) | \(fullest)% | "
            + "\(dollars(average)) / \(dollars(values.max() ?? 0)) | \(service / 10)% |"
    }

    /// Whole dollars of `cents`.
    private func dollars(_ cents: Int64) -> String {
        "$\(cents / 100)"
    }
}
