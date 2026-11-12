import GameCore
@testable import GamePresentation
import XCTest

/// Decision 695: Taiwan's airports on a real-world map, and the words of
/// an airport's day.
final class AirportCatalogTests: XCTestCase {
    func testTheCatalogueIsWhole() {
        XCTAssertEqual(AirportCatalog.places.map(\.key), ["tpe1", "tpe2", "tsa", "rmq", "khh", "mzg", "hun", "ttt", "tnn", "cyi", "cmj", "kyd", "gni"])
        XCTAssertLessThanOrEqual(AirportCatalog.places.count, AirportRules.maximumAirports)
        for place in AirportCatalog.places {
            XCTAssertFalse(place.chinese.isEmpty || place.english.isEmpty, place.key)
            XCTAssertTrue((21.8...25.4).contains(place.latitude) && (119.3...122.1).contains(place.longitude), place.key)
            XCTAssertGreaterThan(place.yearlyPassengers / 365, 0, place.key)
            XCTAssertGreaterThan(place.yearlyFlights / 365, 0, place.key)
            XCTAssertTrue(place.firstHour >= 0 && place.firstHour < place.lastHour && place.lastHour <= 24, place.key)
        }
        // Taoyuan's two terminals add up to the airport's year.
        XCTAssertEqual(AirportCatalog.places.prefix(2).reduce(0) { $0 + $1.yearlyPassengers }, 47_795_969)
        XCTAssertEqual(AirportCatalog.places.prefix(2).reduce(0) { $0 + $1.yearlyFlights }, 262_217)
    }

    /// Decision 700: every airport's destinations add up to its year.
    func testTheDestinationsAddUpToEachAirportsYear() throws {
        for place in AirportCatalog.places {
            let list = AirportCatalog.destinations(of: place)
            XCTAssertFalse(list.isEmpty, place.key)
            XCTAssertLessThanOrEqual(list.count, AirportRules.maximumDestinations, place.key)
            let named = list.filter { !$0.isRest }
            XCTAssertEqual(Set(named.map(\.name)).count, named.count, place.key)
            XCTAssertLessThanOrEqual(list.count - named.count, 2, "one rest of each kind at most: \(place.key)")
            for route in place.routes {
                XCTAssertNotNil(AirportCatalog.destinations[route.to], "\(place.key) \(route.to)")
            }
            let passengers = list.reduce(Int64(0)) { $0 + $1.yearlyPassengers }, flights = list.reduce(Int64(0)) { $0 + $1.yearlyFlights }
            // Within a thousandth: a route's carried passengers and the
            // airport's counted ones differ by a few, and a terminal's
            // share rounds down.
            XCTAssertLessThanOrEqual(abs(passengers - place.yearlyPassengers), place.yearlyPassengers / 1_000 + 1, place.key)
            XCTAssertLessThanOrEqual(flights, place.yearlyFlights, place.key)
            XCTAssertGreaterThan(flights * 10, place.yearlyFlights * 7, place.key)
        }
        func share(_ key: String) throws -> Int64 {
            let place = try XCTUnwrap(AirportCatalog.places.first { $0.key == key })
            return Airport(id: 1, name: place.chinese, englishName: place.english, point: PlanPoint(x: 0, y: 0), dailyPassengers: 1, dailyFlights: 1,
                           destinations: AirportCatalog.destinations(of: place)).domesticShare
        }
        // Taoyuan has no domestic flights; Songshan's 2,598,347 domestic
        // passengers of 5,624,611; the islands' airports fly at home only.
        XCTAssertEqual(try share("tpe1"), 0)
        XCTAssertEqual(try share("tsa"), 461)
        XCTAssertEqual(try share("khh"), 176)
        XCTAssertEqual(try share("kyd"), 1_000)
        // Hong Kong is a destination of every airport that flies there.
        for key in ["tpe1", "tpe2", "rmq", "khh", "hun"] {
            let place = try XCTUnwrap(AirportCatalog.places.first { $0.key == key })
            XCTAssertTrue(AirportCatalog.destinations(of: place).contains { $0.name == "香港" && !$0.isDomestic }, key)
        }
        // Kinmen and Matsu are destinations, not airports of the map.
        XCTAssertFalse(AirportCatalog.places.contains { $0.chinese.contains("金門") || $0.chinese.contains("馬祖") })
    }

