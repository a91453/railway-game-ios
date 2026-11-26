import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 894: Hong Kong's, Finland's and Japan's sights, each country's
/// in a table of its own, on their maps and in older saves.
final class OverseasSightsTests: XCTestCase {
    private func ground(_ city: OverseasMap) throws -> OverseasGround {
        try OverseasGround(city: city, pack: try XCTUnwrap(HongKongRailwaysTests.pack(city)))
    }

    private let tables: [(OverseasMap, [AttractionCatalog.Spot], String)] = [
        (.hongKong, AttractionCatalog.hongKongSpots, "hk"),
        (.rovaniemi, AttractionCatalog.finlandSpots, "fi"),
        (.fukuoka, AttractionCatalog.japanSpots, "jp"),
    ]

    /// Each country's table: Taiwan's first, then Hong Kong's, Finland's
    /// and Japan's; every id and name once across them all.
    func testEachCountryHasATableOfItsOwn() {
        XCTAssertEqual(AttractionCatalog.byCountry.map(\.count), [217, 21, 10, 88])
        XCTAssertEqual(AttractionCatalog.allSpots.map(\.id), AttractionCatalog.byCountry.flatMap { $0 }.map(\.id))
        XCTAssertEqual(Set(AttractionCatalog.allSpots.map(\.id)).count, AttractionCatalog.allSpots.count)
        XCTAssertEqual(Set(AttractionCatalog.allSpots.map(\.name)).count, AttractionCatalog.allSpots.count)
        XCTAssertEqual(Set(AttractionCatalog.allSpots.map(\.englishName)).count, AttractionCatalog.allSpots.count)
        for (_, spots, prefix) in tables {
            XCTAssertTrue(spots.allSatisfy { $0.id.hasPrefix(prefix) && (100...500).contains($0.stars) }, prefix)
        }
        XCTAssertEqual(AttractionCatalog.hongKongSpots.first?.name, "天壇大佛", "decision 880's first keeps its number")
    }

    /// A new game on each map holds all of its own country's sights and
    /// none of another's, two or three of them asking for a line.
    func testANewGameOnEachMapHoldsItsOwnCountrysSights() throws {
        for (city, spots, _) in tables {
            // As the player gets it: a map that grew (Japan's, to Kumamoto)
            // gets the sights of its new ground when the game opens.
            let world = AttractionCatalog.withSights(GameWorld.newOverseasGame(try ground(city)))
            let names = world.tourism?.attractions.map(\.englishName) ?? []
            // Decision 994: Japan's table covers three prefectures; a map
            // holds the ones inside its bounds, in the table's order.
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            let inside = AttractionCatalog.attractions(in: frame, bounds: world.bounds, only: Set(spots.map(\.id))).map(\.englishName)
            XCTAssertEqual(Set(names), Set(inside), "\(city)")
            XCTAssertEqual(names.count, inside.count, "\(city)")
            if city == .fukuoka {
                XCTAssertTrue(Set(spots.prefix(13).map(\.englishName)).isSubset(of: Set(names)), "Fukuoka city's thirteen are all on the map")
                XCTAssertTrue(inside.contains("Kumamoto Castle"), "the map reaches Kumamoto")
                XCTAssertTrue(inside.contains("Hirado Castle"), "decision 997: the map reaches Hirado")
            } else {
                XCTAssertEqual(names, spots.map(\.englishName), "\(city)")
            }
            let alerted = spots.filter { $0.stars >= GameWorld.alertedSightStars }.count
            XCTAssertTrue((2...3).contains(alerted), "\(city): \(alerted)")
        }
    }

    /// A Hong Kong game saved after decision 880, holding only the Tian
    /// Tan Buddha with a souvenir shop, keeps it as it is and gets the
    /// others after it; opened again it changes nothing.
    func testAnOlderHongKongSaveKeepsItsBuddhaAndGetsTheRest() throws {
        var world = GameWorld.newOverseasGame(try ground(.hongKong), balance: Money(100_000_000))
        world.setEconomyMode(.management)
        let buddha = try XCTUnwrap(world.tourism?.attractions.first)
        world.setTourism([buddha])
        try world.investInSouvenirShop(of: buddha.id)
        let shop = try XCTUnwrap(world.tourism?.attractions.first)
        XCTAssertEqual(shop.souvenir, 1)

        let opened = AttractionCatalog.withSights(world)
        let sights = try XCTUnwrap(opened.tourism?.attractions)
        XCTAssertEqual(sights.first, shop, "the Buddha keeps its number, shop and counts")
        XCTAssertEqual(sights.map(\.englishName), AttractionCatalog.hongKongSpots.map(\.englishName))
        XCTAssertEqual(sights.map(\.id.rawValue), Array(1...AttractionCatalog.hongKongSpots.count))
        XCTAssertEqual(AttractionCatalog.withSights(opened), opened)
    }

    /// Decision 994: every Japanese sight lies in Fukuoka, Saga or
    /// Kumamoto prefecture, decision 997: or Nagasaki (their box:
    /// 32.0–34.3 N, 129.3–131.4 E), and a
    /// Fukuoka game saved before them gets those inside its map after its
    /// own, keeping its own numbers.
    func testJapansSightsCoverTheThreePrefecturesAndReachOlderSaves() throws {
        for spot in AttractionCatalog.japanSpots {
            XCTAssertTrue((32.0...34.3).contains(spot.latitude) && (129.3...131.4).contains(spot.longitude), spot.name)
        }
        var world = AttractionCatalog.withSights(GameWorld.newOverseasGame(try ground(.fukuoka)))
        let all = try XCTUnwrap(world.tourism?.attractions)
        XCTAssertGreaterThan(all.count, 13)
        let older = Set(AttractionCatalog.japanSpots.prefix(13).map(\.englishName))
        world.setTourism(all.filter { older.contains($0.englishName) })
        let opened = AttractionCatalog.withSights(world)
        let sights = try XCTUnwrap(opened.tourism?.attractions)
        XCTAssertEqual(Set(sights.map(\.englishName)), Set(all.map(\.englishName)))
        XCTAssertEqual(Array(sights.prefix(13)), Array(world.tourism?.attractions ?? []))
        XCTAssertEqual(sights.map(\.id.rawValue), Array(1...sights.count))
    }

    /// Taiwan's maps are left as they are: none of the overseas sights lie
    /// on them.
    func testTaiwansMapsGetNoOverseasSights() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170))
        let world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 128 * Land.cellLength, height: 128 * Land.cellLength), land: [])
        XCTAssertEqual(AttractionCatalog.withSights(world), world)
        let overseas = Set(AttractionCatalog.byCountry.dropFirst().flatMap { $0 }.map(\.englishName))
        XCTAssertTrue(world.tourism?.attractions.allSatisfy { !overseas.contains($0.englishName) } ?? true)
    }
}
