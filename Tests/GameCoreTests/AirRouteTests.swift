import Foundation
@testable import GameCore
import XCTest

/// Decision 758: air routes the company buys, with decision 762's values.
/// Every expectation is worked out by hand from the rules.
final class AirRouteTests: XCTestCase {
    /// Two terminals 1,000 m apart.
    private let terminal = PlanPoint(x: 31_000, y: 26_768)
    private let island = PlanPoint(x: 95_000, y: 26_768)
    /// Three passengers in four fly to Hong Kong: 30 departures a day each
    /// way ((21,900 + 365) / 730, rounded down); the island 10.
    private let hongKong = AirDestination(name: "香港", englishName: "Hong Kong", isDomestic: false, yearlyPassengers: 3_000_000, yearlyFlights: 21_900)
    private let toIsland = AirDestination(name: "離島", englishName: "Island", isDomestic: true, yearlyPassengers: 1_000_000, yearlyFlights: 7_300)
    private let toHome = AirDestination(name: "機場", englishName: "Airport", isDomestic: true, yearlyPassengers: 1_000_000, yearlyFlights: 7_300)
    /// Taoyuan to Hong Kong.
    private let abroad: Int64 = 810_000

    /// A managed company with NT$10 billion, two airports and no railway:
    /// the first's Monday is 950 thousandths of 16,000 passengers, 15,200,
    /// 11,400 of them Hong Kong's and 3,800 the island's.
    private func world(balance: Int64 = 1_000_000_000_000, first: Int = 0, last: Int = 24) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: fixtureEconomy(balance: Money(balance), costs: testCosts))
        world.setEconomyMode(.management)
        world.setSpeed(.normal)
        world.setAirports([
            Airport(id: 1, name: "機場", englishName: "Airport", point: terminal, dailyPassengers: 16_000, dailyFlights: 150,
                    firstHour: first, lastHour: last, destinations: [hongKong, toIsland]),
            Airport(id: 2, name: "離島", englishName: "Island", point: island, dailyPassengers: 3_000, dailyFlights: 40,
                    firstHour: 7, lastHour: 21, destinations: [toHome]),
        ])
        return world
    }

    func testAnOfferNamesTheRealFlightsTheAircraftAndThePrice() throws {
        let world = try world()
        let offer = try world.airRouteOffer(from: 1, to: "香港", metres: abroad, size: .narrowBody)
        XCTAssertEqual(offer.route.id, AirRouteID(rawValue: 1))
        XCTAssertEqual(offer.route.realDepartures, 30)
        XCTAssertEqual(offer.route.departures, 30)
        // 810 km at 830 km/h: 58.6 minutes, rounded up to 59, and 30 on
        // the ground; there and back with 45 at each end, 268.
        XCTAssertEqual(offer.route.flightMinutes, 89)
        // 30 × 268 = 8,040 minutes of a 1,440-minute day: 6 aircraft.
        XCTAssertEqual(offer.route.aircraft, 6)
        XCTAssertEqual(offer.aircraftPrice, Money(36_000_000_000))
        // 3,000,000 a year is 8,219 a day, each 65 days of the NT$6,060
        // fare (decision 762): NT$393,900 each.
        XCTAssertEqual(offer.dailyPassengers, 8_219)
        XCTAssertEqual(offer.value, Money(323_746_410_000))
        XCTAssertEqual(offer.price, Money(359_746_410_000))
        // NT$1,200 and 810 km at NT$6.
        XCTAssertEqual(offer.route.fare, Money(606_000))
        XCTAssertEqual(offer.route.dailySeats, 11_160)
        XCTAssertEqual(world.airRoutes, [], "an offer buys nothing")
    }

    func testBuyingPaysAndKeepsTheRoute() throws {
        var world = try world()
        let route = try world.buyAirRoute(from: 1, to: "香港", metres: abroad, size: .narrowBody)
        XCTAssertEqual(world.airRoutes, [route])
        XCTAssertEqual(world.nextAirRouteID, 2)
        XCTAssertEqual(world.economy.balance, Money(1_000_000_000_000 - 359_746_410_000))
        XCTAssertEqual(world.airRoute(id: route.id), route)
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))))
    }

    func testARouteBetweenTwoAirportsOfTheMapFliesTheLineBetweenThemAndIsBoughtOnce() throws {
        var world = try world()
        let route = try world.buyAirRoute(from: 1, to: "離島", farAirport: 2, size: .regional)
        XCTAssertEqual(route.metres, 1_000)
        XCTAssertEqual(route.realDepartures, 10)
        // 1 km at 510 km/h rounds up to a minute, and 30 on the ground:
        // 10 × 152 of 1,440 minutes, 2 aircraft.
        XCTAssertEqual(route.flightMinutes, 31)
        XCTAssertEqual(route.aircraft, 2)
        XCTAssertEqual(route.fare, Money(120_600))
        let before = world
        XCTAssertThrowsError(try world.buyAirRoute(from: 1, to: "離島", farAirport: 2, size: .commuter)) {
            XCTAssertEqual($0 as? GameError, .airRouteAlreadyBought)
        }
        XCTAssertThrowsError(try world.buyAirRoute(from: 2, to: "機場", farAirport: 1, size: .commuter), "the same route the other way") {
            XCTAssertEqual($0 as? GameError, .airRouteAlreadyBought)
        }
        XCTAssertEqual(world, before)
    }

    func testARouteTheAirportDoesNotFlyIsRefused() throws {
        var world = try world()
        let before = world
        for (airport, destination, far, metres) in [(3, "香港", nil, abroad), (1, "東京", nil, abroad), (1, "", nil, abroad),
                                                    (1, "香港", nil, nil), (1, "香港", nil, 0), (1, "香港", nil, AirRoute.maximumMetres + 1),
                                                    (1, "離島", 1, nil), (1, "離島", 9, nil)] as [(Int, String, Int?, Int64?)] {
            XCTAssertThrowsError(try world.buyAirRoute(from: airport, to: destination, farAirport: far, metres: metres, size: .narrowBody)) {
                XCTAssertEqual($0 as? GameError, .invalidAirRoute, "\(airport) \(destination) \(String(describing: far)) \(String(describing: metres))")
            }
        }
        XCTAssertEqual(world, before)
    }

    func testARouteTheCompanyCannotAffordLeavesTheWorldAsItWas() throws {
        var world = try world(balance: 100_000_000_000)
        let before = world
        XCTAssertThrowsError(try world.buyAirRoute(from: 1, to: "香港", metres: abroad, size: .narrowBody)) {
            guard case .insufficientFunds = $0 as? GameError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(world, before)
    }

    func testFewerFlightsSellAircraftForNothingAndMoreBuyThem() throws {
        var world = try world()
        let id = try world.buyAirRoute(from: 1, to: "香港", metres: abroad, size: .narrowBody).id
        let paid = world.economy.balance
        try world.setAirRouteFrequency(id, to: .reduced)
        // 15 departures: 4,020 minutes, 3 aircraft.
        XCTAssertEqual(world.airRoute(id: id)?.departures, 15)
        XCTAssertEqual(world.airRoute(id: id)?.aircraft, 3)
        XCTAssertEqual(world.economy.balance, paid)
        try world.setAirRouteFrequency(id, to: .extra)
        // 45 departures: 12,060 minutes, 9 aircraft, 6 of them new.
        XCTAssertEqual(world.airRoute(id: id)?.departures, 45)
        XCTAssertEqual(world.airRoute(id: id)?.aircraft, 9)
        XCTAssertEqual(world.economy.balance, paid - Money(36_000_000_000))
        XCTAssertThrowsError(try world.setAirRouteFrequency(AirRouteID(rawValue: 9), to: .real)) {
            XCTAssertEqual($0 as? GameError, .unknownAirRoute(AirRouteID(rawValue: 9)))
        }
    }

    func testOtherAircraftAreANewFleet() throws {
        var world = try world()
        let id = try world.buyAirRoute(from: 1, to: "香港", metres: abroad, size: .narrowBody).id
        let paid = world.economy.balance
        try world.setAirRouteSize(id, to: .wideBody)
        // 56 minutes at 870 km/h and 30: 30 × 262 minutes, 6 aircraft.
        XCTAssertEqual(world.airRoute(id: id)?.flightMinutes, 86)
        XCTAssertEqual(world.airRoute(id: id)?.aircraft, 6)
        XCTAssertEqual(world.economy.balance, paid - Money(90_000_000_000))
        try world.setAirRouteSize(id, to: .wideBody)
        XCTAssertEqual(world.economy.balance, paid - Money(90_000_000_000), "the same size buys nothing")
    }

    func testSellingARoutePutsItOnSaleAgain() throws {
        var world = try world()
        let id = try world.buyAirRoute(from: 1, to: "香港", metres: abroad, size: .narrowBody).id
        let paid = world.economy.balance
        try world.sellAirRoute(id)
        XCTAssertEqual(world.airRoutes, [])
        XCTAssertEqual(world.economy.balance, paid, "nothing is paid back")
        let again = try world.buyAirRoute(from: 1, to: "香港", metres: abroad, size: .narrowBody)
        XCTAssertEqual(again.id, AirRouteID(rawValue: 2), "a number is never used again")
        XCTAssertThrowsError(try world.sellAirRoute(id)) { XCTAssertEqual($0 as? GameError, .unknownAirRoute(id)) }
    }

    func testTheFlightsLeaveInTheAirportsHours() throws {
        var world = try world(first: 6, last: 23)
        let id = try world.buyAirRoute(from: 1, to: "香港", metres: abroad, size: .narrowBody).id
        let minutes = world.airRouteDepartureMinutes(id)
        XCTAssertEqual(minutes.count, 30)
        XCTAssertEqual(minutes, minutes.sorted())
        XCTAssertTrue(minutes.allSatisfy { (360..<1_380).contains($0) }, "\(minutes)")
        XCTAssertEqual(world.airRouteDepartureMinutes(AirRouteID(rawValue: 9)), [])
    }

    /// The first day: Hong Kong's 11,400 passengers fill 11,160 seats; the
    /// island's 3,800 fill 1,400.
    func testADayCarriesTheDestinationsPassengersAsTheSeatsHold() throws {
        var world = try world()
        let far = try world.buyAirRoute(from: 1, to: "香港", metres: abroad, size: .narrowBody).id
        let near = try world.buyAirRoute(from: 1, to: "離島", farAirport: 2, size: .regional).id
        XCTAssertEqual(world.airportDays().first?.departures.map(\.passengers), [11_400, 3_800])
        try world.advance(ticks: 1_442)
        let farDay = try XCTUnwrap(world.airRoute(id: far)?.days.last)
        // 11,160 at NT$6,060; 6 aircraft at NT$200,000 and 60 flights of
        // 810 km at NT$600; 60 landings at NT$15,000.
        XCTAssertEqual(farDay, AirRouteDay(day: 0, passengers: 11_160, fares: Money(6_762_960_000), running: Money(3_036_000_000),
                                           landingFees: Money(90_000_000), closed: false))
        let nearDay = try XCTUnwrap(world.airRoute(id: near)?.days.last)
        // 1,400 at NT$1,206; 2 aircraft at NT$60,000 and 20 flights of a
        // kilometre at NT$350; 20 landings at NT$6,000.
        XCTAssertEqual(nearDay, AirRouteDay(day: 0, passengers: 1_400, fares: Money(168_840_000), running: Money(12_700_000),
                                            landingFees: Money(12_000_000), closed: false))
        let entry = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailyAirRoutes })
        XCTAssertEqual(entry.breakdown, [
            LedgerLine(item: .airFares, amount: Money(6_931_800_000)),
            LedgerLine(item: .airRunning, amount: Money(-3_048_700_000)),
            LedgerLine(item: .landingFees, amount: Money(-102_000_000)),
        ])
        XCTAssertEqual(entry.amount, Money(3_781_100_000))
        XCTAssertEqual(world.accounts.report(.day, day: 0).current.propertyRevenue, Money(6_931_800_000))
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))))
    }

    /// Half the flights keep 800 thousandths of the passengers.
    func testFewerFlightsKeepMostOfThePassengers() throws {
        var world = try world()
        let id = try world.buyAirRoute(from: 1, to: "離島", farAirport: 2, size: .narrowBody, frequency: .reduced).id
        try world.advance(ticks: 1_442)
        // 5 departures of 186 seats both ways: 1,860; 3,800 × 0.8 = 3,040.
        XCTAssertEqual(world.airRoute(id: id)?.days.last?.passengers, 1_860)
        // 440 seats hold 4,400: the 3,040 fly, Tuesday's 950 thousandths
        // as Monday's.
        try world.setAirRouteSize(id, to: .wideBody)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.airRoute(id: id)?.days.last?.passengers, 3_040)
    }

    /// A typhoon over either end keeps the aircraft on the ground: no
    /// passenger, no flight, no landing; the upkeep is paid.
    func testATyphoonOverEitherEndGroundsTheRoute() throws {
        var world = try world()
        let id = try world.buyAirRoute(from: 1, to: "離島", farAirport: 2, size: .regional).id
        world.setDisruptions(try XCTUnwrap(Disruptions(level: .standard, country: "TW", seed: 7)))
        let stormy = try XCTUnwrap((0..<720).first { day in world.typhoons(onDay: day).contains { $0.isActive(onDay: day) && $0.covers(terminal) } })
        var flows = TouristFlows()
        let days = world.addAirportFlows(onDay: stormy, to: &flows) { _, _ in true }
        world.settleAirRoutes(day: stormy, airportDays: days, time: GameTime(seconds: (stormy + 1) * GameTime.secondsPerDay))
        XCTAssertEqual(world.airRoute(id: id)?.days.last, AirRouteDay(day: stormy, passengers: 0, fares: .zero, running: Money(12_000_000),
                                                                      landingFees: .zero, closed: true))
    }

    func testAWorldWithoutAirRoutesWritesNone() throws {
        let world = try world()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNil(object["airRoutes"])
        XCTAssertNil(object["nextAirRouteID"])
    }

    func testASaveRefusesARouteBoughtTwice() throws {
        var world = try world()
        try world.buyAirRoute(from: 1, to: "離島", farAirport: 2, size: .regional)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var saved = try XCTUnwrap(object["world"] as? [String: Any])
        var routes = try XCTUnwrap(saved["airRoutes"] as? [[String: Any]])
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: data))
        var twin = routes[0]
        twin["id"] = 2
        twin["airport"] = 2
        twin["destination"] = "機場"
        twin["farAirport"] = 1
        routes.append(twin)
        saved["airRoutes"] = routes
        saved["nextAirRouteID"] = 3
        object["world"] = saved
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    /// The version 103 save: a day after buying Taoyuan's Hong Kong route
    /// and the island's, both with their first day's takings; it loads as
    /// the same world and flies on the same. Written with
    /// `AIR_ROUTE_SAVE_NEW=1` by the build that first made it.
    func testTheVersion103SaveKeepsItsAirRoutes() throws {
        var world = try world()
        try world.buyAirRoute(from: 1, to: "香港", metres: abroad, size: .narrowBody)
        try world.buyAirRoute(from: 1, to: "離島", farAirport: 2, size: .regional, frequency: .extra)
        try world.advance(ticks: 1_442)
        let url = SavedGameTests.fixtures.appendingPathComponent("v103-air-routes.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["AIR_ROUTE_SAVE_NEW"] != nil, SavedGame.currentVersion == 103 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 103)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.airRoutes.map(\.destination), ["香港", "離島"])
        XCTAssertEqual(loaded.airRoutes.map(\.frequency), [.real, .extra])
        XCTAssertEqual(loaded.airRoutes.map { $0.days.count }, [1, 1])
        // What the routes cost and their first day are the save's own,
        // under the values of the build that wrote it (decision 758):
        // later builds' values (decision 762) never rewrite them.
        XCTAssertEqual(loaded.airRoutes.map(\.value), [Money(82_190_000_000), Money(27_390_000_000)])
        XCTAssertEqual(loaded.airRoutes.map { $0.days[0].running }, [Money(4_980_000_000), Money(13_050_000)])
        XCTAssertEqual(loaded.airRoutes.map(\.aircraft), world.airRoutes.map(\.aircraft))
        var again = try JSONDecoder().decode(SavedGame.self, from: data).world
        try loaded.advance(ticks: 1_440)
        try again.advance(ticks: 1_440)
        XCTAssertEqual(loaded, again, "a loaded save runs on the same way each time")
        XCTAssertEqual(loaded.airRoutes.map { $0.days.count }, [2, 2])
        XCTAssertEqual(loaded.airRoutes[0].days[1].running, Money(3_036_000_000), "the next day is this build's")
    }
}
