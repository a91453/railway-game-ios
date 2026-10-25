import Foundation
@testable import GameCore
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
    /// The first line (``firstLine()``).
    func testAFirstLine() throws {
        let days = try requestedDays()
        var world = try firstLine()
        try play(&world, days: days, title: "A first line")
    }

    /// Decision 137's first line that pays: the first town to the second
    /// (seed 1, 5.4 km), one train of four cars.
    func testALineBetweenTwoTowns() throws {
        let days = try requestedDays()
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try play(&world, days: days, title: "A line between two towns")
    }

    /// Release check before a build is shipped: a new game with every
    /// switch on (door crowding, flexible dispatch, line accounts, rolling-
    /// stock economics, tourism, ...) and two lines, played `BALANCE_REPORT`
    /// days. Every day the lines' records must add up to the company's
    /// books, the world must save and load back equal every 30 days, and
    /// nothing may run negative; a row per 30 days is printed.
    func testAYearWithEverySwitchOn() throws {
        let days = try requestedDays()
        let bounds = GameWorld.newGameBounds
        let towns = Land.townCentres(seed: 1, in: bounds)
        let first = towns[0], second = towns[1]
        let edgeX = second.x > first.x ? 40_000 : bounds.width - 40_000
        let edge = PlanPoint(x: edgeX, y: first.y + (first.y - second.y) * (edgeX - first.x) / (first.x - second.x))
        var world = try newGameLine(through: [first, second])
        let shifted = PlanPoint(x: first.x, y: first.y + 6_144)
        world = try newGameLine(through: [shifted, PlanPoint(x: edge.x, y: edge.y + 6_144)], in: world)
        XCTAssertEqual(world.lines.count, 2)
        Self.applyRealisticOperationSwitch(&world)
        let encoder = JSONEncoder()
        var rows = ["| Day | Balance | Fares | Operating profit | Tourism and shops | Lines' fares | Lines' costs | Trains | Sights |", "| --: | --: | --: | --: | --: | --: | --: | --: | --: |"]
        var player = try reportPlayer(world)
        try player.advance(ticks: 1)
        var lowest = player.world.economy.balance.amount
        for day in 1...days {
            try player.playDay()
            world = player.world
            let report = world.financeReport(.day).previous
            let tallies = world.lines.compactMap { world.lineYesterday($0.id) }
            let lineFares = tallies.reduce(Int64(0)) { $0 + $1.fareRevenue.amount }
            let lineCosts = tallies.reduce(Int64(0)) { $0 + $1.totalCost.amount }
            XCTAssertEqual(lineFares, report.fareRevenue.amount, "day \(day): the lines' fares are the company's")
            XCTAssertEqual(lineCosts, report.totalCost.amount, "day \(day): the lines' costs are the company's")
            XCTAssertGreaterThanOrEqual(report.fareRevenue.amount, 0)
            lowest = min(lowest, world.economy.balance.amount)
            if day % 30 == 0 || day == days {
                let data = try encoder.encode(world)
                XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world, "day \(day): the world loads back equal")
                rows.append("| \(day) | \(dollars(world.economy.balance.amount)) | \(dollars(report.fareRevenue.amount)) | \(dollars(report.operatingProfit.amount)) | "
                    + "\(dollars(report.propertyRevenue.amount - report.propertyCost.amount)) | \(dollars(lineFares)) | \(dollars(lineCosts)) | \(world.trains.count) | \(world.tourism?.attractions.count ?? 0) |")
            }
        }
        print("### A year with every switch on (lowest balance \(dollars(lowest)))\n" + rows.joined(separator: "\n"))
        print("\n" + PlayReport.table([PlayReport(label: "Two lines", player: player)], title: "A year with every switch on"))
    }

    /// The first line with the company's buildings (decision 130): once the
    /// line has paid for itself, on day 30, two office blocks by its middle
    /// station: A beside it, buying out the city's D4 buildings in its
    /// way, and B on the empty land at the town's edge 768 m north, inside
    /// the station's 800 m. Then the day's balance, what they earn, how full
    /// they are and what selling each would bring, and at the end both are
    /// sold. Measures what a sale does to the cash against keeping them.
    func testAFirstLineWithBuildingsToSell() throws {
        let days = try requestedDays()
        var world = try firstLine()
        let tile = Int64(1_024)
        let middle = world.stations[1].location
        let sites = [PlanPoint(x: middle.x, y: middle.y + 3 * tile), PlanPoint(x: middle.x, y: middle.y - 48 * tile)]
        var bought: [PlacedBuildingID] = []
        var lines = [
            "### A first line with two office blocks bought on day 30: A buying out, B on empty land",
            "",
            "| Day | Balance | Property a day | A full | A price | A book | B full | B price | B book | Balance if sold |",
            "| --: | --: | --: | --: | --: | --: | --: | --: | --: | --: |",
        ]
        try world.advance(ticks: 1)
        for day in 1...days {
            try world.advance(ticks: 1_440)
            if day == 30 {
                for site in sites {
                    let quote = try XCTUnwrap(world.placedBuildingQuote(.office, at: site))
                    bought.append(try world.placeBuilding(.office, at: site).id)
                    lines.append(
                        "| \(day) | bought for \(dollars(quote.total.amount)): building \(dollars(quote.building.amount)), "
                            + "land \(dollars(quote.land.amount)), buy-out \(dollars(quote.buyOut.amount)) | | | | | | | | |"
                    )
                }
            }
            guard !bought.isEmpty else { continue }
            let report = world.financeReport(.day).previous
            let quotes = bought.compactMap { world.saleQuote(of: $0) }
            let columns = quotes.map { quote in
                "\(quote.occupants * 100 / max(1, quote.capacity))% | \(dollars(quote.price.amount)) | \(dollars(quote.bookValue.amount))"
            }
            let price = quotes.reduce(Money.zero) { $0 + $1.price }
            lines.append(
                "| \(day) | \(dollars(world.economy.balance.amount)) | \(dollars((report.propertyRevenue - report.propertyCost).amount)) | "
                    + columns.joined(separator: " | ") + " | \(dollars((world.economy.balance + price).amount)) |"
            )
        }
        let before = world.economy.balance
        for id in bought {
            try world.sellPlacedBuilding(id)
        }
        let sold = world.financeReport(.day).current
        lines.append("")
        lines.append(
            "Sold on day \(days): \(dollars((world.economy.balance - before).amount)) in, "
                + "realized \(dollars(sold.realizedGain.amount)), the balance \(dollars(world.economy.balance.amount))."
        )
        print(lines.joined(separator: "\n"))
    }

    /// Decision 173's subsidiaries: once the first line has paid for itself,
    /// on day 30, a department store, a hotel and an amusement park beside
    /// its middle station (the station's 800 m), each where the land is
    /// free. Then each day's customers and profit of each, its year's profit
    /// and what selling it would bring, and the days it takes to pay back
    /// what it cost. The aim: a store well placed pays back in one and a
    /// half to three years (540 to 1,080 days).
    func testAFirstLineWithSubsidiaries() throws {
        let days = try requestedDays()
        var world = try firstLine()
        let tile = Int64(1_024)
        let middle = world.stations[1].location
        let sites: [(PlacedBuildingKind, PlanPoint)] = [
            (.departmentStore, PlanPoint(x: middle.x, y: middle.y + 3 * tile)),
            (.hotel, PlanPoint(x: middle.x + 6 * tile, y: middle.y + 3 * tile)),
            (.amusementPark, PlanPoint(x: middle.x - 8 * tile, y: middle.y + 5 * tile)),
        ]
        var bought: [PlacedBuildingID] = []
        var lines = [
            "### A first line with a department store, a hotel and an amusement park bought on day 30",
            "",
            "| Day | Balance | Store customers / profit a day | Hotel customers / profit a day | Park customers / profit a day | Store price | Store payback days |",
            "| --: | --: | --: | --: | --: | --: | --: |",
        ]
        try world.advance(ticks: 1)
        for day in 1...days {
            try world.advance(ticks: 1_440)
            if day == 30 {
                // A first line cannot yet pay $7.3 million for a store: the
                // cash is topped up so the measure is of the trade alone.
                world.economy.earn(Money(3_000_000_000))
                for (kind, site) in sites {
                    let quote = try XCTUnwrap(world.placedBuildingQuote(kind, at: site))
                    do {
                        bought.append(try world.placeBuilding(kind, at: site).id)
                        lines.append("| \(day) | \(kind) bought for \(dollars(quote.total.amount)) | | | | | |")
                    } catch {
                        lines.append("| \(day) | \(kind) could not be placed: \(error) | | | | | |")
                    }
                }
            }
            guard !bought.isEmpty else { continue }
            let buildings = bought.compactMap { world.placedBuilding(id: $0) }
            let columns = buildings.map { building -> String in
                let result = world.subsidiaryDay(of: building, onDay: Int64(day))
                return "\(result.customers) / \(dollars((result.sales - result.cost).amount))"
            }
            let store = buildings.first
            let profit = store.map { world.subsidiaryDay(of: $0, onDay: Int64(day)) }.map { ($0.sales - $0.cost).amount } ?? 0
            let payback = (store?.cost.amount ?? 0) / max(1, profit)
            let price = store.flatMap { world.saleQuote(of: $0.id)?.price.amount } ?? 0
            lines.append(
                "| \(day) | \(dollars(world.economy.balance.amount)) | " + columns.joined(separator: " | ")
                    + " | \(dollars(price)) | \(payback) |"
            )
        }
        for id in bought {
            guard let building = world.placedBuilding(id: id) else { continue }
            lines.append(
                "\(building.kind): cost \(dollars(building.cost.amount)), booked \(dollars(building.books.totalProfit.amount)) since opening, "
                    + "last 12 months \(dollars(building.books.trailingProfit.amount))"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// Decision 174: the first line with a 4-star town 47 m from its last
    /// station, whose shop is built to level 2 on day 10, against the same
    /// line without it: the tourists' fares, the shop's takings and what they
    /// do to the cash (the tourists come from the map's edge and the busiest
    /// stations, and all of them ride the line). Printed as a table.
    func testAFirstLineWithASight() throws {
        let days = try requestedDays()
        var plain = try firstLine()
        plain.setTourism(nil)
        var sight = plain
        let station = try XCTUnwrap(sight.stations.last)
        sight.setTourism([Attraction(
            id: AttractionID(rawValue: 1), name: "Sight", englishName: "Sight",
            point: PlanPoint(x: station.point.x + 3_000, y: station.point.y), kind: .town, baseStars: 400
        )])
        var lines = [
            "### A first line with a 4-star town beside its last station (shop level 2 on day 10)",
            "",
            "| Day | Balance without | Balance with | Difference | Tourists | Shop takings | Fares without | Fares with |",
            "| --: | --: | --: | --: | --: | --: | --: | --: |",
        ]
        try plain.advance(ticks: 1)
        try sight.advance(ticks: 1)
        for day in 1...days {
            try plain.advance(ticks: 1_440)
            try sight.advance(ticks: 1_440)
            if day == 10 {
                try sight.investInSouvenirShop(of: AttractionID(rawValue: 1))
                try sight.investInSouvenirShop(of: AttractionID(rawValue: 1))
            }
            let without = plain.financeReport(.day).previous, with = sight.financeReport(.day).previous
            let tourists = sight.attraction(id: AttractionID(rawValue: 1))?.yesterday ?? 0
            lines.append(
                "| \(day) | \(dollars(plain.economy.balance.amount)) | \(dollars(sight.economy.balance.amount)) | "
                    + "\(dollars((sight.economy.balance - plain.economy.balance).amount)) | \(tourists) | "
                    + "\(dollars((with.propertyRevenue - with.propertyCost).amount)) | \(dollars(without.fareRevenue.amount)) | \(dollars(with.fareRevenue.amount)) |"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// Decision 324's day pass: the first line with a 4-star town beside
    /// its last station and a 3-star mountain beside its middle one, the
    /// pass on sale from the first day at each price, against the same line
    /// selling none. The passes sold, what they brought against the fares
    /// their buyers would have paid, the extra rides, the cash; then an
    /// amusement park beside the last station (bought on day 1, the cash
    /// topped up in both worlds) with and without a pass at $15.
    func testADayPassAtEachPrice() throws {
        let days = try requestedDays()
        func sights() throws -> GameWorld {
            var world = try firstLine()
            let middle = try XCTUnwrap(world.stations.dropFirst().first), last = try XCTUnwrap(world.stations.last)
            world.setTourism([
                Attraction(id: AttractionID(rawValue: 1), name: "Town", englishName: "Town",
                           point: PlanPoint(x: last.point.x + 3_000, y: last.point.y), kind: .town, baseStars: 400),
                Attraction(id: AttractionID(rawValue: 2), name: "Hill", englishName: "Hill",
                           point: PlanPoint(x: middle.point.x, y: middle.point.y + 3_000), kind: .mountain, baseStars: 300),
            ])
            return world
        }
        var lines = [
            "### A first line with two sights: a day pass at each price, from day 1, \(days) days",
            "",
            "| Price | Sold a day | Net a day (sales less their fares) | Extra rides a day | Fares a day | Balance | Against no pass |",
            "| --: | --: | --: | --: | --: | --: | --: |",
        ]
        var plain = try sights()
        try plain.advance(ticks: 1)
        for _ in 1...days { try plain.advance(ticks: 1_440) }
        let plainFares = plain.accounts.days.reduce(Int64(0)) { $0 + $1.fareRevenue.amount }
        lines.append("| none | 0 | $0 | 0 | \(dollars(plainFares / Int64(days))) | \(dollars(plain.economy.balance.amount)) | $0 |")
        for price in [500, 1_000, 1_200, 1_500, 1_800, 2_000, 2_500, 3_000] as [Int64] {
            var world = try sights()
            try world.setDayPass(Money(price))
            try world.advance(ticks: 1)
            var sold: Int64 = 0, net: Int64 = 0, rides: Int64 = 0
            for day in 1...days {
                try world.advance(ticks: 1_440)
                let passes = world.dayPassDay(onDay: Int64(day) - 1)
                sold += passes.sold
                net += passes.net.amount
                rides += passes.rides
            }
            let fares = world.accounts.days.reduce(Int64(0)) { $0 + $1.fareRevenue.amount }
            let n = Int64(days)
            lines.append(
                "| \(dollars(price)) | \(sold / n) | \(dollars(net / n)) | \(rides / n) | \(dollars(fares / n)) | "
                    + "\(dollars(world.economy.balance.amount)) | \(dollars((world.economy.balance - plain.economy.balance).amount)) |"
            )
        }
        lines += ["", "| Park beside the town | Customers a day (mean) | Profit a day (mean) | Payback days | Balance |", "| --- | --: | --: | --: | --: |"]
        for price in [nil, Money(1_500)] {
            var world = try sights()
            if let price { try world.setDayPass(price) }
            try world.advance(ticks: 1)
            world.economy.earn(Money(3_000_000_000))
            let last = try XCTUnwrap(world.stations.last)
            let park = try world.placeBuilding(.amusementPark, at: PlanPoint(x: last.point.x + 6_000, y: last.point.y + 8_000)).id
            var customers: Int64 = 0, profit: Int64 = 0
            for day in 1...days {
                try world.advance(ticks: 1_440)
                let building = try XCTUnwrap(world.placedBuilding(id: park))
                let result = world.subsidiaryDay(of: building, onDay: Int64(day) - 1)
                customers += result.customers
                profit += (result.sales - result.cost).amount
            }
            let n = Int64(days)
            let cost = try XCTUnwrap(world.placedBuilding(id: park)).cost.amount
            let payback = profit > 0 ? cost * n / profit : 0
            lines.append("| \(price.map { "pass at \(dollars($0.amount))" } ?? "no pass") | \(customers / n) | \(dollars(profit / n)) | \(payback) | \(dollars(world.economy.balance.amount)) |")
        }
        print(lines.joined(separator: "\n"))
    }

    /// Decision 286's sightseeing train: the first line beside a 4-star
    /// town, its one train of four coaches the Blue Train, against the same
    /// line run by the R100 Chu-Kuang (the same performance and seats, no
    /// sightseeing). The Blue Train's half star: the tourists, the fares and
    /// the cash. No shop, so the difference is the train's alone.
    func testASightseeingTrainAtASight() throws {
        let days = try requestedDays()
        var worlds = try [TrainType.r100ChuKuang, .blueTrain].map { type in
            var world = try firstLine(type: type)
            let station = try XCTUnwrap(world.stations.last)
            world.setTourism([Attraction(
                id: AttractionID(rawValue: 1), name: "Sight", englishName: "Sight",
                point: PlanPoint(x: station.point.x + 3_000, y: station.point.y), kind: .town, baseStars: 400
            )])
            try world.advance(ticks: 1)
            return world
        }
        var lines = [
            "### A first line beside a 4-star town: R100 Chu-Kuang against the Blue Train (four coaches)",
            "",
            "| Day | Balance Chu-Kuang | Balance Blue | Difference | Tourists Chu-Kuang | Tourists Blue | Fares Chu-Kuang | Fares Blue |",
            "| --: | --: | --: | --: | --: | --: | --: | --: |",
        ]
        for day in 1...days {
            for index in worlds.indices { try worlds[index].advance(ticks: 1_440) }
            let plain = worlds[0], blue = worlds[1]
            let tourists = worlds.map { $0.attraction(id: AttractionID(rawValue: 1))?.yesterday ?? 0 }
            lines.append(
                "| \(day) | \(dollars(plain.economy.balance.amount)) | \(dollars(blue.economy.balance.amount)) | "
                    + "\(dollars((blue.economy.balance - plain.economy.balance).amount)) | \(tourists[0]) | \(tourists[1]) | "
                    + "\(dollars(plain.financeReport(.day).previous.fareRevenue.amount)) | \(dollars(blue.financeReport(.day).previous.fareRevenue.amount)) |"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// Decision 286, later: the Ming-Ri's whole star against the Hai-Feng's
    /// half, beside a sight of 2, 3, 4 and 4.5 stars, with the E500
    /// Chu-Kuang (the Ming-Ri's locomotive, no star) as the line without a
    /// sightseeing train: the mean tourists and fares a day, and the cash
    /// on the last day, each set four cars. Decision 286, later (third):
    /// and the Formosa Star's three quarters, against the Ming-Ri too, and
    /// a sight of 4.25 stars, where the Ming-Ri's last quarter is lost.
    /// Decision 286, later (fourth): and the Midsummer Formosa, against
    /// the best of the others, and a sight of 2.5 stars.
    func testTheMingRiAtASight() throws {
        let days = try requestedDays()
        var lines = [
            "### A first line beside a sight: E500 Chu-Kuang, Hai-Feng, Ming-Ri, Formosa Star and Midsummer Formosa (four cars), \(days) days",
            "",
            "| Sight | Type | Tourists a day | Fares a day | Balance | Against the Chu-Kuang | Against the Hai-Feng | Against the Ming-Ri | Against the best other |",
            "| --: | --- | --: | --: | --: | --: | --: | --: | --: |",
        ]
        for stars in [200, 250, 300, 350, 400, 425, 450] {
            var balances: [Int64] = []
            for type in [TrainType.e500ChuKuang, .haiFeng, .mingRi, .formosaStar, .midsummerFormosa] {
                var world = try firstLine(type: type)
                let station = try XCTUnwrap(world.stations.last)
                world.setTourism([Attraction(
                    id: AttractionID(rawValue: 1), name: "Sight", englishName: "Sight",
                    point: PlanPoint(x: station.point.x + 3_000, y: station.point.y), kind: .town, baseStars: stars
                )])
                try world.advance(ticks: 1)
                var tourists: Int64 = 0, fares: Int64 = 0
                for _ in 1...days {
                    try world.advance(ticks: 1_440)
                    tourists += world.attraction(id: AttractionID(rawValue: 1))?.yesterday ?? 0
                    fares += world.financeReport(.day).previous.fareRevenue.amount
                }
                let balance = world.economy.balance.amount
                balances.append(balance)
                lines.append(
                    "| \(StationMasterAdvice.starsText(stars)) | \(type.rawValue) | \(tourists / Int64(days)) | \(dollars(fares / Int64(days))) | "
                        + "\(dollars(balance)) | \(dollars(balance - balances[0])) | \(balances.count > 1 ? dollars(balance - balances[1]) : "—") | "
                        + "\(balances.count > 3 ? dollars(balance - balances[2]) : "—") | "
                        + "\(balances.count > 4 ? dollars(balance - balances.dropLast().max()!) : "—") |"
                )
            }
        }
        print(lines.joined(separator: "\n"))
    }

    /// Decision 174's hotels: a hotel built on day 10 beside a sight, whose
    /// guests are 80 per mille of its tourists, for a sight of 3, 4 and 4.5
    /// stars before it (a hotel adds a quarter star). The hotel's customers,
    /// profit a day and the days to pay back what it cost, and the cash
    /// against the same line without the hotel. The aim: 2 to 4 years
    /// (720 to 1,440 days) for a good sight, no snowball.
    func testAHotelBesideASight() throws {
        let days = try requestedDays()
        var lines = [
            "### A hotel beside a sight on the first line (built on day 10)",
            "",
            "| Sight stars | Hotel cost | Tourists a day (mean) | Guests a day (mean) | Profit a day (mean) | Payback days | Balance with hotel | without |",
            "| --: | --: | --: | --: | --: | --: | --: | --: |",
        ]
        for stars in [300, 400, 450] {
            var base = try firstLine()
            let station = try XCTUnwrap(base.stations.last)
            base.setTourism([Attraction(
                id: AttractionID(rawValue: 1), name: "Sight", englishName: "Sight",
                point: PlanPoint(x: station.point.x + 3_000, y: station.point.y), kind: .town, baseStars: stars
            )])
            var with = base
            var hotel: PlacedBuildingID?
            try base.advance(ticks: 1)
            try with.advance(ticks: 1)
            var guests: Int64 = 0, profit: Int64 = 0, tourists: Int64 = 0, counted: Int64 = 0
            for day in 1...days {
                try base.advance(ticks: 1_440)
                try with.advance(ticks: 1_440)
                if day == 10 {
                    // A first line cannot yet pay for a hotel: the cash is topped
                    // up (in both worlds) so the measure is of the trade alone.
                    with.economy.earn(Money(3_000_000_000))
                    base.economy.earn(Money(3_000_000_000))
                    hotel = try with.placeBuilding(.hotel, at: PlanPoint(x: station.point.x + 3_000, y: station.point.y - 6_000)).id
                }
                if day > 10, let id = hotel, let building = with.placedBuilding(id: id) {
                    let result = with.subsidiaryDay(of: building, onDay: Int64(day) - 1)
                    guests += result.customers
                    profit += (result.sales - result.cost).amount
                    tourists += with.attraction(id: AttractionID(rawValue: 1))?.yesterday ?? 0
                    counted += 1
                }
            }
            let building = try XCTUnwrap(hotel.flatMap { with.placedBuilding(id: $0) })
            let mean = max(1, counted)
            let payback = profit > 0 ? building.cost.amount * mean / profit : 0
            lines.append(
                "| \(Double(stars) / 100) | \(dollars(building.cost.amount)) | \(tourists / mean) | \(guests / mean) | \(dollars(profit / mean)) | \(payback) | "
                    + "\(dollars(with.economy.balance.amount)) | \(dollars(base.economy.balance.amount)) |"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// Decision 361's temple: built on day 10 beside the first line's last
    /// station, with no other sight, a 2-star sight of its own whose
    /// visitors are its customers. Its visitors, profit a day and the days
    /// to pay back what it cost, against the hotel's aim of 2 to 4 years.
    /// And its park: what a house beside it lets for a day with and
    /// without a park built next to it on day 10, and the days the
    /// difference takes to pay for the park and its upkeep.
    func testATempleAndAParkOnTheFirstLine() throws {
        let days = try requestedDays()
        var lines = [
            "### A temple and a park beside the first line's last station (built on day 10)",
            "",
            "| Temple cost | Visitors a day (mean) | Profit a day (mean) | Payback days | Balance with temple | without |",
            "| --: | --: | --: | --: | --: | --: |",
        ]
        var base = try firstLine()
        let station = try XCTUnwrap(base.stations.last)
        // A sight far off, so tourism is on but draws nobody here.
        base.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "Far", englishName: "Far", point: PlanPoint(x: 0, y: 0), kind: .town, baseStars: 100)])
        var with = base
        var temple: PlacedBuildingID?
        try base.advance(ticks: 1)
        try with.advance(ticks: 1)
        var visitors: Int64 = 0, profit: Int64 = 0, counted: Int64 = 0
        for day in 1...days {
            try base.advance(ticks: 1_440)
            try with.advance(ticks: 1_440)
            if day == 10 {
                with.economy.earn(Money(3_000_000_000))
                base.economy.earn(Money(3_000_000_000))
                temple = try with.placeBuilding(.temple, at: PlanPoint(x: station.point.x + 3_000, y: station.point.y - 6_000)).id
            }
            if day > 10, let id = temple, let building = with.placedBuilding(id: id) {
                let result = with.subsidiaryDay(of: building, onDay: Int64(day) - 1)
                visitors += result.customers
                profit += (result.sales - result.cost).amount
                counted += 1
            }
        }
        let building = try XCTUnwrap(temple.flatMap { with.placedBuilding(id: $0) })
        let mean = max(1, counted)
        let payback = profit > 0 ? building.cost.amount * mean / profit : 0
        lines.append(
            "| \(dollars(building.cost.amount)) | \(visitors / mean) | \(dollars(profit / mean)) | \(payback) | "
                + "\(dollars(with.economy.balance.amount)) | \(dollars(base.economy.balance.amount)) |"
        )
        lines += [
            "",
            "| Office site (east, north of the station) | Park cost (building + land and buy-outs) | Park upkeep and tax a day | Land value under the office without / with | Office rent a day without / with | Payback days for one office |",
            "| --- | --: | --: | --: | --: | --: |",
        ]
        // Offices (they let at once) on sites no city park reaches yet,
        // each with a park 48 m north of it, measured on the day the
        // first line has run `days` days.
        var measured = 0
        search: for dx in stride(from: Int64(-24_576), through: 24_576, by: 8_192) {
            for dy in stride(from: Int64(-16_384), through: 16_384, by: 8_192) where dx != 0 || dy != 0 {
                var plain = base
                plain.economy.earn(Money(30_000_000_000))
                let site = PlanPoint(x: station.point.x + dx, y: station.point.y + dy)
                guard plain.landValue(row: Land.cellIndex(site.y), column: Land.cellIndex(site.x))?.parkPremium == 0,
                      let office = try? plain.placeBuilding(.office, at: site) else { continue }
                var parked = plain
                guard let park = try? parked.placeBuilding(.park, at: PlanPoint(x: site.x, y: site.y - 3_072)) else { continue }
                let without = plain.dailyRent(of: office).amount
                let withPark = parked.dailyRent(of: try XCTUnwrap(parked.placedBuilding(id: office.id))).amount
                let (upkeep, tax) = parked.dailyUpkeep(of: park)
                let gain = withPark - without - upkeep.amount - tax.amount
                let value = { (world: GameWorld) in world.landValue(row: Land.cellIndex(site.y), column: Land.cellIndex(site.x))?.value ?? 0 }
                lines.append(
                    "| \(dx / 64) m, \(dy / 64) m | \(dollars(park.cost.amount)) (\(dollars(park.buildingCost.amount)) + \(dollars(park.landCost.amount))) | "
                        + "\(dollars(upkeep.amount + tax.amount)) | \(value(plain)) / \(value(parked)) | \(dollars(without)) / \(dollars(withPark)) | "
                        + "\(gain > 0 ? String(park.cost.amount / gain) : "never") |"
                )
                measured += 1
                if measured == 4 { break search }
            }
        }
        print(lines.joined(separator: "\n"))
    }

    /// Decision 361's sequel: a night market beside the first line's last
    /// station, as the temple above, and a school or a hospital there:
    /// what each costs, and how many more people live within 400 m of it,
    /// and on the whole map, than with none.
    func testANightMarketASchoolAndAHospitalOnTheFirstLine() throws {
        let days = try requestedDays()
        var lines = [
            "### A night market, a school and a hospital beside the first line's last station (built on day 10)",
            "",
            "| Building | Cost | Customers a day (mean) | Profit a day (mean) | Payback days | Balance with | without |",
            "| --- | --: | --: | --: | --: | --: | --: |",
        ]
        var base = try firstLine()
        let station = try XCTUnwrap(base.stations.last)
        base.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "Far", englishName: "Far", point: PlanPoint(x: 0, y: 0), kind: .town, baseStars: 100)])
        let kinds: [PlacedBuildingKind] = [.nightMarket, .school, .hospital]
        var worlds = Array(repeating: base, count: kinds.count)
        var ids = [PlacedBuildingID?](repeating: nil, count: kinds.count)
        var customers = [Int64](repeating: 0, count: kinds.count), profit = customers, counted = customers
        let site = PlanPoint(x: station.point.x + 3_000, y: station.point.y - 6_000)
        try base.advance(ticks: 1)
        for index in worlds.indices { try worlds[index].advance(ticks: 1) }
        func nearby(_ world: GameWorld) -> Int64 {
            let reach = LandValueRules.civicReach * LandValueRules.civicReach
            return world.land.cells.reduce(0) { sum, cell in
                let dx = cell.middle.x - site.x, dy = cell.middle.y - site.y
                return dx * dx + dy * dy < reach ? sum + cell.residents : sum
            }
        }
        func everyone(_ world: GameWorld) -> Int64 {
            world.land.cells.reduce(0) { $0 + $1.residents }
        }
        func row(_ day: Int) -> String {
            "| \(day) | \(nearby(base)) / \(everyone(base)) | "
                + worlds.dropFirst().map { "\(nearby($0)) / \(everyone($0))" }.joined(separator: " | ") + " |"
        }
        var growth: [String] = []
        for day in 1...days {
            try base.advance(ticks: 1_440)
            for index in worlds.indices { try worlds[index].advance(ticks: 1_440) }
            if day == 10 {
                base.economy.earn(Money(3_000_000_000))
                for index in worlds.indices {
                    worlds[index].economy.earn(Money(3_000_000_000))
                    ids[index] = try worlds[index].placeBuilding(kinds[index], at: site).id
                }
                growth.append(row(10))
            }
            for index in worlds.indices where day > 10 && kinds[index].isSubsidiary {
                guard let id = ids[index], let building = worlds[index].placedBuilding(id: id) else { continue }
                let result = worlds[index].subsidiaryDay(of: building, onDay: Int64(day) - 1)
                customers[index] += result.customers
                profit[index] += (result.sales - result.cost).amount
                counted[index] += 1
            }
            if day > 10 && (day % 30 == 0 || day == days) {
                growth.append(row(day))
            }
        }
        for index in worlds.indices {
            let building = try XCTUnwrap(ids[index].flatMap { worlds[index].placedBuilding(id: $0) })
            let mean = max(1, counted[index])
            let daily = profit[index] / mean
            let payback = kinds[index].isSubsidiary ? (daily > 0 ? String(building.cost.amount / daily) : "never") : "—"
            lines.append(
                "| \(kinds[index]) | \(dollars(building.cost.amount)) | \(customers[index] / mean) | \(dollars(daily)) | \(payback) | "
                    + "\(dollars(worlds[index].economy.balance.amount)) | \(dollars(base.economy.balance.amount)) |"
            )
        }
        lines += [
            "",
            "| Day | Residents within 400 m / on the map: none | school | hospital |",
            "| --: | --: | --: | --: |",
        ] + growth
        print(lines.joined(separator: "\n"))
    }

    /// Decision 183: the first line with the city's requests, against the
    /// same line without them, sights off in both. Every midnight the
    /// company takes on the best paying offers of riders and residents it
    /// has room for, and does nothing else to meet them: what the
    /// subsidies bring a railway left to itself, so that they do not
    /// snowball the cash.
    func testAFirstLineTakingTheCitysRequests() throws {
        let days = try requestedDays()
        var plain = try firstLine()
        plain.setTourism(nil)
        plain.setCityRequests(seed: nil)
        var asked = plain
        asked.setCityRequests(seed: 1)
        var lines = [
            "### A first line taking the riders and residents requests it can (seed 1)",
            "",
            "| Day | Balance without | Balance with | Difference | Trust | In hand | Offers | Met / missed | Paid so far |",
            "| --: | --: | --: | --: | --: | --- | --- | --: | --: |",
        ]
        try plain.advance(ticks: 1)
        try asked.advance(ticks: 1)
        for day in 1...days {
            // What the town's growth can meet alone: riders and
            // residents, the best paying first; never a station to build,
            // freight or a sight.
            let passive: Set<CityRequestKind> = [.stationRiders, .networkRiders, .population]
            for offer in (asked.cityRequests?.offers ?? []).filter({ passive.contains($0.kind) }).sorted(by: { $0.reward > $1.reward }) {
                try? asked.acceptRequest(offer.id)
            }
            try plain.advance(ticks: 1_440)
            try asked.advance(ticks: 1_440)
            let requests = try XCTUnwrap(asked.cityRequests)
            let met = requests.results.count { $0.succeeded }, missed = requests.results.count { !$0.succeeded }
            lines.append(
                "| \(day) | \(dollars(plain.economy.balance.amount)) | \(dollars(asked.economy.balance.amount)) | "
                    + "\(dollars((asked.economy.balance - plain.economy.balance).amount)) | \(requests.trust) | "
                    + "\(requests.active.map(\.kind.rawValue).joined(separator: ", ")) | \(requests.offers.map(\.kind.rawValue).joined(separator: ", ")) | "
                    + "\(met) / \(missed) | \(dollars(requests.paid.amount)) |"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// `NewGameBalanceTests`' first line: three stations through the first
    /// town on 448 m of track and one train of four cars, $914,800.
    private func firstLine(type: TrainType? = nil) throws -> GameWorld {
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
        if let type { try world.setTrainType(train, to: type) }
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        return world
    }

    /// Decision 137: lines of different lengths on a new game's map of seed
    /// 1, each with one train of four cars, played `BALANCE_REPORT` days:
    /// the first line, a line across the first town, one from it to the
    /// second town, one from it to the map's edge away from the second town
    /// (an outside connection) and one from the second town through the
    /// first to that edge.
    func testLinesByDistance() throws {
        let days = try requestedDays()
        let bounds = GameWorld.newGameBounds
        let towns = Land.townCentres(seed: 1, in: bounds)
        let first = towns[0], second = towns[1]
        let metre = WorldCoordinate.unitsPerMetre
        // On from the second town through the first to 40,000 units inside
        // the map's east or west edge, in a straight line, so a line from
        // the second town through the first runs on without turning.
        let edgeX = second.x > first.x ? 40_000 : bounds.width - 40_000
        let edge = PlanPoint(x: edgeX, y: first.y + (first.y - second.y) * (edgeX - first.x) / (first.x - second.x))
        let layouts: [(String, [PlanPoint])] = [
            ("Across the first town, 1.5 km", [PlanPoint(x: first.x - 750 * metre, y: first.y), first, PlanPoint(x: first.x + 750 * metre, y: first.y)]),
            ("First town to second", [first, second]),
            ("First town to the edge (outside connection)", [first, edge]),
            ("Second town, first town, edge", [second, first, edge]),
        ]
        var lines = [
            "### Lines by distance (seed 1; second town at \((second.x - first.x) / metre) m, \((second.y - first.y) / metre) m)",
            "",
            "| Line | Built for | Trips a day (day 2) | Fares (day 2) | Operating profit (day 2) | Payback | Balance day \(days) |",
            "| --- | --: | --: | --: | --: | --: | --: |",
        ]
        var worlds: [(String, GameWorld)] = [("The first line, 448 m", try firstLine())]
        for (name, points) in layouts {
            worlds.append((name, try newGameLine(through: points)))
        }
        for (name, start) in worlds {
            var world = start
            Self.applyRealisticOperationSwitch(&world)
            let cost = GameWorld.startingBalance - world.economy.balance
            try world.advance(ticks: 1 + 2 * 1_440)
            let report = world.financeReport(.day).previous
            let trips = world.stations.reduce(Int64(0)) { $0 + (world.stationDemand(of: $1.id)?.dailyTrips ?? 0) }
            let payback = report.operatingProfit.amount > 0 ? "\(cost.amount / report.operatingProfit.amount) days" : "never"
            try world.advance(ticks: (days - 2) * 1_440)
            lines.append(
                "| \(name) | \(dollars(cost.amount)) | \(trips) | \(dollars(report.fareRevenue.amount)) | "
                    + "\(dollars(report.operatingProfit.amount)) | \(payback) | \(dollars(world.economy.balance.amount)) |"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// Building materials (decisions 156–158): ``testALineBetweenTwoTowns``
    /// with a freight line between the same two stations, on the same
    /// track, both yards sending building materials (each town's industry
    /// supplies the other's), one train of four cars. Measures whether one
    /// freight line brings the growth back that the materials gate takes.
    func testALineBetweenTwoTownsWithMaterials() throws {
        let days = try requestedDays()
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        let passenger = try XCTUnwrap(world.lines.first)
        let train = try XCTUnwrap(world.train(id: try XCTUnwrap(passenger.assignedTrains.first)))
        for station in world.stations.map(\.id) {
            try world.buildFreightFacility(at: station)
            try world.setFreightProduct(at: station, to: .materials)
        }
        // One track for both: without traffic control the trains pass
        // through each other, as a second track would let them (this
        // measures the materials, not the track).
        try world.setTrafficControl(false)
        // From the far end, so it does not stand on the passenger train.
        let goods = try world.createLine(named: "Materials", stops: passenger.stops.reversed()).id
        try world.setLineServiceWindow(goods, to: .allDay)
        try world.setLineFreight(goods, to: true)
        try world.setLineTrainsInService(goods, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let freight = try world.purchaseTrain(named: "Freight 1").id
        try world.setTrainCars(freight, to: train.cars)
        guard case .onEdge(let traversal, let offset)? = train.position else { throw XCTSkip("the passenger train is off the track") }
        try world.placeTrain(freight, at: .onEdge(TrackTraversal(edge: traversal.edge, direction: .backward), offset: offset))
        try world.setTrainContinuation(freight, along: [], stoppingAt: offset)
        try world.setTrainMovementRate(freight, to: 512)
        try world.assignTrain(freight, to: goods)
        try play(&world, days: days, title: "A line between two towns, with a freight line of building materials")
        print("materials received \(world.freight?.materialsReceived ?? 0) t, used \(world.freight?.materialsUsed ?? 0) t, short last night \(world.freight?.lastShort.map(\.rawValue) ?? [])")
    }

    /// Freight (decision 155): the line of ``testALineBetweenTwoTowns`` (the
    /// first town to the second, 5.4 km, one train of four cars) as a
    /// freight line between two freight yards, with industry round the
    /// first yard of 10, 60 and 150 cells of 29 jobs (the real-world map's
    /// factory cell), next to the passenger line itself. Shows what the
    /// ton-kilometre fare must be for freight to pay about as a passenger
    /// line does, and whether the yard fills or the train does.
    func testAFreightLine() throws {
        let days = try requestedDays()
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var lines = [
            "### A freight line between two towns (seed 1, 5.4 km, one train of four cars), \(days) days",
            "",
            "| Line | Built for | Made a day | Carried a day | Yard 1 / spilled | Freight a day (day 3) | Operating profit (day 3) | Payback | Balance |",
            "| --- | --: | --: | --: | --- | --: | --: | --: | --: |",
        ]
        var worlds: [(String, GameWorld)] = [("Passengers", try newGameLine(through: [towns[0], towns[1]]))]
        for cells in [10, 60, 150] {
            var world = try newGameLine(through: [towns[0], towns[1]])
            let line = try XCTUnwrap(world.lines.first)
            let train = try XCTUnwrap(line.assignedTrains.first)
            try world.unassignTrain(train)
            try world.setLineFreight(line.id, to: true)
            try world.assignTrain(train, to: line.id)
            for station in world.stations.map(\.id) { try world.buildFreightFacility(at: station) }
            // Industry in a block of cells beside the first town's centre,
            // on cells with nobody on them.
            var land = world.land.cells
            let first = try XCTUnwrap(world.stations.first).point
            let row = Int(first.y / Land.cellLength) - 8, column = Int(first.x / Land.cellLength) - 8
            var added = 0, step = 0
            while added < cells {
                let cell = LandCell(row: row + step / 12, column: column + step % 12, use: .industrial, residents: 0, jobs: 29)
                step += 1
                guard !land.contains(where: { $0.row == cell.row && $0.column == cell.column }) else { continue }
                land.append(cell)
                added += 1
            }
            try world.setLand(land)
            worlds.append(("Freight, \(cells) cells of industry", world))
        }
        for (name, start) in worlds {
            var world = start
            let cost = GameWorld.startingBalance - world.economy.balance
            try world.advance(ticks: 1 + 3 * 1_440)
            let report = world.financeReport(.day).previous
            try world.advance(ticks: (days - 3) * 1_440)
            let state = world.freight ?? FreightState()
            let made = state.produced / Int64(days), carried = state.delivered / Int64(days)
            let payback = report.operatingProfit.amount > 0 ? "\(cost.amount / report.operatingProfit.amount) days" : "never"
            lines.append(
                "| \(name) | \(dollars(cost.amount)) | \(made) t | \(carried) t | \(state.facilities.first?.stock ?? 0) t / \(state.spilled) t | "
                    + "\(dollars(report.freightRevenue.amount)) | \(dollars(report.operatingProfit.amount)) | \(payback) | \(dollars(world.economy.balance.amount)) |"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// Buying the map (decision 160): ``testALineBetweenTwoTowns`` on a
    /// blank map of 5 × 5 tiles that owns the middle one, the same towns.
    /// A player who buys the cheapest tile beside the line's towns as soon
    /// as the best day allows it and the cash covers it with $1,000,000 to
    /// spare, and builds nothing more. Prints the day the milestones and
    /// prices are met, the outside connections lost, and how long a day
    /// takes to play on the larger map against the usual one.
    func testBuyingTheMap() throws {
        let days = try requestedDays()
        let towns = Land.townCentres(seed: 1, in: GameWorld.buyingMapBounds)
        var world = try newGameLine(through: [towns[0], towns[1]], in: .newGame(buysMap: true))
        let usualTowns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var usual = try newGameLine(through: [usualTowns[0], usualTowns[1]])
        var lines = [
            "### Buying the map: a line between two towns (seed 1, 5.4 km), one train of four cars, \(days) days",
            "",
            "| Day | Balance | Riders yesterday | Best day | Tiles owned / allowed | Next price | Outside connections | Bought | ms a day (5 × 5 / 1 × 1) |",
            "| --: | --: | --: | --: | --- | --: | --: | --- | --- |",
        ]
        try world.advance(ticks: 1)
        try usual.advance(ticks: 1)
        for day in 1...days {
            let start = Date()
            try world.advance(ticks: 1_440)
            let large = Date().timeIntervalSince(start)
            let usualStart = Date()
            try usual.advance(ticks: 1_440)
            let small = Date().timeIntervalSince(usualStart)
            var bought = ""
            let expansion = try XCTUnwrap(world.mapExpansion)
            if expansion.owned.count < expansion.allowance, world.economy.balance >= expansion.nextPrice + 100_000_000 {
                // The tile beside the line nearest the first town.
                let first = world.stations[0].point
                let tile = world.mapTilesForSale().min { a, b in
                    func distance(_ tile: MapTile) -> Int64 {
                        let area = world.mapArea(of: tile)
                        let dx = (area.minX + area.maxX) / 2 - first.x, dy = (area.minY + area.maxY) / 2 - first.y
                        return dx * dx + dy * dy
                    }
                    return distance(a) < distance(b)
                }
                if let tile {
                    let lost = world.mapTileQuote(tile)?.outsideConnectionsLost.count ?? 0
                    try world.buyMapTile(tile)
                    bought = "(\(tile.row), \(tile.column)), \(lost) outside connections lost"
                }
            }
            let after = try XCTUnwrap(world.mapExpansion)
            lines.append(
                "| \(day) | \(dollars(world.economy.balance.amount)) | \(world.lastDayTrips()) | \(after.bestDayRiders) | "
                    + "\(after.owned.count) / \(after.allowance) | \(dollars(after.nextPrice.amount)) | "
                    + "\(world.stations.count { world.isOutsideConnection($0.id) }) | \(bought) | \(Int(large * 1_000)) / \(Int(small * 1_000)) |"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// The demo map (decision 78): three lines and four trains, $2,291,200.
    func testTheDemoMap() throws {
        let days = try requestedDays()
        var world = DemoWorld.make(in: .english)
        try play(&world, days: days, title: "The demo map")
    }

    /// Decision 181: the company's rank as a game goes on, every 30 days:
    /// the first line, a line between two towns, and the demo map
    /// (`BALANCE_RANK_DEMO=1`, slow), each left to run without a player.
    func testTheCompanyRank() throws {
        let days = try requestedDays()
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var games: [(String, GameWorld)] = [
            ("A first line", try firstLine()),
            ("A line between two towns", try newGameLine(through: [towns[0], towns[1]])),
        ]
        if ProcessInfo.processInfo.environment["BALANCE_RANK_DEMO"] != nil {
            games.append(("The demo map", DemoWorld.make(in: .english)))
        }
        for (title, start) in games {
            var world = start
            var lines = [
                "### The company's rank: \(title), \(days) days, \(world.land.totals.residents) residents on the map",
                "",
                "| Day | Score | Title | " + RankMeasure.allCases.map { $0.title(in: .english) }.joined(separator: " | ") + " |",
                "| --: | --: | --- |" + String(repeating: " --- |", count: RankMeasure.allCases.count),
            ]
            try world.advance(ticks: 1)
            for day in 1...days {
                try world.advance(ticks: 1_440)
                guard day % 30 == 0 || day == days else { continue }
                let rank = CompanyRank(world: world)
                let parts = rank.parts.map { "\($0.value.map($0.measure.valueText) ?? "—") (\($0.points))" }
                lines.append("| \(day) | \(rank.score) | \(rank.title.title(in: .english)) | " + parts.joined(separator: " | ") + " |")
            }
            print(lines.joined(separator: "\n"))
        }
    }

    /// Decision 207: `BALANCE_NO_REALISTIC=1` measures a new game without
    /// realistic operation, as before it.
    private static func applyRealisticOperationSwitch(_ world: inout GameWorld) {
        if ProcessInfo.processInfo.environment["BALANCE_NO_REALISTIC"] != nil {
            world.setRealisticOperation(false)
        }
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
        // Decision 139: `BALANCE_NO_CITY_DEMAND=1` measures the city without
        // its valves, as before it.
        if ProcessInfo.processInfo.environment["BALANCE_NO_CITY_DEMAND"] != nil {
            world.setCityDemand(false)
        }
        // Decision 157: `BALANCE_NO_MATERIALS=1` measures the city without
        // building materials, as before it.
        if ProcessInfo.processInfo.environment["BALANCE_NO_MATERIALS"] != nil {
            world.setBuildingMaterials(false)
        }
        Self.applyRealisticOperationSwitch(&world)
        let stops = world.stations.map(\.id)
        let cost = GameWorld.startingBalance - world.economy.balance
        var lines = [
            "### \(title): built for \(dollars(cost.amount)), \(stops.count) stations",
            "",
            "| Day | Balance | Fares | Operating profit | Tax | Recovered | Trips a day | Catchment people | D1 / D2 / D3 / D4 / stock | Fullest D3 | Land value avg / max | Service | Homes / shops / work demand | City residents / shop jobs / work jobs |",
            "| --: | --: | --: | --: | --: | --: | --: | --: | --- | --: | --- | --- | --- | --- |",
        ]
        // Decision 261: the days played by the shared player.
        var player = try reportPlayer(world)
        try player.advance(ticks: 1)
        for day in 1...days {
            try player.playDay()
            lines.append(row(player.world, day: day, stops: stops, cost: cost))
        }
        world = player.world
        print(lines.joined(separator: "\n"))
        print("\n" + PlayReport.table([PlayReport(label: title, player: player)], title: title))
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
            + "\(dollars(report.operatingProfit.amount)) | \(dollars(report.taxCost.amount)) | \(recovered)% | \(trips) | \(people) | "
            + "\(heights[1]) / \(heights[2]) / \(heights[3]) / \(heights[4]) / \(heights[0]) | \(fullest)% | "
            + "\(dollars(average)) / \(dollars(values.max() ?? 0)) | \(service / 10)% | "
            + "\(world.cityDemandLevels.homes / 10)% / \(world.cityDemandLevels.shops / 10)% / \(world.cityDemandLevels.work / 10)% | "
            + cityTotals(world) + " |"
    }

    /// The city's residents, shop jobs and jobs in work (decision 139).
    private func cityTotals(_ world: GameWorld) -> String {
        var residents: Int64 = 0, shops: Int64 = 0, work: Int64 = 0
        for cell in world.land.cells {
            residents += cell.residents
            switch cell.use {
            case .residential, .commercial, .park: shops += cell.jobs
            case .office, .industrial, .agricultural: work += cell.jobs
            case .civic, .leisure: break
            }
        }
        return "\(residents) / \(shops) / \(work)"
    }

    /// Whole dollars of `cents`.
    private func dollars(_ cents: Int64) -> String {
        "$\(cents / 100)"
    }
}
