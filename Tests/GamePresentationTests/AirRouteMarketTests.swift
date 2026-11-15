import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 759: the air routes for sale, their cards and the map's lines.
@MainActor
final class AirRouteMarketTests: XCTestCase {
    /// The whole of Taiwan, managed, with NT$100 billion: every catalogue
    /// airport but Hong Kong's.
    private func taiwan(balance: Int64 = 10_000_000_000_000) -> GameWorld {
        var world = GameWorld.newGame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds, balance: Money(balance), land: [], rules: .simple)
        world.setEconomyMode(.management)
        return world
    }

    private func listing(_ list: [AirRouteListing], _ airport: String, _ destination: String) throws -> AirRouteListing {
        try XCTUnwrap(list.first { $0.airportName == airport && $0.destination.name == destination }, "\(airport) → \(destination)")
    }

    func testEveryNamedDestinationIsForSaleOnceEitherWay() throws {
        let world = taiwan()
        let list = AirRouteMarket.listings(in: world)
        XCTAssertEqual(Set(list.map(\.id)).count, list.count)
        XCTAssertFalse(list.contains { $0.destination.isRest })
        // Songshan → Penghu is between two airports of the map: listed from
        // Songshan (listed first), not again from Penghu.
        let penghu = try listing(list, "臺北松山機場", "澎湖")
        XCTAssertEqual(penghu.farAirport, world.airports.first { $0.name == "澎湖機場" }?.id)
        XCTAssertNil(penghu.metres)
        XCTAssertNil(list.first { $0.airportName == "澎湖機場" && $0.destination.name == "臺北" })
        // Every pair of the map's airports once.
        let pairs = list.compactMap { item in item.farAirport.map { Set([item.airport, $0]) } }
        XCTAssertEqual(Set(pairs).count, pairs.count)
        // Kinmen lies outside the map: flown its real distance, about 330 km
        // from Songshan.
        let kinmen = try listing(list, "臺北松山機場", "金門")
        XCTAssertNil(kinmen.farAirport)
        XCTAssertTrue((320_000...340_000).contains(try XCTUnwrap(kinmen.metres)), "\(kinmen.metres ?? 0)")
        // Taoyuan to Hong Kong, some 800 km, from both terminals.
        for terminal in ["桃園機場第一航廈", "桃園機場第二航廈"] {
            let hongKong = try listing(list, terminal, "香港")
            XCTAssertTrue((790_000...820_000).contains(try XCTUnwrap(hongKong.metres)), "\(hongKong.metres ?? 0)")
        }
        // Every destination outside the map has a place.
        XCTAssertTrue(list.allSatisfy { $0.farAirport != nil || $0.metres != nil })
        XCTAssertEqual(list.count, world.airports.flatMap { a in a.destinations.filter { !$0.isRest } }.count - pairs.count)
    }

    func testEveryCatalogueDestinationHasAPlace() {
        for (key, names) in AirportCatalog.destinations {
            XCTAssertNotNil(AirportCatalog.coordinate(ofDestination: names.chinese), key)
        }
        XCTAssertEqual(AirportCatalog.destinationName(ofAirport: "臺北松山機場"), "臺北")
        XCTAssertEqual(AirportCatalog.destinationName(ofAirport: "桃園機場第一航廈"), "臺北桃園")
        XCTAssertEqual(AirportCatalog.destinationName(ofAirport: "香港國際機場"), "香港")
    }

    func testTheEstimatesAreGameCoresOfferAndItsAverageDay() throws {
        let world = taiwan()
        let penghu = try listing(AirRouteMarket.listings(in: world), "臺北松山機場", "澎湖")
        let estimates = AirRouteMarket.estimates(penghu, frequency: .real, in: world)
        XCTAssertEqual(estimates.map(\.size), AircraftSize.allCases)
        for estimate in estimates {
            let offer = try XCTUnwrap(estimate.offer)
            XCTAssertEqual(offer, try world.airRouteOffer(from: penghu.airport, to: "澎湖", farAirport: penghu.farAirport, size: estimate.size))
            // 935,711 a year is 2,563 a day; as many as the seats hold.
            XCTAssertEqual(offer.dailyPassengers, 935_711 / 365)
            XCTAssertEqual(estimate.passengers, min(offer.route.dailySeats, 2_563))
            let route = offer.route
            let net = estimate.passengers * route.fare.amount - Int64(route.aircraft) * route.size.dailyUpkeep.amount
                - 2 * route.departures * (route.flightCost.amount + route.size.landingFee.amount)
            XCTAssertEqual(estimate.dailyNet, Money(net))
            if let days = estimate.paybackDays {
                XCTAssertGreaterThan(estimate.dailyNet, .zero)
                XCTAssertGreaterThanOrEqual(days * estimate.dailyNet.amount, offer.price.amount)
                XCTAssertLessThan((days - 1) * estimate.dailyNet.amount, offer.price.amount)
            }
        }
        let suggested = AirRouteMarket.suggestedSize(estimates)
        let best = estimates.compactMap { $0.offer == nil ? nil : $0.dailyNet }.max()
        XCTAssertEqual(estimates.first { $0.size == suggested }?.dailyNet, best)
    }

    func testBuyingThroughTheSessionIsLoggedAndReplayed() throws {
        let session = GameSession(world: taiwan(), language: .traditionalChinese)
        let kinmen = try listing(session.airRouteListings, "臺北松山機場", "金門")
        let before = session.world.economy.balance
        XCTAssertTrue(session.buyAirRoute(kinmen, size: .regional, frequency: .real))
        let route = try XCTUnwrap(session.world.airRoutes.first)
        XCTAssertEqual(route.destination, "金門")
        XCTAssertEqual(route.metres, kinmen.metres)
        let offer = try XCTUnwrap(AirRouteMarket.estimates(kinmen, frequency: .real, in: taiwan()).first { $0.size == .regional }?.offer)
        XCTAssertEqual(before - session.world.economy.balance, offer.price)
        XCTAssertEqual(session.airRouteListings.first { $0.id == kinmen.id }?.bought, route.id)
        XCTAssertFalse(session.buyAirRoute(kinmen, size: .regional, frequency: .real), "bought once")

        // More flights buy the aircraft more; another size a new fleet.
        let more = try XCTUnwrap(session.airRouteChangePrice(route.id, frequency: .extra))
        let balance = session.world.economy.balance
        session.setAirRouteFrequency(route.id, to: .extra)
        XCTAssertEqual(session.world.airRoute(id: route.id)?.frequency, .extra)
        XCTAssertEqual(balance - session.world.economy.balance, more)
        let jets = try XCTUnwrap(session.airRouteChangePrice(route.id, size: .narrowBody))
        let aircraft = try XCTUnwrap(session.world.airRoute(id: route.id)?.aircraft)
        XCTAssertGreaterThan(jets, .zero)
        let paid = session.world.economy.balance
        session.setAirRouteSize(route.id, to: .narrowBody)
        XCTAssertEqual(paid - session.world.economy.balance, jets)
        XCTAssertEqual(Money(AircraftSize.narrowBody.price.amount * Int64(session.world.airRoute(id: route.id)?.aircraft ?? 0)), jets)
        _ = aircraft
        XCTAssertEqual(session.airRouteChangePrice(route.id, size: .narrowBody), .zero, "no change, nothing to buy")

        let card = try XCTUnwrap(session.airRouteCard(route.id))
        XCTAssertEqual(card.title, "臺北松山機場 → 金門")
        XCTAssertEqual(card.frequency, .extra)
        XCTAssertEqual(card.size, .narrowBody)
        XCTAssertTrue(card.rows[0].contains("真實"), card.rows[0])
        XCTAssertTrue(card.rows[2].contains("午夜"), card.rows[2])

        // The log replays to the same world.
        let report = try JSONDecoder().decode(CommandLogReport.self, from: session.commandLogReport(version: "0.9", build: "90", data: [:]).encoded())
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world.airRoutes, session.world.airRoutes)

        session.sellAirRoute(route.id)
        XCTAssertTrue(session.world.airRoutes.isEmpty)
        XCTAssertNil(session.airRouteListings.first { $0.id == kinmen.id }?.bought)
    }

    func testTheMapDrawsARouteToTheOtherAirportOrToTheEdge() throws {
        let session = GameSession(world: taiwan(), language: .traditionalChinese)
        XCTAssertNil(session.airRouteMapOverlay)
        let list = session.airRouteListings
        let penghu = try listing(list, "臺北松山機場", "澎湖"), hongKong = try listing(list, "高雄國際機場", "香港")
        XCTAssertTrue(session.buyAirRoute(penghu, size: .narrowBody, frequency: .real))
        XCTAssertTrue(session.buyAirRoute(hongKong, size: .narrowBody, frequency: .real))
        let overlay = try XCTUnwrap(session.airRouteMapOverlay)
        XCTAssertEqual(overlay.routes.count, 2)
        let songshan = try XCTUnwrap(session.world.airports.first { $0.name == "臺北松山機場" })
        let magong = try XCTUnwrap(session.world.airports.first { $0.name == "澎湖機場" })
        XCTAssertEqual(overlay.routes[0].from, songshan.point)
        XCTAssertEqual(overlay.routes[0].to, magong.point)
        XCTAssertNil(overlay.routes[0].edgeLabel)
        // Hong Kong lies west-south-west of Kaohsiung: the line ends on the
        // map's western edge, named there.
        XCTAssertEqual(overlay.routes[1].edgeLabel, "香港")
        XCTAssertEqual(overlay.routes[1].to.x, 0)
        XCTAssertTrue((0...session.world.bounds.height).contains(overlay.routes[1].to.y))
    }

    func testTheEdgePoint() throws {
        let bounds = try WorldBounds(width: 1_000, height: 500)
        let start = PlanPoint(x: 500, y: 250)
        XCTAssertEqual(GameSession.edgePoint(from: start, toward: (x: -500, y: 250), in: bounds), PlanPoint(x: 0, y: 250))
        XCTAssertEqual(GameSession.edgePoint(from: start, toward: (x: 1_500, y: 1_250), in: bounds), PlanPoint(x: 750, y: 500))
        XCTAssertNil(GameSession.edgePoint(from: start, toward: (x: 900, y: 100), in: bounds), "inside the map")
    }

    /// Decision 759's balance table: each route's best size, its price,
    /// its average day and the days it takes to pay back, printed as
    /// Markdown. It asserts nothing and runs only on request:
    ///
    ///     AIR_ROUTE_REPORT=1 swift test --skip-build --filter AirRouteMarketTests/testThePaybackTable
    func testThePaybackTable() throws {
        guard ProcessInfo.processInfo.environment["AIR_ROUTE_REPORT"] != nil else {
            throw XCTSkip("set AIR_ROUTE_REPORT=1 to print the payback table")
        }
        let world = taiwan()
        var rows = ["| Route | km | Real flights | Size | Aircraft | Price (NT$) | Passengers | Net a day (NT$) | Payback (days) |",
                    "| --- | --: | --: | --- | --: | --: | --: | --: | --: |"]
        for listing in AirRouteMarket.listings(in: world) {
            let estimates = AirRouteMarket.estimates(listing, frequency: .real, in: world)
            let size = AirRouteMarket.suggestedSize(estimates)
            guard let best = estimates.first(where: { $0.size == size }), let offer = best.offer else { continue }
            rows.append("| \(listing.title(in: .traditionalChinese)) | \(offer.route.metres / 1_000) | \(offer.route.realDepartures) | \(size.rawValue) | \(offer.route.aircraft) | \(offer.price.amount / 100) | \(best.passengers) | \(best.dailyNet.amount / 100) | \(best.paybackDays.map(String.init) ?? "—") |")
        }
        print(rows.joined(separator: "\n"))
    }

    /// Decision 762's targets, flown at the real frequency with the size
    /// the panel picks: a route of 1,000 passengers a day or more pays
    /// back in 120 to 240 days; one of 100 to 1,000 with two flights a day
    /// or more in 150 to 360; a smaller one or one with a single flight
    /// in 720 at most, or, with fewer than 15 passengers a day, may lose.
    /// Hualien to Hong Kong is the one outside (778 days): 97 passengers a
    /// day, of whom its one flight a day each way carries 38.
    func testEveryRoutePaysBackInItsBand() throws {
        let world = taiwan()
        var losing: [String] = []
        for listing in AirRouteMarket.listings(in: world) {
            let estimates = AirRouteMarket.estimates(listing, frequency: .real, in: world)
            let best = try XCTUnwrap(estimates.first { $0.size == AirRouteMarket.suggestedSize(estimates) })
            let offer = try XCTUnwrap(best.offer)
            let title = listing.title(in: .traditionalChinese)
            let daily = offer.dailyPassengers
            guard let days = best.paybackDays else {
                XCTAssertLessThan(daily, 15, title)
                losing.append(title)
                continue
            }
            if daily >= 1_000 {
                XCTAssertTrue((120...240).contains(days), "\(title): \(days)")
            } else if daily >= 100, offer.route.realDepartures >= 2 {
                XCTAssertTrue((150...360).contains(days), "\(title): \(days)")
            } else if title != "花蓮機場 → 香港" {
                XCTAssertLessThanOrEqual(days, 720, title)
            }
        }
        XCTAssertEqual(losing.count, 4, "\(losing)")
    }

    /// Decision 762's check of the average day against the days GameCore
    /// settles: every route bought with the size the panel picks, flown
    /// `AIR_ROUTE_REPORT` days (weekdays, holidays, typhoons and the
    /// railway's riders to the airport as they come), 32 at a time.
    /// Prints Markdown and asserts nothing:
    ///
    ///     AIR_ROUTE_REPORT=28 swift test --skip-build --filter AirRouteMarketTests/testTheSettledDays
    func testTheSettledDays() throws {
        guard let text = ProcessInfo.processInfo.environment["AIR_ROUTE_REPORT"], let days = Int(text), days > 0 else {
            throw XCTSkip("set AIR_ROUTE_REPORT=<days> to fly every route")
        }
        let listings = AirRouteMarket.listings(in: taiwan())
        var rows = ["| Route | Price (NT$) | Average day (NT$) | Payback | Settled days | Settled day (NT$) | Payback |",
                    "| --- | --: | --: | --: | --: | --: | --: |"]
        for start in stride(from: 0, to: listings.count, by: AirRoute.maximumRoutes) {
            var world = taiwan()
            world.setSpeed(.normal)
            var bought: [(AirRouteListing, AirRouteEstimate, AirRouteID)] = []
            for listing in listings[start..<min(listings.count, start + AirRoute.maximumRoutes)] {
                let estimates = AirRouteMarket.estimates(listing, frequency: .real, in: world)
                let size = AirRouteMarket.suggestedSize(estimates)
                let best = try XCTUnwrap(estimates.first { $0.size == size })
                let route = try world.buyAirRoute(from: listing.airport, to: listing.destination.name, farAirport: listing.farAirport,
                                                  metres: listing.metres, size: size)
                bought.append((listing, best, route.id))
            }
            try world.advance(ticks: days * 1_440 + 2)
            for (listing, best, id) in bought {
                let route = try XCTUnwrap(world.airRoute(id: id))
                let net = route.days.reduce(Int64(0)) { $0 + $1.fares.amount - $1.running.amount - $1.landingFees.amount } / Int64(max(1, route.days.count))
                let price = try XCTUnwrap(best.offer).price.amount
                let settled = net > 0 ? String((price + net - 1) / net) : "—"
                rows.append("| \(listing.title(in: .traditionalChinese)) | \(price / 100) | \(best.dailyNet.amount / 100) | \(best.paybackDays.map(String.init) ?? "—") | \(route.days.count) | \(net / 100) | \(settled) |")
            }
        }
        print(rows.joined(separator: "\n"))
    }
}
