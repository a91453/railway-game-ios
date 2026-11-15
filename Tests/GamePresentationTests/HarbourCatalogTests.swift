@testable import GameCore
import GamePresentation
import XCTest

/// Decision 773: the catalog's harbours, and the names an older save's
/// coasts are told by.
final class HarbourCatalogTests: XCTestCase {
    func testTheCatalogsHarboursAreThoseAnOldSaveIsToldBy() {
        let catalog = Set(AttractionCatalog.spots.filter { $0.kind == .harbour }.map(\.englishName))
        // Decision 774's two came after: no older save has them.
        let added: Set = ["Longfeng Fishing Port", "Budai Fishing Port"]
        XCTAssertEqual(catalog.subtracting(added), Tourism.harbourNames.subtracting([GameWorld.blankHarbourName]))
        XCTAssertTrue(catalog.isSuperset(of: added))
        XCTAssertEqual(catalog.count, 12)
    }

    func testTheFamousOnesHaveTheirKinds() {
        let kinds = Dictionary(uniqueKeysWithValues: AttractionCatalog.spots.map { ($0.name, $0.kind) })
        XCTAssertEqual(kinds["淡水漁人碼頭"], .harbour)
        XCTAssertEqual(kinds["南方澳"], .harbour)
        XCTAssertEqual(kinds["正濱漁港"], .harbour)
        XCTAssertEqual(kinds["龍鳳漁港"], .harbour)
        XCTAssertEqual(kinds["布袋漁港"], .harbour)
        XCTAssertEqual(kinds["旗津"], .coast, "an island beach stays a coast")
        XCTAssertEqual(kinds["駁二藝術特區"], .town, "an art district on the pier stays a town")
    }

    func testABlankMapsFishingHarbourIsOne() {
        for seed: UInt32 in 0..<40 {
            for sight in GameWorld.newGame(eventSeed: seed).tourism?.attractions ?? [] {
                XCTAssertEqual(sight.kind == .harbour, sight.englishName == GameWorld.blankHarbourName, "seed \(seed), \(sight.englishName)")
            }
        }
    }

    func testTheKindHasAName() {
        XCTAssertEqual(AttractionKind.harbour.title(in: .traditionalChinese), "港口碼頭")
        XCTAssertEqual(AttractionKind.harbour.title(in: .english), "Harbour")
    }
}
