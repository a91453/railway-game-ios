import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 585: the collection's ferry page.
final class FerryCollectionTests: XCTestCase {
    func testPagesAndNames() {
        // Decision 632: trains, ferries, cable cars, in that order; decision 701: then aircraft.
        XCTAssertEqual(FerryCollection.Page.allCases, [.trains, .ferries, .cableways, .aircraft])
        XCTAssertEqual(FerryCollection.Page.allCases.map { $0.title(in: .traditionalChinese) }, ["列車", "渡輪", "纜車", "飛機"])
        XCTAssertEqual(FerryCollection.Page.allCases.map { $0.title(in: .english) }, ["Trains", "Ferries", "Cable Cars", "Aircraft"])
        XCTAssertEqual(FerryCollection.Page.allCases.map(\.exhibit), [nil, .ferries, .cableways, .aircraft])
        XCTAssertEqual(FerryCollection.name(in: .traditionalChinese), "圖鑑")
        XCTAssertEqual(FerryCollection.name(in: .english), "Collection")
    }

    func testBoatsAndRoutesInBothLanguages() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let entries = FerryCollection.boats(in: language) + FerryCollection.routes(in: language)
            XCTAssertEqual(entries.map(\.id), ["shunfeng166", "chigu2", "tamsuiBali", "gushanCijin", "centralTsimShaTsui", "wanChaiTsimShaTsui"])
            XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
            XCTAssertTrue(entries.allSatisfy { !$0.lines.isEmpty })
        }
        let chinese = FerryCollection.boats(in: .traditionalChinese)
        XCTAssertTrue(chinese[0].lines.contains { $0.contains("99 人") })
        XCTAssertTrue(chinese[1].lines.contains { $0.contains("170 人") })
        let routes = FerryCollection.routes(in: .traditionalChinese)
        XCTAssertTrue(routes[0].lines[0].contains(RealFerry.tamsuiBali.legMetres.reduce(0, +).groupedText))
        // Both crossings give their hours and fare.
        XCTAssertTrue(routes[0].lines.contains { $0.contains(FerryRoute.fare.moneyText) })
        XCTAssertTrue(routes[1].lines.contains { $0.contains(FerryCollection.gushanCijinFare.moneyText) && $0.contains("5:00") })
        // Decision 981: Victoria Harbour's two, each with its crossing's
        // length, its hours and its fare in Hong Kong dollars; every real
        // ferry the tool lays has its entry.
        XCTAssertEqual(routes.map(\.title), RealFerry.all.map(\.name))
        XCTAssertEqual(FerryCollection.routes(in: .english).map(\.title), RealFerry.all.map(\.englishName))
        for (entry, real) in zip(routes[2...], [RealFerry.centralTsimShaTsui, .wanChaiTsimShaTsui]) {
            XCTAssertTrue(entry.lines[0].contains(real.legMetres.reduce(0, +).groupedText), entry.id)
            XCTAssertTrue(entry.lines[1].contains("HK$5.0") && entry.lines[1].contains("23:"), entry.id)
        }
    }

    /// The real crossings find their piers on the shore of the game's own
    /// water (from OpenStreetMap): Taiwan's (decision 105) and, decision
    /// 981, Hong Kong's map pack's (decision 726).
    func testRealFerriesFindTheirPiersOnTheRealWater() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let taiwan = try WaterGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_water.json")))
        let hongKong = try WaterGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/MapPacks/hongkong/water.json")))
        XCTAssertEqual(RealFerry.all.count, 4)
        for real in RealFerry.all {
            let grid = [RealFerry.centralTsimShaTsui, .wanChaiTsimShaTsui].contains(real) ? hongKong : taiwan
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
