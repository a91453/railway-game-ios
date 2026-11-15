@testable import GameCore
import GamePresentation
import XCTest

/// Decision 772: the catalog's landmarks, museums and temples, and the
/// names an older save's towns are told by.
final class SightKindsCatalogTests: XCTestCase {
    private let split: Set<AttractionKind> = [.landmark, .museum, .temple]

    func testTheCatalogsKindsAreThoseAnOldSaveIsToldBy() {
        let catalog = Dictionary(uniqueKeysWithValues: AttractionCatalog.spots.filter { split.contains($0.kind) }.map { ($0.englishName, $0.kind) })
        let known = Tourism.sightKindsByName.filter { !GameWorld.blankSightKinds.keys.contains($0.key) }
        XCTAssertEqual(catalog, known)
        XCTAssertEqual(catalog.values.count { $0 == .landmark }, 20)
        XCTAssertEqual(catalog.values.count { $0 == .museum }, 10)
        XCTAssertEqual(catalog.values.count { $0 == .temple }, 13)
    }

    func testTheFamousOnesHaveTheirKinds() {
        let kinds = Dictionary(uniqueKeysWithValues: AttractionCatalog.spots.map { ($0.name, $0.kind) })
        XCTAssertEqual(kinds["台北101"], .landmark)
        XCTAssertEqual(kinds["國立故宮博物院"], .museum)
        XCTAssertEqual(kinds["艋舺龍山寺"], .temple)
        XCTAssertEqual(kinds["大甲鎮瀾宮"], .temple)
        XCTAssertEqual(kinds["九份"], .town, "an old street stays a town")
    }

    func testEachKindHasAName() {
        XCTAssertEqual(AttractionKind.landmark.title(in: .traditionalChinese), "地標")
        XCTAssertEqual(AttractionKind.museum.title(in: .traditionalChinese), "博物館")
        XCTAssertEqual(AttractionKind.temple.title(in: .traditionalChinese), "廟宇")
        XCTAssertEqual(AttractionKind.temple.title(in: .english), "Temple")
    }
}
