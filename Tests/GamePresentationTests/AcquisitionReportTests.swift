import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 315 §2: what a real branch line bought costs against the same
/// line built by the company itself, and what an ordinary player has by
/// then, printed as Markdown. It asserts nothing and runs only on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     ACQUIRE_REPORT=360 swift test -c release --skip-build \
///       --filter AcquisitionReportTests
///
/// `ACQUIRE_REPORT` is the days to play (1 to 720); `ACQUIRE_ONLY` picks
/// one line (`PINGXI`, `trtc:R_XBT`), `player` or `cities`.
///
/// - **Each line**: a real-world game round the line under simple rules
///   (decision 258), over the app's heights, its land read round each
///   station, real transfers on, $200 million in the bank so neither way
///   runs short. One copy buys the line (`build`, recording it); the other
///   lays the same track, stations and trains and runs the same real
///   timetable without paying for the riders, from the same minute. Both
///   then run without a player.
/// - **An ordinary player**: the shared opening (decision 261, a line to
///   the second town and on day 3 to the third) on the app's real places
///   Taipei and Hsinchu (Neiwan Line's junction), under simple rules, left
///   to run: the cash and the operating profit a day (averaged over the
///   30 days before) on days 180 and 360, against each line's price.
/// - **Each city's opening** (decision 400, 10j-3): a new game on a real
///   place, as the launcher begins it, and every line it sells: what
///   each costs, its land included, and whether the opening's cash and
///   the most it can borrow buy it (A.5's $8 million).
@MainActor
final class AcquisitionReportTests: XCTestCase {
    static let networks = ["PINGXI", "SHENAO", "JIJI", "NEIWAN", "ntdlrt:VB", "trtc:R_XBT", "trtc:G_XBT"]
    static let checkpoints: [Int64] = [1, 2, 7, 30, 180, 360, 720]

    private func requestedDays() throws -> Int64 {
        guard let value = ProcessInfo.processInfo.environment["ACQUIRE_REPORT"] else {
            throw XCTSkip("set ACQUIRE_REPORT=<days> to print the line purchase report")
        }
        return try XCTUnwrap(Int64(value).flatMap { (1...720).contains($0) ? $0 : nil }, "ACQUIRE_REPORT is 1 to 720 days")
    }

    private func wanted(_ name: String) -> Bool {
        ProcessInfo.processInfo.environment["ACQUIRE_ONLY"].map { $0 == name } ?? true
    }