    func testTheWholeOfTaiwanHoldsThirteenAirports() {
        let airports = AirportCatalog.airports(in: RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds), bounds: WholeTaiwan.bounds)
        XCTAssertEqual(airports.map(\.name), AirportCatalog.places.map(\.chinese))
        XCTAssertEqual(airports.map(\.id), Array(1...13))
        XCTAssertTrue(airports.allSatisfy { $0.dailyPassengers > 0 && $0.dailyFlights > 0 && !$0.destinations.isEmpty })
    }

    func testAnEarlierCataloguesAirportsGetTheDestinations() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitude: 250_478_000, longitude: 1_215_170_000))
        let bounds = try WorldBounds(width: 1 << 21, height: 1 << 21)
        var world = GameWorld.newGame(anchor: anchor, bounds: bounds, balance: Money(1_000_000_000), land: [], rules: .simple)
        let today = world.airports
        XCTAssertFalse(try XCTUnwrap(today.first).destinations.isEmpty)
        // As decision 695 set them: no destinations.
        world.setAirports(today.map {
            Airport(id: $0.id, name: $0.name, englishName: $0.englishName, point: $0.point, dailyPassengers: $0.dailyPassengers,
                    dailyFlights: $0.dailyFlights, firstHour: $0.firstHour, lastHour: $0.lastHour)
        })
        XCTAssertEqual(world.airports.first?.destinations, [])
        XCTAssertEqual(AirportCatalog.withAirports(world).airports, today)
        // Airports that are not the catalogue's are left alone.
        let other = [Airport(id: 1, name: "機場", englishName: "Airport", point: PlanPoint(x: 31_000, y: 26_768), dailyPassengers: 16_000, dailyFlights: 150)]
        world.setAirports(other)
        XCTAssertEqual(AirportCatalog.withAirports(world).airports, other)
    }

    func testTheWordsOfAnAirportsDestinations() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitude: 250_478_000, longitude: 1_215_170_000))
        let world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 21, height: 1 << 21), balance: Money(1_000_000_000), land: [], rules: .simple)
        let day = try XCTUnwrap(world.airportDays().first)
        XCTAssertEqual(day.departures.reduce(0) { $0 + $1.flights }, day.flights / 2)
        XCTAssertEqual(day.departures.reduce(0) { $0 + $1.passengers }, day.passengers)
        let chinese = try XCTUnwrap(day.destinationsText(in: .traditionalChinese)), english = try XCTUnwrap(day.destinationsText(in: .english))
        // Songshan's four busiest by flights: Penghu, Kinmen, Tokyo Haneda, Matsu Nangan.
        for name in ["國內線", "國際及兩岸航線", "今天飛往：", "澎湖", "金門", "東京羽田", "馬祖南竿", "其他"] {
            XCTAssertTrue(chinese.contains(name), "\(name): \(chinese)")
        }
        XCTAssertFalse(chinese.contains("臺東"), chinese)
        for name in ["domestic", "cross-strait", "Penghu", "Kinmen", "Tokyo Haneda", "others"] {
            XCTAssertTrue(english.contains(name), "\(name): \(english)")
        }
        // An airport that lists none says nothing.
        var plain = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: GameEconomy(balance: 1_000_000))
        plain.setAirports([Airport(id: 1, name: "機場", englishName: "Airport", point: PlanPoint(x: 31_000, y: 26_768), dailyPassengers: 16_000, dailyFlights: 150)])
        XCTAssertNil(try XCTUnwrap(plain.airportDays().first).destinationsText(in: .english))
    }

    func testOnlyTheAirportsOnTheMapAreSet() throws {
        // A map 32 km across round Taipei Main Station holds Songshan only.
        let anchor = try XCTUnwrap(GeoAnchor(latitude: 250_478_000, longitude: 1_215_170_000))
        let bounds = try WorldBounds(width: 1 << 21, height: 1 << 21)
        let airports = AirportCatalog.airports(in: RealWorldFrame(anchor: anchor, bounds: bounds), bounds: bounds)
        XCTAssertEqual(airports.map(\.name), ["臺北松山機場"])
        XCTAssertEqual(airports.first?.id, 1)
        XCTAssertEqual(airports.first?.dailyPassengers, 5_624_611 / 365)
        XCTAssertEqual(airports.first?.firstHour, 6)
        var world = GameWorld.newGame(anchor: anchor, bounds: bounds, balance: Money(1_000_000_000), land: [], rules: .simple)
        XCTAssertEqual(world.airports, airports, "a new real-world game has them")
        // A save from before airports gets them when the app opens it.
        world.setAirports([])
        XCTAssertEqual(AirportCatalog.withAirports(world).airports, airports)
        XCTAssertEqual(AirportCatalog.withAirports(AirportCatalog.withAirports(world)).airports, airports)
        var blank = GameWorld(bounds: bounds, economy: GameEconomy(balance: 1_000_000))
        blank.setTourism(nil)
        XCTAssertEqual(AirportCatalog.withAirports(blank).airports, [], "not a real-world map")
    }

    func testTheWordsOfAnAirportsDay() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: GameEconomy(balance: 1_000_000))
        world.setAirports([Airport(id: 1, name: "機場", englishName: "Airport", point: PlanPoint(x: 31_000, y: 26_768), dailyPassengers: 16_000, dailyFlights: 150)])
        let day = try XCTUnwrap(world.airportDays().first)
        for language in DisplayLanguage.allCases {
            XCTAssertEqual(day.airport.title(in: language), language.text("Airport", "機場"))
            let summary = day.summary(in: language)
            XCTAssertTrue(summary.contains("142"), summary)
            XCTAssertTrue(summary.contains(language.text("15,200", "15,200")), summary)
            XCTAssertTrue(summary.contains(language.text("No station yet", "還沒有車站")), summary)
            XCTAssertNil(day.yesterdayText(in: language))
            XCTAssertNil(day.growthText(in: language))
        }
    }

    func testTheScreenshotSceneShowsAServedAirportAndOneWithNoStation() throws {
        let world = ScreenshotScene.airport.make(in: .traditionalChinese)
        let days = world.airportDays()
        XCTAssertEqual(days.count, 2)
        let served = days[0], alone = days[1]
        XCTAssertNotNil(served.station)
        // Home's 9,000 at one rider for 60: 150 each way.
        XCTAssertEqual(served.ridersTo, 150)
        XCTAssertEqual(served.ridersFrom, 150)
        XCTAssertEqual(served.airport.yesterdayRiders, 300)
        XCTAssertTrue(served.summary(in: .traditionalChinese).contains("150 人搭你的車離開機場"), served.summary(in: .traditionalChinese))
        XCTAssertNotNil(served.yesterdayText(in: .english))
        XCTAssertNotNil(served.growthText(in: .english))
        XCTAssertNil(alone.station)
        XCTAssertEqual(alone.riders, 0)
        XCTAssertTrue(alone.summary(in: .english).contains("No station yet"))
        // The station's panel has the airport's day too.
        XCTAssertEqual(world.stationRidership(of: try XCTUnwrap(served.station)).airports.map(\.airport.id), [1])
    }
}
