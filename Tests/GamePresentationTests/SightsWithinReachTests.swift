import GameCore
@testable import GamePresentation
import XCTest

/// Review L16-1 (decision 663's fold of the sights off the company's map):
/// a sight a station can serve, or that has a souvenir shop, is not folded
/// away, because the folded row shows no status and no shop button while
/// the rules serve it whoever owns the ground under it.
final class SightsWithinReachTests: XCTestCase {
    /// A blank map bought tile by tile, owning its middle tile, with a
    /// sight 300 m off the tile's west edge and one two tiles east.
    private func world() throws -> GameWorld {
        var world = GameWorld.newGame(eventSeed: 3, buysMap: true)
        let owned = try XCTUnwrap(world.mapExpansion?.owned.first)
        let area = world.mapArea(of: owned)
        let middle = PlanPoint(x: (area.minX + area.maxX) / 2, y: (area.minY + area.maxY) / 2)
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "遠湖", englishName: "Far Lake",
                       point: PlanPoint(x: area.maxX + 2 * MapExpansion.tileLength, y: middle.y), kind: .mountain, baseStars: 450),
            Attraction(id: AttractionID(rawValue: 2), name: "界外亭", englishName: "Edge Pavilion",
                       point: PlanPoint(x: area.minX - 300 * WorldCoordinate.unitsPerMetre, y: middle.y), kind: .coast, baseStars: 300),
        ])
        return world
    }

    /// A station on the company's own ground reaches 800 m, so a sight
    /// 300 m past the edge is listed in full: its status, and a shop to
    /// open.
    func testASightAStationOnTheMapCanReachIsNotFolded() throws {
        let rows = try world().attractionRows(in: .english)
        let edge = try XCTUnwrap(rows.first { $0.name == "Edge Pavilion" })
        XCTAssertNil(edge.offMapMetres, "folded away with a shop to open: \(String(describing: edge.nextShop))")
        XCTAssertNotNil(edge.nextShop)
        XCTAssertEqual(edge.status, .noStation)
        // The far one stays folded, after it.
        XCTAssertEqual(rows.map(\.name), ["Edge Pavilion", "Far Lake"])
        XCTAssertNotNil(rows[1].offMapMetres)
    }

    /// A shop already opened at a far sight keeps its row whole, so the
    /// player sees it and can raise it.
    func testASightWithAShopIsNotFolded() throws {
        var world = try world()
        try world.investInSouvenirShop(of: AttractionID(rawValue: 1))
        let far = try XCTUnwrap(world.attractionRows(in: .english).first { $0.name == "Far Lake" })
        XCTAssertEqual(far.souvenir, 1)
        XCTAssertNil(far.offMapMetres)
        XCTAssertNotNil(far.nextShop)
    }

    /// The rule itself: folded only when nothing serves it, it has no
    /// shop, and it lies farther off than a station reaches. A sight a
    /// cableway, ferry or bus brings tourists to has a station however
    /// far off it lies.
    func testWhatIsFolded() {
        let reach = Tourism.reach / WorldCoordinate.unitsPerMetre
        XCTAssertEqual(reach, 800)
        XCTAssertNil(AttractionRow.foldedOffMapMetres(distance: nil, hasStation: false, souvenir: 0))
        XCTAssertNil(AttractionRow.foldedOffMapMetres(distance: 300, hasStation: false, souvenir: 0))
        XCTAssertNil(AttractionRow.foldedOffMapMetres(distance: reach, hasStation: false, souvenir: 0))
        XCTAssertEqual(AttractionRow.foldedOffMapMetres(distance: reach + 1, hasStation: false, souvenir: 0), reach + 1)
        XCTAssertNil(AttractionRow.foldedOffMapMetres(distance: 5_000, hasStation: true, souvenir: 0))
        XCTAssertNil(AttractionRow.foldedOffMapMetres(distance: 5_000, hasStation: false, souvenir: 1))
        XCTAssertEqual(AttractionRow.foldedOffMapMetres(distance: 5_000, hasStation: false, souvenir: 0), 5_000)
    }

    /// Under a kilometre the distance is in metres, not "about 1 km".
    func testAShortDistanceIsInMetres() {
        func text(_ metres: Int64, _ language: DisplayLanguage) -> String {
            AttractionRow.offMapText(metres: metres, in: language)
        }
        XCTAssertEqual(text(840, .english), "About 800 m off your map")
        XCTAssertEqual(text(860, .traditionalChinese), "在你的地圖外約 900 公尺")
        XCTAssertEqual(text(960, .english), "About 1 km off your map")
        XCTAssertEqual(text(8_192, .english), "About 8 km off your map")
    }
}
