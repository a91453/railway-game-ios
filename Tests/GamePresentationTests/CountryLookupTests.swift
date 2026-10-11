import GameCore
@testable import GamePresentation
import XCTest

/// Decision 154: a real-world map keeps the holidays of the country it lies
/// in, looked up in Natural Earth's borders.
final class CountryLookupTests: XCTestCase {
    private func country(_ latitude: Double, _ longitude: Double) -> String {
        CountryLookup.country(at: GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded()))!)
    }

    func testEveryCountryWithHolidaysHasABorderAndEveryBorderHolidays() {
        XCTAssertEqual(Set(CountryLookup.encodedBorders.keys), Set(HolidayCalendar.countries.keys))
        for border in CountryLookup.borders {
            XCTAssertFalse(border.rings.isEmpty, border.country)
            XCTAssertTrue(border.rings.allSatisfy { $0.count >= 3 }, border.country)
        }
    }

    func testCitiesLieInTheirCountries() {
        let cities: [(String, Double, Double, String)] = [
            ("台北車站", 25.0478, 121.5170, "TW"), ("高雄", 22.6394, 120.3025, "TW"), ("花蓮", 23.9930, 121.6011, "TW"),
            ("馬公", 23.5654, 119.5793, "TW"), ("金城（金門）", 24.4321, 118.3171, "TW"), ("南竿（馬祖）", 26.1597, 119.9512, "TW"),
            ("基隆港", 25.1330, 121.7400, "TW"),
            ("廈門", 24.4798, 118.0894, "CN"), ("上海", 31.2304, 121.4737, "CN"), ("北京", 39.9042, 116.4074, "CN"),
            ("香港中環", 22.2819, 114.1582, "HK"), ("深圳北站", 22.6097, 114.0294, "CN"),
            ("東京", 35.6812, 139.7671, "JP"), ("那霸", 26.2124, 127.6809, "JP"), ("首爾", 37.5665, 126.9780, "KR"),
            ("新加坡", 1.2903, 103.8519, "SG"), ("曼谷", 13.7563, 100.5018, "TH"), ("河內", 21.0278, 105.8342, "VN"),
            ("雅加達", -6.2088, 106.8456, "ID"), ("德里", 28.6139, 77.2090, "IN"),
            ("杜拜", 25.2048, 55.2708, "AE"), ("利雅德", 24.7136, 46.6753, "SA"),
            ("倫敦", 51.5072, -0.1276, "GB"), ("巴黎", 48.8566, 2.3522, "FR"), ("史特拉斯堡", 48.5734, 7.7521, "FR"),
            ("柏林", 52.5200, 13.4050, "DE"), ("阿姆斯特丹", 52.3676, 4.9041, "NL"), ("華沙", 52.2297, 21.0122, "PL"),
            ("紐約", 40.7128, -74.0060, "US"), ("西雅圖", 47.6062, -122.3321, "US"), ("水牛城", 42.8864, -78.8784, "US"),
            ("多倫多", 43.6532, -79.3832, "CA"), ("溫哥華", 49.2827, -123.1207, "CA"),
            ("墨西哥城", 19.4326, -99.1332, "MX"), ("聖保羅", -23.5505, -46.6333, "BR"), ("約翰尼斯堡", -26.2041, 28.0473, "ZA"),
            ("雪梨", -33.8688, 151.2093, "AU"), ("奧克蘭", -36.8485, 174.7633, "NZ"),
        ]
        for (name, latitude, longitude, expected) in cities {
            XCTAssertEqual(country(latitude, longitude), expected, name)
        }
    }

    func testElsewhereIsTaiwanTheGamesHome() {
        // The open Pacific, and countries without holidays here.
        XCTAssertEqual(country(0, -150), HolidayCalendar.home)
        XCTAssertEqual(country(55.7558, 37.6173), HolidayCalendar.home, "Moscow")
        XCTAssertEqual(country(-12.0464, -77.0428), HolidayCalendar.home, "Lima")
    }

    func testANewRealWorldGameKeepsItsCountrysHolidaysAndABlankOneTaiwans() {
        let tokyo = GeoAnchor(latitude: 356_812_000, longitude: 1_397_671_000)!
        XCTAssertEqual(GameWorld.newGame(anchor: tokyo).disruptions, Disruptions(level: .light, country: "JP"))
        XCTAssertEqual(GameWorld.newGame().disruptions, Disruptions(level: .light, country: "TW"))
        XCTAssertNil(GameWorld.newGame(challenge: .threeTowns, eventSeed: 1).disruptions)
    }
}
