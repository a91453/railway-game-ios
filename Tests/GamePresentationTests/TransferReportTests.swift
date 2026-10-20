import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The real network's transfers (decision 298), played for days without a
/// player and printed as Markdown, so ``TransferDemand/tripsPerPoint`` is
/// chosen from what a first line carries and earns rather than guessed. It
/// asserts nothing and runs only on request:
///
///     TRANSFER_REPORT=14 swift test -c release --skip-build \
///       --filter TransferReportTests
///
/// `TRANSFER_REPORT` is the days to play.
@MainActor
final class TransferReportTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func grid<T>(_ name: String, _ make: (Data) throws -> T) -> T {
        do {
            return try make(Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/\(name)")))
        } catch {
            preconditionFailure("\(error)")
        }
    }

    private static let population = grid("taiwan_population.json", PopulationGrid.init(data:))
    private static let places = grid("taiwan_places.json", PlaceGrid.init(data:))

    /// A new game on a real place's first tile, as the app starts one: a
    /// line from its TRA station to the densest town 3 to 8 km from it
    /// (or, with none, the densest), one train of four cars, played with
    /// real transfers off and then on. Prints the transfer trips the
    /// station brings, the riders, the balance and the day the line has
    /// paid back what it cost.
    func testAFirstLineFromARealStation() throws {
        guard let value = ProcessInfo.processInfo.environment["TRANSFER_REPORT"], let days = Int(value), days > 0 else {
            throw XCTSkip("set TRANSFER_REPORT=<days> to print the transfer report")
        }
        let railways = try BundledRealData.railways()
        let ids = ["tra-taipei", "tra-taoyuan", "tra-hsinchu", "tra-taichung", "tra-tainan", "tra-kaohsiung", "tra-keelung", "tra-chiayi", "tra-yilan", "tra-hualien", "tra-taitung"]
        var lines = [
            "### A first line from a real place's TRA station, one train of four cars, \(days) days (\(TransferDemand.tripsPerPoint) trips a point)",
            "",
            "| Place | Systems | Points | Transfer trips | Apart | Cost | Riders day 1 / 7 / \(days): off → on | Balance day \(days): off → on | Paid back: off → on |",
            "| --- | --- | --: | --: | --: | --: | --- | --- | --- |",
        ]
        for id in ids {
            let place = try XCTUnwrap(RealWorldPlace.all.first { $0.id == id })
            let key = RealRailways.stationKey(place.name(in: .traditionalChinese))
            let real = try XCTUnwrap(railways.stations.first { $0.system.id == "tra_sched" && RealRailways.stationKey($0.chinese) == key }, id)
            let layout = try XCTUnwrap(RealWorldExpansion(around: place.anchor))
            let step = layout.ridersStep(population: Self.population, places: Self.places, water: nil)
            var world = GameWorld.newRealWorldExpansionGame(layout, ridersStep: step)
            NewGameOptions().apply(to: &world)
            GameSession.readLand(roundStationsOf: &world, population: Self.population, places: Self.places)
            let station = try BundledRealData.point(real.coordinate, in: world)
            func metres(_ a: PlanPoint, _ b: PlanPoint) -> Double {
                hypot(Double(a.x - b.x), Double(a.y - b.y)) / Double(WorldCoordinate.unitsPerMetre)
            }
            let towns = try XCTUnwrap(PolicyMap.densestTowns(in: world, tile: layout.start), id)
            let town = towns.first { (3_000...8_000).contains(metres($0, station)) } ?? towns[0]

            var results: [(riders: [Int64], balance: Int64, paidBack: Int?)] = []
            var points: Int64 = 0, systems = "", cost: Int64 = 0
            for transfers in [false, true] {
                var start = world
                start.setRealTransfers(transfers)
                let before = start.economy.balance
                start = try newGameLine(through: [station, town], in: start)
                cost = (before - start.economy.balance).amount
                let session = GameSession(world: start, language: .english)
                session.railways = railways
                start = session.world
                if transfers, let first = start.stations.first {
                    points = first.transferPoints
                    systems = session.transferPlace(of: first.id)?.systems.map { $0.name(in: .english) }.joined(separator: ", ") ?? "-"
                }
                var player = try reportPlayer(start)
                try player.advance(ticks: 1)
                var riders: [Int64] = []
                var paidBack: Int?
                for day in 1...days {
                    try player.playDay()
                    riders.append(player.world.lastDayTrips())
                    if paidBack == nil, player.world.economy.balance >= before { paidBack = day }
                }
                results.append((riders, player.world.economy.balance.amount, paidBack))
            }
            func ridersText(_ day: Int) -> String { "\(results[0].riders[day - 1]) → \(results[1].riders[day - 1])" }
            func paid(_ day: Int?) -> String { day.map { "day \($0)" } ?? "not yet" }
            lines.append(
                "| \(place.name(in: .english)) | \(systems) | \(points) | \(points * TransferDemand.tripsPerPoint) | \(String(format: "%.1f", metres(station, town) / 1_000)) km | "
                    + "$\(cost / 100) | \(ridersText(1)) / \(ridersText(min(7, days))) / \(ridersText(days)) | "
                    + "$\(results[0].balance / 100) → $\(results[1].balance / 100) | \(paid(results[0].paidBack)) → \(paid(results[1].paidBack)) |"
            )
        }
        print(lines.joined(separator: "\n"))
    }
}
