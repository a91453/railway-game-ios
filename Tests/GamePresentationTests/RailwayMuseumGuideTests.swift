import GameCore
@testable import GamePresentation
import XCTest

/// Decision 696: the railway museum's page, exhibit by exhibit.
final class RailwayMuseumGuideTests: XCTestCase {
    /// No museum, no page.
    func testAWorldWithoutAMuseumHasNoGuide() throws {
        let world = try makeWorld(width: 40_960, height: 40_960)
        XCTAssertNil(RailwayMuseumGuide(world: world, in: .english))
    }

    /// The exhibits come first, in the museum's order, each with its
    /// track and the garage's key; then the types never owned, as
    /// silhouettes with neither; no type twice.
    func testTheExhibitsThenTheTypesNeverOwned() throws {
        let world = ScreenshotScene.museumWorld(in: .traditionalChinese)
        let museum = try XCTUnwrap(world.railwayMuseum)
        XCTAssertFalse(museum.exhibits.isEmpty)
        let guide = try XCTUnwrap(RailwayMuseumGuide(world: world, in: .traditionalChinese))
        XCTAssertEqual(guide.shown, museum.exhibits.count)
        XCTAssertEqual(Array(guide.items.prefix(guide.shown).map(\.type)), museum.exhibits)
        XCTAssertTrue(guide.items.prefix(guide.shown).allSatisfy { $0.isShown && $0.place != nil })
        let waiting = guide.items.dropFirst(guide.shown)
        XCTAssertFalse(waiting.isEmpty)
        XCTAssertTrue(waiting.allSatisfy { !$0.isShown && $0.place == nil && $0.showcaseKey == nil })
        XCTAssertEqual(Set(guide.items.map(\.type)).count, guide.items.count)
        XCTAssertEqual(Set(waiting.map(\.type)), Set(RollingStockCatalog(world: world).entries.map(\.type)).subtracting(museum.exhibits))
        // An exhibit the 3D map draws with its own model opens in the garage.
        for item in guide.items.prefix(guide.shown) {
            let own = Map3DTrainSet.key(type: item.type, performance: item.type.spec.performance ?? .standard)
            let drawn = Map3DModelPack.standard.drawnSet(forKey: own, count: Map3DRailwayMuseum.cars(of: own))?.key ?? own
            XCTAssertEqual(item.showcaseKey, Map3DShowcase.entry(drawn) == nil ? nil : drawn, item.name)
            XCTAssertFalse(item.name.isEmpty)
        }
        // The scene's five (three metros, the steam train, the EMU3000) all have one.
        XCTAssertTrue(guide.items.prefix(guide.shown).allSatisfy { $0.showcaseKey != nil })
        XCTAssertTrue(guide.summary.contains("\(guide.shown) 種"))
        XCTAssertTrue(guide.hint.contains("隔天"))
    }

    /// The page says what the sights panel's row says: the same stars and
    /// the same visitors.
    func testThePageAgreesWithTheSightsPanel() throws {
        let world = ScreenshotScene.museumWorld(in: .english)
        let row = try XCTUnwrap(world.attractionRows(in: .english).first { $0.exhibitsText != nil })
        let guide = try XCTUnwrap(RailwayMuseumGuide(world: world, row: row, in: .english))
        XCTAssertTrue(guide.summary.contains(row.starsText))
        XCTAssertTrue(guide.summary.contains("today \(row.today), yesterday \(row.yesterday)"))
        // Without the row, the museum's own stars.
        let plain = try XCTUnwrap(RailwayMuseumGuide(world: world, in: .english))
        XCTAssertTrue(plain.summary.contains(StationMasterAdvice.starsText(Tourism.museumStars(exhibits: plain.shown))))
    }

    /// An empty museum says how exhibits come, and every type it could
    /// show is a silhouette.
    func testAnEmptyMuseumSaysHowExhibitsCome() throws {
        var world = try makeWorld(width: 40_960, height: 40_960, balance: 1_000_000_000)
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "老街", englishName: "Old Street",
                                     point: PlanPoint(x: 12_000, y: 30_000), kind: .town, baseStars: 300)])
        try world.placeBuilding(.railwayMuseum, at: PlanPoint(x: 20_480, y: 20_480))
        let guide = try XCTUnwrap(RailwayMuseumGuide(world: world, in: .english))
        XCTAssertEqual(guide.shown, 0)
        XCTAssertTrue(guide.hint.contains("next day"))
        XCTAssertFalse(guide.items.isEmpty)
        XCTAssertTrue(guide.items.allSatisfy { !$0.isShown })
    }
}
