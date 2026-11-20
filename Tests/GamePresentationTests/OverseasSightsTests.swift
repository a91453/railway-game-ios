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
        XCTAssertEqual(AttractionCatalog.byCountry.map(\.count), [217, 21, 10, 13])
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
            let world = GameWorld.newOverseasGame(try ground(city))
            let names = world.tourism?.attractions.map(\.englishName) ?? []
            XCTAssertEqual(names, spots.map(\.englishName), "\(city)")
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