    func testBuyingALineAgainstBuildingIt() throws {
        let days = try requestedDays()
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        var rows = [
            "| Line | Riders a day (real) | Building | Trains | Riders' value | Price | ÷ $3M start | ÷ own build | Trips day 1 bought / own | Operating profit a day, days 30–\(days) | Payback | Cash change by day \(min(days, 360)): bought / own |",
            "| --- | --: | --: | --: | --: | --: | --: | --: | --- | --: | --: | --- |",
        ]
        var trace: [String] = []
        for network in Self.networks where wanted(network) {
            let started = Date()
            let bought = try play(network, recording: true, days: days, data: data)
            let own = try play(network, recording: false, days: days, data: data)
            let price = bought.price, ownCost = price.building + price.trains
            let profit = bought.averageProfit(from: 30)
            let payback = profit > 0 ? "\(price.total.amount / profit) days" : "never"
            let year = min(days, 360)
            rows.append(
                "| \(network) | \(bought.dailyRiders) | \(price.building.moneyText) | \(price.trains.moneyText) | \(price.riders.moneyText) | \(price.total.moneyText) | "
                    + String(format: "%.2f", Double(price.total.amount) / 300_000_000) + " | " + String(format: "%.2f", Double(price.total.amount) / Double(ownCost.amount))
                    + " | \(bought.trips[1] ?? 0) / \(own.trips[1] ?? 0) | \(Money(profit).moneyText) | \(payback) | "
                    + "\(Money(bought.cashChange(by: year)).moneyText) / \(Money(own.cashChange(by: year)).moneyText) |"
            )
            for day in Self.checkpoints where day <= days {
                trace.append("| \(network) | \(day) | \(bought.trips[day] ?? 0) / \(own.trips[day] ?? 0) | \(Money(bought.profits[Int(day) - 1]).moneyText) / \(Money(own.profits[Int(day) - 1]).moneyText) | \(Money(bought.cashChange(by: day)).moneyText) / \(Money(own.cashChange(by: day)).moneyText) |")
            }
            FileHandle.standardError.write(Data("\(rows.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
        }
        print("### Buying a real line against building it (\(days) days)\n\n" + rows.joined(separator: "\n"))
        print("\n| Line | Day | Trips bought / own | Operating profit bought / own | Cash change bought / own |\n| --- | --: | --- | --- | --- |\n" + trace.joined(separator: "\n"))
    }

    func testWhatAnOrdinaryPlayerHas() throws {
        guard wanted("player") else { throw XCTSkip("ACQUIRE_ONLY names a line") }
        let days = try requestedDays()
        let files = RealWorldFiles(folder: CommandLogReplay.root.appendingPathComponent("RailwayGameApp/Resources/RealWorld"))
        var rows = [
            "| Place | Towns | Cash day 180 | Operating profit a day, days 151–180 | Cash day 360 | Operating profit a day, days 331–360 | Trips day 360 |",
            "| --- | --: | --: | --: | --: | --: | --: |",
        ]
        for place in ["tra-taipei", "tra-hsinchu"] {
            let started = Date()
            let game = try HeadlessGame.newGame(map: .place(place), rules: .simple, files: files)
            let towns = game.towns
            var player = PolicyPlayer(world: game.world, policy: towns.count >= 3 ? .thirdTown(towns) : .twoTowns(towns))
            var cash: [Int64: Int64] = [:]
            var profits: [Int64] = []
            for day in 1...days {
                try player.playDay()
                cash[day] = player.world.economy.balance.amount
                profits.append(player.world.accounts.days.last.map(operatingProfit) ?? 0)
            }
            func average(_ range: ClosedRange<Int64>) -> String {
                guard range.upperBound <= days else { return "—" }
                let slice = profits[Int(range.lowerBound - 1)...Int(range.upperBound - 1)]
                return Money(slice.reduce(0, +) / Int64(slice.count)).moneyText
            }
            rows.append(
                "| \(place) | \(towns.count) | \(cash[180].map { Money($0).moneyText } ?? "—") | \(average(151...180)) | "
                    + "\(cash[360].map { Money($0).moneyText } ?? "—") | \(average(331...360)) | \(player.world.lastDayTrips()) |"
            )
            FileHandle.standardError.write(Data("\(rows.last!) (\(Int(Date().timeIntervalSince(started))) s)\n".utf8))
        }
        print("### An ordinary player on a real map (\(days) days, simple rules)\n\n" + rows.joined(separator: "\n"))
    }

    /// The places whose openings A.5 sets a target for, by where the
    /// player points: Taipei, New Taipei (Banqiao and Tamsui), Taoyuan,
    /// Taichung and Kaohsiung's main stations.
    static let cities: [(name: String, latitude: Double, longitude: Double)] = [
        ("Taipei", 25.047882, 121.517219), ("New Taipei, Banqiao", 25.013965, 121.464003), ("New Taipei, Tamsui", 25.167818, 121.445561),
        ("Taoyuan", 24.988726, 121.313777), ("Taichung", 24.137066, 120.686867), ("Kaohsiung", 22.639532, 120.302559),
    ]

    func testWhatEachCityOpeningCanBuy() throws {
        guard wanted("cities") else { throw XCTSkip("ACQUIRE_ONLY names another") }
        _ = try requestedDays()
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let reach = GameWorld.startingBalance + CompanyAccounts.maximumLoan
        var rows = [
            "| Opening | Line | Tier | Riders a day (paid for) | Land | Building | Trains | Riders' value | Price | Within cash and loan (\(reach.moneyText)) |",
            "| --- | --- | --- | --: | --: | --: | --: | --: | --: | --- |",
        ]
        for city in Self.cities {
            let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: city.latitude, longitudeDegrees: city.longitude))
            let world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
                population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
            ))
            let session = GameSession(world: world, language: .english)
            session.population = data.population
            session.places = data.places
            session.water = data.water
            session.heights = data.heights
            session.coverage = data.coverage
            session.railways = data.railways
            var listed = 0
            for line in session.buyableRealLines {
                let offer = session.realLineOffer(for: line)
                listed += 1
                guard let price = offer.price, let acquisition = offer.acquisition else {
                    rows.append("| \(city.name) | \(line.id) | \(line.tier.rawValue) | not offered: \(offer.problem ?? "") | | | | | | |")
                    continue
                }
                rows.append(
                    "| \(city.name) | \(line.id) | \(line.tier.rawValue) | \(acquisition.dailyRiders) | \(price.land.moneyText) | \(price.building.moneyText) | "
                        + "\(price.trains.moneyText) | \(price.riders.moneyText) | \(price.total.moneyText) | \(price.total <= reach ? "yes" : "no") |"
                )
            }
            if listed == 0 { rows.append("| \(city.name) | none | | | | | | | | |") }
        }
        print("### What each city's opening can buy\n\n" + rows.joined(separator: "\n"))
    }

    /// One line's game, bought or built, played `days`.
    private struct Played {
        let price: RealLineAcquisitionPrice
        let dailyRiders: Int64
        let before: Int64
        var cash: [Int64: Int64] = [:]
        var trips: [Int64: Int64] = [:]
        var profits: [Int64] = []

        func averageProfit(from day: Int) -> Int64 {
            let slice = profits.dropFirst(day - 1)
            return slice.isEmpty ? 0 : slice.reduce(0, +) / Int64(slice.count)
        }

        func cashChange(by day: Int64) -> Int64 {
            (cash[day] ?? cash[Int64(profits.count)] ?? before) - before
        }
    }

    private func play(_ network: String, recording: Bool, days: Int64, data: RealWorldData) throws -> Played {
        let railways = try XCTUnwrap(data.railways)
        let runs = try XCTUnwrap(railways.branchRuns[network] ?? railways.metroRuns[network])
        let prefix = String(network.prefix { $0 != ":" })
        let system = railways.branchRuns[network] != nil ? RealBranchLine.tra : prefix == "trtc" ? "mrt" : prefix
        let stations = try runs.stops.map { try BundledRealData.station($0, in: system) }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        var world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 21, height: 1 << 21), balance: Money(20_000_000_000), land: [], rules: .simple)
        world.setLandOnDemand()
        world.setRealTransfers(true)
        try world.mapGround()
        let session = GameSession(world: world, language: .english)
        session.railways = railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == network || $0.id == network }, network)
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, "\(network): \(offer.problem ?? "")")
        let before = world.economy.balance.amount
        let price = try session.build(acquisition, in: &world, recording: recording)
        // The transfer points the session gives the new stations.
        let built = GameSession(world: world, language: .english)
        built.railways = railways
        built.refreshTransfers()
        world = built.world
        var played = Played(price: price, dailyRiders: acquisition.dailyRiders, before: before)
        for day in 1...days {
            try world.advance(ticks: 1_440)
            played.cash[day] = world.economy.balance.amount
            played.trips[day] = world.lastDayTrips()
            played.profits.append(world.accounts.days.last.map(operatingProfit) ?? 0)
        }
        return played
    }
}

/// A day's fares and other income less its running costs (the finance
/// report's operating profit).
private func operatingProfit(_ day: DayAccount) -> Int64 {
    (day.fareRevenue + day.freightRevenue + day.propertyRevenue - day.totalCost - day.propertyCost).amount
}
