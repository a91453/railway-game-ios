import Foundation
@testable import GameCore
import GamePresentation
import XCTest

/// Stage E2 (ARCHITECTURE decision 50): a real-world game's map lies over
/// the Earth with its middle at the world's anchor; the places a game can
/// start at are the references' own.
final class RealWorldMapTests: XCTestCase {
    private let taipei = RealWorldPlace.standard.anchor

    // MARK: - Degrees

    func testDegreesRoundToTenMillionths() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.047_930_84, longitudeDegrees: 121.517_004_56))
        XCTAssertEqual(anchor, GeoAnchor(latitude: 250_479_308, longitude: 1_215_170_046))
        XCTAssertEqual(anchor.latitudeDegrees, 25.047_930_8, accuracy: 1e-12)
        XCTAssertEqual(anchor.longitudeDegrees, 121.517_004_6, accuracy: 1e-12)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: anchor.latitudeDegrees, longitudeDegrees: anchor.longitudeDegrees), anchor)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: -33.7, longitudeDegrees: -58.381_6), GeoAnchor(latitude: -337_000_000, longitude: -583_816_000))
    }

    /// A map panned round the Earth reports longitudes past ±180°.
    func testLongitudesComeBackRoundTheEarth() {
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 190)?.longitude, -1_700_000_000)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: -190)?.longitude, 1_700_000_000)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 180)?.longitude, -1_800_000_000, "180° east is 180° west")
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: -180)?.longitude, -1_800_000_000)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 179.999_999_99)?.longitude, -1_800_000_000, "rounds to 180°")
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 540)?.longitude, -1_800_000_000)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 721.5)?.longitude, 15_000_000)
    }

    func testOnlyTheEarthsLatitudes() {
        XCTAssertNotNil(GeoAnchor(latitudeDegrees: 90, longitudeDegrees: 0))
        XCTAssertNotNil(GeoAnchor(latitudeDegrees: -90, longitudeDegrees: 0))
        XCTAssertNil(GeoAnchor(latitudeDegrees: 90.000_001, longitudeDegrees: 0))
        XCTAssertNil(GeoAnchor(latitudeDegrees: -91, longitudeDegrees: 0))
        XCTAssertNil(GeoAnchor(latitudeDegrees: .nan, longitudeDegrees: 0))
        XCTAssertNil(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: .infinity))
    }

    // MARK: - The frame

    /// The middle of a new game's 16 km map is at the anchor; its edges are
    /// 8,192 m away, and a world metre is 64 units.
    func testTheMapsMiddleIsAtTheAnchor() throws {
        let world = GameWorld.newGame(anchor: taipei)
        XCTAssertEqual(world.bounds, .standard, "16,384 m a side, as the map of 1024 tiles was (Stage F3d)")
        XCTAssertEqual(GameWorld.newGame().bounds, .standard)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        XCTAssertEqual(frame.anchor, taipei)
        XCTAssertEqual(frame.middleX, 524_288)
        XCTAssertEqual(frame.middleY, 524_288)
        XCTAssertEqual(RealWorldFrame.halfExtent(of: world.bounds).east, 8_192)
        XCTAssertEqual(RealWorldFrame.halfExtent(of: world.bounds).south, 8_192)

        let middle = frame.metresFromAnchor(worldX: 524_288, worldY: 524_288)
        XCTAssertEqual(middle.east, 0)
        XCTAssertEqual(middle.south, 0)
        let corner = frame.metresFromAnchor(worldX: 0, worldY: 0)
        XCTAssertEqual(corner.east, -8_192)
        XCTAssertEqual(corner.south, -8_192)
        let point = frame.metresFromAnchor(worldX: 524_288 + 640, worldY: 524_288 - 32)
        XCTAssertEqual(point.east, 10)
        XCTAssertEqual(point.south, -0.5)
        let back = frame.worldPosition(east: 10, south: -0.5)
        XCTAssertEqual(back.x, 524_928)
        XCTAssertEqual(back.y, 524_256)
    }

    /// An old save's 32 × 24 map has its middle at the anchor too.
    func testAnySizeOfMapHasItsMiddleThere() throws {
        let frame = RealWorldFrame(anchor: taipei, bounds: try WorldBounds(width: 32_768, height: 24_576))
        XCTAssertEqual(frame.middleX, 16_384)
        XCTAssertEqual(frame.middleY, 12_288)
        XCTAssertEqual(RealWorldFrame.halfExtent(of: try WorldBounds(width: 32_768, height: 24_576)).east, 256)
        // Bounds need not be whole tiles (Stage F3d).
        let odd = RealWorldFrame(anchor: taipei, bounds: try WorldBounds(width: 1_000, height: 333))
        XCTAssertEqual(odd.middleX, 500)
        XCTAssertEqual(odd.middleY, 166.5)
        XCTAssertEqual(RealWorldFrame.halfExtent(of: try WorldBounds(width: 1_000, height: 333)).south, 2.6015625)
    }

    func testABlankMapHasNoFrame() {
        XCTAssertNil(RealWorldFrame(world: .newGame()))
        XCTAssertNil(RealWorldFrame(world: DemoWorld.make(in: .english)))
    }

    // MARK: - New games

    /// A real-world new game is a new game on a map laid over the Earth:
    /// the same money, prices, city and empty map, but that the company's
    /// buildings buy out the city's by area (decision 146).
    func testARealWorldNewGameIsANewGameOverTheEarth() {
        let real = GameWorld.newGame(anchor: taipei)
        XCTAssertEqual(real.geoAnchor, taipei)
        XCTAssertTrue(real.areaBuyOut)
        var blank = real
        blank.setGeoAnchor(nil)
        blank.setAreaBuyOut(false)
        // A real-world map has Taiwan's sights, a blank one its drawn ones (decision 174).
        blank.setTourism(nil)
        var plain = GameWorld.newGame()
        plain.setTourism(nil)
        // A blank map's towns have roads, a real-world map none yet (decision 400).
        XCTAssertNotNil(plain.roads)
        plain.roads = nil
        XCTAssertEqual(blank, plain)
        XCTAssertNil(GameWorld.newGame().geoAnchor)
    }

    @MainActor
    func testTheLauncherStartsARealWorldGameAndKeepsItsAnchor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RealWorldMapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        let paris = try XCTUnwrap(RealWorldPlace.all.first { $0.id == "paris" }).anchor
        do {
            let launcher = GameLauncher(library: library, language: .english)
            launcher.startNewGame(at: paris)
            let seed = try XCTUnwrap(launcher.session?.world.demandEvents?.seed)
            var expected = GameWorld.newGame(anchor: paris, eventSeed: seed, rules: .simple)
            // A real-world new game has riders changing from real railways (decision 298).
            expected.setRealTransfers(true)
            // And riders switching to scooters and cars (decision 332).
            try expected.setModeShift(.simple)
            XCTAssertEqual(launcher.session?.world, expected)
            launcher.returnToStart()
            let autosave = try XCTUnwrap(launcher.autosave)
            XCTAssertEqual(autosave.summary?.realWorld, true)
            XCTAssertEqual(autosave.summary?.text(in: .english), "Real-world map · Day 1 · 00:00 · $ 3,000,000 · 0 stations · 0 lines · 0 trains")
            XCTAssertEqual(autosave.summary?.text(in: .traditionalChinese), "實景地圖 · 第 1 日 · 00:00 · $ 3,000,000 · 0 座車站 · 0 條路線 · 0 列列車")
            await launcher.continueGame()?.value
            XCTAssertEqual(launcher.session?.world.geoAnchor, paris)

            launcher.startNewGame()
            XCTAssertNil(launcher.session?.world.geoAnchor, "a blank map")
            launcher.returnToStart()
            XCTAssertNil(launcher.autosave?.summary?.realWorld)
        }
    }

    /// A save list written before E2 has no `"realWorld"`, and reads as a
    /// blank map's.
    func testSummariesFromBeforeE2ReadAsBlankMaps() throws {
        let json = #"{"seconds": 60, "balance": 100, "stations": 1, "lines": 0, "trains": 0}"#
        let summary = try JSONDecoder().decode(SaveSummary.self, from: Data(json.utf8))
        XCTAssertNil(summary.realWorld)
        XCTAssertFalse(summary.text(in: .english).contains("Real-world"))
        let blank = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SaveSummary(world: .newGame()))) as? [String: Any])
        XCTAssertNil(blank["realWorld"], "written only on a real-world map")
    }

    // MARK: - Places

    /// The references' places: the 22 Taiwan places of
    /// `Railway/` (decision 442), the 53 cities of `Ci/` and the 127 main stations of
    /// decision 262.
    func testThePlacesAreTheReferences() {
        let places = RealWorldPlace.all
        XCTAssertEqual(places.count, 202)
        XCTAssertEqual(Set(places.map(\.id)).count, 202)
        XCTAssertEqual(Set(places.map(\.anchor)).count, 202)
        XCTAssertEqual(Set(places.map { $0.name(in: .english) }).count, 202)
        XCTAssertEqual(Set(places.map { $0.name(in: .traditionalChinese) }).count, 202)
        XCTAssertEqual(places.filter { $0.country == "TW" }.count, 22)
        XCTAssertTrue(places.filter { $0.country == "TW" }.allSatisfy { $0.id.hasPrefix("tra-") || $0.id.hasPrefix("moi-") })
        XCTAssertEqual(RealWorldPlace.standard.id, "tra-taipei")
        XCTAssertEqual(RealWorldPlace.standard.name(in: .english), "Taipei")
        XCTAssertEqual(RealWorldPlace.standard.name(in: .traditionalChinese), "臺北")
        // `Ci/`'s Shanghai: center [31.2304, 121.4737].
        XCTAssertEqual(places.first { $0.id == "shanghai" }?.anchor, GeoAnchor(latitude: 312_304_000, longitude: 1_214_737_000))
        XCTAssertEqual(places.first { $0.id == "london" }?.anchor, GeoAnchor(latitude: 515_074_000, longitude: -1_278_000))
        // Wikidata's Tokyo Station (Q283196): 35.6808333, 139.7669444.
        XCTAssertEqual(places.first { $0.id == "tokyo" }?.anchor, GeoAnchor(latitude: 356_808_333, longitude: 1_397_669_444))
        XCTAssertEqual(places.first { $0.id == "tokyo" }?.name(in: .traditionalChinese), "東京")
        for place in places {
            XCTAssertNotEqual(place.name(in: .english), place.name(in: .traditionalChinese), place.id)
            // Apple's maps (Web Mercator) show up to about 85°.
            XCTAssertLessThan(abs(place.anchor.latitudeDegrees), 85, place.id)
            XCTAssertEqual(place.country.count, 2, place.id)
            XCTAssertEqual(place.country, place.country.uppercased(), place.id)
            XCTAssertGreaterThan(place.population, 0, place.id)
        }
        let japan = ["tokyo", "yokohama", "osaka", "nagoya", "sapporo", "fukuoka", "kobe", "kyoto", "kawasaki", "saitama", "hiroshima",
                     "sendai", "kitakyushu", "chiba", "okayama", "kumamoto", "niigata", "shizuoka", "hamamatsu", "kagoshima", "naha"]
        let korea = ["seoul", "busan", "incheon", "daegu", "daejeon", "gwangju", "ulsan", "suwon"]
        XCTAssertEqual(Set(places.filter { $0.country == "JP" }.map(\.id)), Set(japan))
        XCTAssertEqual(Set(places.filter { $0.country == "KR" }.map(\.id)), Set(korea))
        for region in RealWorldPlace.Region.allCases {
            XCTAssertTrue(places.contains { $0.region == region }, "\(region)")
            XCTAssertNotEqual(region.name(in: .english), region.name(in: .traditionalChinese))
        }
    }

    /// The list: a country with four places or more has a group of its
    /// own, Taiwan, Japan, South Korea, China and the United States first,
    /// then the others with the most places first (Brazil's and
    /// Pakistan's four by their codes); the rest by region (decision 262).
    func testTheListGroupsByCountryThenRegion() throws {
        let groups = RealWorldPlace.groups
        XCTAssertEqual(groups.map(\.id), [
            "country-TW", "country-JP", "country-KR", "country-CN", "country-US", "country-IN", "country-BR", "country-PK",
            "region-asia", "region-europe", "region-americas", "region-oceaniaAndAfrica",
        ])
        XCTAssertEqual(groups.map { $0.name(in: .traditionalChinese) }, [
            "台灣", "日本", "韓國", "中國", "美國", "印度", "巴西", "巴基斯坦", "其他亞洲", "歐洲", "其他美洲", "大洋洲與非洲",
        ])
        XCTAssertEqual(groups.map { $0.name(in: .english) }, [
            "Taiwan", "Japan", "South Korea", "China", "United States", "India", "Brazil", "Pakistan",
            "Other Asia", "Europe", "Other Americas", "Oceania and Africa",
        ])
        // Every place once.
        XCTAssertEqual(groups.flatMap(\.places).map(\.id).sorted(), RealWorldPlace.all.map(\.id).sorted())
        for group in groups {
            XCTAssertFalse(group.places.isEmpty, group.id)
            if case .country(let code) = group.kind {
                XCTAssertGreaterThanOrEqual(group.places.count, RealWorldPlace.countryGroupMinimum, group.id)
                XCTAssertTrue(group.places.allSatisfy { $0.country == code }, group.id)
                XCTAssertNotEqual(group.name(in: .english), code, "\(code) has a name")
            }
        }
        // Taiwan north to south and round the east, as `Railway/` lists them.
        XCTAssertEqual(groups[0].places.map(\.id), RealWorldPlace.all.filter { $0.country == "TW" }.map(\.id))
        // The others largest first; places of one city in the list's order.
        for group in groups.dropFirst() {
            XCTAssertEqual(group.places.map(\.population), group.places.map(\.population).sorted(by: >), group.id)
        }
        XCTAssertEqual(groups[1].places.prefix(6).map(\.id), ["tokyo", "yokohama", "kawasaki", "saitama", "chiba", "osaka"])
        XCTAssertEqual(groups[3].places.first?.id, "shanghai")
        // Hong Kong and Macau are Asia's, each its own place.
        let asia = try XCTUnwrap(groups.first { $0.kind == .region(.asia) })
        XCTAssertTrue(asia.places.contains { $0.id == "hongkong" })
        XCTAssertTrue(asia.places.contains { $0.id == "macau" })
    }

    /// Typing a name finds the city in either language, whatever the
    /// case, accents, spaces or 臺/台.
    func testCitiesMatchTheirNames() {
        XCTAssertEqual(RealWorldPlace.matching("").count, 0)
        XCTAssertEqual(RealWorldPlace.matching("東京").map(\.id), ["tokyo"])
        XCTAssertEqual(RealWorldPlace.matching("tokyo").map(\.id), ["tokyo"])
        XCTAssertEqual(RealWorldPlace.matching("TOK").first?.id, "tokyo")
        XCTAssertEqual(RealWorldPlace.matching("sao paulo").map(\.id), ["saopaulo"])
        XCTAssertEqual(RealWorldPlace.matching("台北").map(\.id), ["tra-taipei"])
        XCTAssertEqual(RealWorldPlace.matching("xi'an").map(\.id), ["xian", "xianyang"])
        XCTAssertEqual(RealWorldPlace.matching("首爾").map(\.id), ["seoul"])
        // Names that start with it first.
        XCTAssertEqual(RealWorldPlace.matching("new").first?.id, "newyork")
        XCTAssertTrue(RealWorldPlace.matching("zzz").isEmpty)
    }

    /// Every place starts a game: a new world over the Earth with its
    /// middle at the place (decision 262).
    func testEveryPlaceStartsAGame() throws {
        for place in RealWorldPlace.all {
            let world = GameWorld.newGame(anchor: place.anchor)
            XCTAssertEqual(world.geoAnchor, place.anchor, place.id)
            let frame = try XCTUnwrap(RealWorldFrame(world: world), place.id)
            XCTAssertEqual(frame.anchor, place.anchor, place.id)
        }
    }
}
