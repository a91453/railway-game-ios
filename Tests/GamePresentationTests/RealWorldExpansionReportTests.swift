import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Buying a real place's map (decision 167), played for weeks without a
/// player and printed as Markdown, so the share of the first tile's trips
/// that unlocks the next tile (``RealWorldExpansion/ridersPerRootTrip``) is chosen
/// from what a line carries instead of worked out by hand. It asserts
/// nothing and runs only on request:
///
///     BALANCE_REPORT=40 swift test -c release -Xswiftc -enable-testing \
///       --filter RealWorldExpansionReportTests
///
/// `BALANCE_REPORT` is the days to play. `BALANCE_MODE_SHIFT=realistic`
/// lets riders switch to scooters and cars up to each place's county share
/// (decision 332).
@MainActor
final class RealWorldExpansionReportTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let population: PopulationGrid = {
        do {
            return try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private static let places: PlaceGrid = {
        do {
            return try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json")))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private static let placeNames: PlaceNames = {
        do {
            return try PlaceNames(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_place_names.json")))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// The shares of the first tile's trips a day that might unlock the
    /// next tile, as numerators over denominators.
    private static let shares: [(Int64, Int64)] = [(1, 10), (1, 6), (1, 4), (1, 3), (1, 2)]
    /// The multiples of the square root of those trips that might.
    private static let roots: [Double] = [80, 100, 120, 150]

    /// A line between the two densest towns of a real place's first tile
    /// (3 to 8 km apart), one train of four cars, played without buying
    /// anything: what it carries, and the day each share of the tile's trips
    /// would have unlocked the second tile.
    func testBuyingARealMap() throws {
        guard let value = ProcessInfo.processInfo.environment["BALANCE_REPORT"], let days = Int(value), days > 0 else {
            throw XCTSkip("set BALANCE_REPORT=<days> to print the balance report")
        }
        let ids = ["tra-taipei", "tra-taoyuan", "tra-hsinchu", "tra-taichung", "tra-tainan", "tra-kaohsiung", "tra-keelung", "tra-chiayi", "tra-yilan", "tra-hualien", "tra-taitung"]
        var lines = [
            "### Buying a real place's map: a line between its two densest towns, one train of four cars, \(days) days, nothing bought",
            "",
            "| Place | Tile residents | Trips a day at most | Towns (residents within 800 m) | Apart | Cost | Riders: day 1 / 5 / 10 / 20 / \(days) | Best day | Balance: day 10 / 20 / \(days) | Step | Next tile | Riders unlock it | Cash for it (+ $1M) | Bought |",
            "| --- | --: | --: | --- | --: | --: | --- | --: | --- | --: | --: | --: | --: | --: |",
        ]
        var unlocks = [
            "",
            "### The day each share of the tile's trips a day would have unlocked the second tile",
            "",
            "| Place | " + (Self.shares.map { "\($0.0)/\($0.1)" } + Self.roots.map { "\(Int($0)) √trips" }).joined(separator: " | ") + " |",
            "| --- | " + (Self.shares.map { _ in "--:" } + Self.roots.map { _ in "--:" }).joined(separator: " | ") + " |",
        ]
        var shared: [PlayReport] = []
        for id in ids {
            let place = try XCTUnwrap(RealWorldPlace.all.first { $0.id == id })
            let layout = try XCTUnwrap(RealWorldExpansion(around: place.anchor))
            let step = layout.ridersStep(population: Self.population, places: Self.places, water: nil)
            var world = GameWorld.newRealWorldExpansionGame(layout, ridersStep: step)
            GameSession.readLand(roundStationsOf: &world, population: Self.population, places: Self.places)
            let residents = world.land.cells.reduce(0) { $0 + $1.residents }
            let trips = residents * StationDemand.tripsPerHundredResidents / 100
            let towns = try XCTUnwrap(PolicyMap.densestTowns(in: world, tile: layout.start))
            let sites = (towns[0], towns[1])
            let apart = hypot(Double(sites.0.x - sites.1.x), Double(sites.0.y - sites.1.y)) / 64 / 1_000
            let catchments = [sites.0, sites.1].map { world.land.totals(within: Land.catchmentRadius, of: $0).residents }
            let before = world.economy.balance
            world = try newGameLine(through: [sites.0, sites.1], in: world)
            // Decision 332: the realistic rule stops at the county's share,
            // as a player's new game there does.
            if world.modeShift?.rule == .realistic {
                try world.setModeShift(ModeShift.realistic(cap: ModeShiftCounties.cap(at: place.anchor, in: Self.placeNames)))
            }
            let cost = before - world.economy.balance
            // Decision 261: the days played by the shared player.
            var player = try reportPlayer(world)
            try player.advance(ticks: 1)
            var riders: [Int64] = []
            var best: [Int64] = []
            var balances: [Int64] = []
            var top: Int64 = 0
            var affordable: Int?
            var unlocked: Int?
            let price = try XCTUnwrap(player.world.mapExpansion).nextPrice
            for day in 1...days {
                try player.playDay()
                world = player.world
                let yesterday = world.lastDayTrips()
                riders.append(yesterday)
                top = max(top, yesterday)
                best.append(top)
                balances.append(world.economy.balance.amount)
                // The next tile's price and $1,000,000 to spare.
                if affordable == nil, world.economy.balance >= price + 100_000_000 {
                    affordable = day
                }
                if unlocked == nil, top >= step {
                    unlocked = day
                }
            }
            func rider(_ day: Int) -> String { day <= days ? "\(riders[day - 1])" : "-" }
            func balance(_ day: Int) -> String { day <= days ? dollars(balances[day - 1]) : "-" }
            lines.append(
                "| \(place.name(in: .english)) | \(residents) | \(trips) | \(catchments.map(String.init).joined(separator: " / ")) | "
                    + "\(String(format: "%.1f", apart)) km | \(dollars(cost.amount)) | \(rider(1)) / \(rider(5)) / \(rider(10)) / \(rider(20)) / \(riders.last ?? 0) | \(top) | "
                    + "\(balance(10)) / \(balance(20)) / \(balances.last.map(dollars) ?? "-") | \(step) | \(dollars(price.amount)) | "
                    + "\(unlocked.map { "day \($0)" } ?? "not yet") | \(affordable.map { "day \($0)" } ?? "not yet") | "
                    + "\(unlocked.flatMap { u in affordable.map { "day \(max(u, $0))" } } ?? "not yet") |"
            )
            var row = "| \(place.name(in: .english)) |"
            var steps = Self.shares.map { trips * $0.0 / $0.1 }
            steps += Self.roots.map { Int64($0 * Double(trips).squareRoot()) }
            for raw in steps {
                let step = min(max(raw / 1_000 * 1_000, RealWorldExpansion.minimumRidersStep), MapExpansion.standardRidersStep)
                let day = best.firstIndex { $0 >= step }.map { "day \($0 + 1)" } ?? "never"
                row += " \(day) (\(step)) |"
            }
            unlocks.append(row)
            shared.append(PlayReport(label: place.name(in: .english), player: player))
        }
        print((lines + unlocks).joined(separator: "\n"))
        // Decision 261: the measures every report shares.
        print("\n" + PlayReport.table(shared, title: "Buying a real place's map"))
    }

    /// What owning several tiles of a dense place costs (decision 167):
    /// Taipei, bought a tile at a time (the nearest to the first, free play
    /// with the money for it), each tile's land read in as the game does it.
    /// Prints, after 1, 2, 4 and 8 tiles, how long the buy took, the land,
    /// the save's size and the time to write and read it, and how long a
    /// game day takes with a line of two stations running.
    func testTheCostOfSeveralDenseTiles() throws {
        guard ProcessInfo.processInfo.environment["BALANCE_REPORT"] != nil else {
            throw XCTSkip("set BALANCE_REPORT=<days> to print the balance report")
        }
        let layout = try XCTUnwrap(RealWorldExpansion(around: try XCTUnwrap(RealWorldPlace.all.first { $0.id == "tra-taipei" }).anchor))
        var world = GameWorld.newRealWorldExpansionGame(layout, ridersStep: MapExpansion.standardRidersStep, balance: 1_000_000_000_000)
        world.setEconomyMode(.free)
        GameSession.readLand(roundStationsOf: &world, population: Self.population, places: Self.places)
        let pair = try XCTUnwrap(PolicyMap.densestTowns(in: world, tile: layout.start))
        let towns = (pair[0], pair[1])
        world = try newGameLine(through: [towns.0, towns.1], in: world)
        var lines = [
            "### Several dense tiles: Taipei bought tile by tile (free play), a line of two stations running",
            "",
            "| Tiles | Buy + read (ms) | Land cells | Buildings | Save (MB) | Encode (ms) | Decode (ms) | A game day (ms) |",
            "| --: | --: | --: | --: | --: | --: | --: | --: |",
        ]
        var buyMs = 0.0
        for count in 1...8 {
            if count > 1 {
                let start = Date()
                let first = world.stations[0].point
                func distance(_ tile: MapTile) -> Int64 {
                    let area = world.mapArea(of: tile)
                    let dx = (area.minX + area.maxX) / 2 - first.x, dy = (area.minY + area.maxY) / 2 - first.y
                    return dx * dx + dy * dy
                }
                let tile = try XCTUnwrap(world.mapTilesForSale().min { distance($0) < distance($1) })
                try world.buyMapTile(tile)
                GameSession.readLand(roundStationsOf: &world, population: Self.population, places: Self.places)
                buyMs = Date().timeIntervalSince(start) * 1_000
            }
            guard [1, 2, 4, 8].contains(count) else { continue }
            let encodeStart = Date()
            let data = try JSONEncoder().encode(SavedGame(world: world))
            let encodeMs = Date().timeIntervalSince(encodeStart) * 1_000
            let decodeStart = Date()
            _ = try JSONDecoder().decode(SavedGame.self, from: data)
            let decodeMs = Date().timeIntervalSince(decodeStart) * 1_000
            let dayStart = Date()
            try world.advance(ticks: 1_440)
            let dayMs = Date().timeIntervalSince(dayStart) * 1_000
            lines.append(
                "| \(count) | \(Int(buyMs)) | \(world.land.cells.count) | \(world.buildings.all.count) | "
                    + "\(String(format: "%.1f", Double(data.count) / 1_000_000)) | \(Int(encodeMs)) | \(Int(decodeMs)) | \(Int(dayMs)) |"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    private func dollars(_ cents: Int64) -> String {
        "$\(cents / 100)"
    }
}
