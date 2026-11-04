import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 585: the collection's ferry page.
final class FerryCollectionTests: XCTestCase {
    func testPagesAndNames() {
        XCTAssertEqual(FerryCollection.Page.allCases, [.trains, .ferries])
        XCTAssertEqual(FerryCollection.Page.allCases.map { $0.title(in: .traditionalChinese) }, ["列車", "渡輪"])
        XCTAssertEqual(FerryCollection.name(in: .traditionalChinese), "圖鑑")
        XCTAssertEqual(FerryCollection.name(in: .english), "Collection")
    }

    func testBoatsAndRoutesInBothLanguages() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let entries = FerryCollection.boats(in: language) + FerryCollection.routes(in: language)
            XCTAssertEqual(entries.map(\.id), ["shunfeng166", "chigu2", "tamsuiBali", "gushanCijin"])
            XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
            XCTAssertTrue(entries.allSatisfy { !$0.lines.isEmpty })
        }
        let chinese = FerryCollection.boats(in: .traditionalChinese)
        XCTAssertTrue(chinese[0].lines.contains { $0.contains("99 人") })
        XCTAssertTrue(chinese[1].lines.contains { $0.contains("170 人") })
        let routes = FerryCollection.routes(in: .traditionalChinese)
        XCTAssertTrue(routes[0].lines[0].contains(RealFerry.tamsuiBali.legMetres.reduce(0, +).groupedText))
    }

    /// Both real crossings find their piers on the shore of the game's own
    /// map of Taiwan's water (decision 105, from OpenStreetMap).
    func testRealFerriesFindTheirPiersOnTheRealWater() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let grid = try WaterGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_water.json")))
        for real in RealFerry.all {
            let latitude = real.piers.map(\.latitude).reduce(0, +) / Double(real.piers.count)
            let longitude = real.piers.map(\.longitude).reduce(0, +) / Double(real.piers.count)
            let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
            let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
            let world = GameWorld.newGame(anchor: anchor, water: grid.cells(frame: frame, bounds: GameWorld.newGameBounds))
            let piers = try XCTUnwrap(real.piers(in: world), real.englishName)
            XCTAssertEqual(piers.count, real.piers.count)
            XCTAssertTrue(piers.allSatisfy { world.isPierCell(row: $0.row, column: $0.column) })
        }
    }
}
