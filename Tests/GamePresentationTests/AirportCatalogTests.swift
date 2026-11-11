import GameCore
@testable import GamePresentation
import XCTest

/// Decision 695: Taiwan's airports on a real-world map, and the words of
/// an airport's day.
final class AirportCatalogTests: XCTestCase {
    func testTheCatalogueIsWhole() {
        XCTAssertEqual(AirportCatalog.places.map(\.key), ["tpe1", "tpe2", "tsa", "rmq", "khh"])
        for place in AirportCatalog.places {
            XCTAssertFalse(place.chinese.isEmpty || place.english.isEmpty, place.key)
            XCTAssertTrue((21.8...25.4).contains(place.latitude) && (120.0...122.1).contains(place.longitude), place.key)
            XCTAssertGreaterThan(place.yearlyPassengers / 365, 0, place.key)
            XCTAssertGreaterThan(place.yearlyFlights / 365, 0, place.key)
            XCTAssertTrue(place.firstHour >= 0 && place.firstHour < place.lastHour && place.lastHour <= 24, place.key)
        }
        // Taoyuan's two terminals add up to the airport's year.
        XCTAssertEqual(AirportCatalog.places.prefix(2).reduce(0) { $0 + $1.yearlyPassengers }, 47_795_969)
        XCTAssertEqual(AirportCatalog.places.prefix(2).reduce(0) { $0 + $1.yearlyFlights }, 262_217)
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
