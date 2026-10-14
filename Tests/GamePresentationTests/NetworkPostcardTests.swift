import GameCore
@testable import GamePresentation
import XCTest

/// Decision 215: the network postcard's words, its map's region and its
/// layout.
final class NetworkPostcardTests: XCTestCase {
    func testTheDemoNetworkPostcardSaysWhatTheCompanyHas() {
        let world = DemoWorld.make(in: .traditionalChinese)
        let postcard = NetworkPostcard(world: world, companyName: "  沿線鐵道 ", in: .traditionalChinese)
        let figures = CompanyFigures(world: world)

        XCTAssertEqual(postcard.title, "沿線鐵道")
        XCTAssertEqual(postcard.eyebrow, "ALONG THE LINE ・ 沿線")
        XCTAssertEqual(
            postcard.subtitle,
            "\(world.clock.now.date.text(in: .traditionalChinese)) ・ \(CompanyRank(world: world).title.title(in: .traditionalChinese))"
        )
        XCTAssertEqual(postcard.figures.map(\.label), ["條路線", "座車站", "路網長度", "昨日旅客"])
        XCTAssertEqual(postcard.figures[0].value, "\(world.lines.count)")
        XCTAssertEqual(postcard.figures[1].value, "\(world.stations.count)")
        XCTAssertEqual(postcard.figures[2].value, RankMeasure.network.valueText(figures.trackMetres))
        XCTAssertEqual(postcard.figures[3].value, Money(figures.yesterdayRiders).displayText)
        // The demo map is the game's own: no base map, no real railways.
        XCTAssertEqual(postcard.credit, "")
    }

    func testEnglishLabelsCountTheirThings() {
        let postcard = NetworkPostcard.figures(lines: 1, figures: CompanyFigures(yesterdayRiders: 12_345, trackMetres: 3_400, stations: 5), in: .english)
        XCTAssertEqual(postcard.map(\.label), ["line", "stations", "of track", "riders yesterday"])
        XCTAssertEqual(postcard[3].value, "12,345")
        XCTAssertEqual(postcard[2].value, "3.4 km")
    }

    func testTheCompanyNameIsTrimmedCutAndNeverEmpty() {
        XCTAssertEqual(NetworkPostcard.companyName(" \n ", in: .traditionalChinese), "我的鐵道")
        XCTAssertEqual(NetworkPostcard.companyName("", in: .english), "My Railway")
        XCTAssertEqual(NetworkPostcard.companyName("北海\n岸線", in: .english), "北海 岸線")
        let long = String(repeating: "鐵", count: 30)
        XCTAssertEqual(NetworkPostcard.companyName(long, in: .english).count, NetworkPostcard.nameLimit)
    }

    func testARealWorldMapCreditsItsRailways() {
        let world = LiuMingchuanChallenge.make()
        XCTAssertNotNil(world.geoAnchor)
        let postcard = NetworkPostcard(world: world, companyName: "", in: .english)
        XCTAssertEqual(postcard.credit, DataSourceCredits.mapCorner(baseMap: false, railways: true, in: .english))
    }

    func testTheMapShowsTheNetworkWithRoomRoundIt() throws {
        let world = DemoWorld.make(in: .english)
        let built = try XCTUnwrap(WorldRegion.built(in: world))
        let region = NetworkPostcard(world: world, companyName: "", in: .english).region
        XCTAssertLessThan(region.minX, built.minX)
        XCTAssertLessThan(region.minY, built.minY)
        XCTAssertGreaterThan(region.maxX, built.maxX)
        XCTAssertGreaterThan(region.maxY, built.maxY)
        // Fitted into the postcard's map, the whole network is in view.
        let frame = PostcardLayout.map
        let projection = PostcardProjection(region: region, size: ScreenSize(width: frame.width, height: frame.height))
        for station in world.stations {
            let point = projection.screenPoint(of: station.location)
            XCTAssertTrue((0...frame.width).contains(point.x) && (0...frame.height).contains(point.y), station.name)
        }
    }

    func testANewMapShowsTheWholeMap() throws {
        let world = GameWorld(bounds: try WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        XCTAssertEqual(NetworkPostcard(world: world, companyName: "", in: .english).region, WorldRegion(bounds: world.bounds))
    }

    func testTheProjectionIsNoCloserThanTheMapsClosestZoom() {
        let tiny = WorldRegion(minX: 0, minY: 0, maxX: 10, maxY: 10)
        let projection = PostcardProjection(region: tiny, size: ScreenSize(width: 380, height: 296))
        XCTAssertEqual(projection.referenceSize, MapScale.largestSize, accuracy: 1e-9)
        let middle = projection.screenPoint(worldX: 5, worldY: 5)
        XCTAssertEqual(middle.x, 190, accuracy: 1e-9)
        XCTAssertEqual(middle.y, 148, accuracy: 1e-9)
        let back = projection.worldPosition(at: middle)
        XCTAssertEqual(back.x, 5, accuracy: 1e-9)
        XCTAssertEqual(back.y, 5, accuracy: 1e-9)
    }

    func testThePartsStayOnTheCardAndApart() {
        let card = PostcardLayout.Frame(
            x: PostcardLayout.border, y: PostcardLayout.border,
            width: PostcardLayout.size.width - 2 * PostcardLayout.border,
            height: PostcardLayout.size.height - 2 * PostcardLayout.border
        )
        let figures = (0..<4).map(PostcardLayout.figure)
        let parts = [PostcardLayout.eyebrow, PostcardLayout.title, PostcardLayout.subtitle, PostcardLayout.map, PostcardLayout.credit, PostcardLayout.stationMaster] + figures
        for part in parts {
            XCTAssertTrue(card.contains(part), "\(part)")
        }
        // The words and figures never touch one another, the map or the
        // station master; only the badge sits over the map's corner.
        let apart = [PostcardLayout.eyebrow, PostcardLayout.title, PostcardLayout.subtitle, PostcardLayout.credit] + figures
        for (index, part) in apart.enumerated() {
            for other in apart[(index + 1)...] {
                XCTAssertFalse(part.intersects(other), "\(part) \(other)")
            }
            XCTAssertFalse(part.intersects(PostcardLayout.map), "\(part)")
            XCTAssertFalse(part.intersects(PostcardLayout.stationMaster), "\(part)")
        }
        XCTAssertTrue(PostcardLayout.stationMaster.intersects(PostcardLayout.map))
        XCTAssertEqual(PostcardLayout.size.width * PostcardLayout.scale, 1_200)
        XCTAssertEqual(PostcardLayout.size.height * PostcardLayout.scale, 1_500)
    }
}
